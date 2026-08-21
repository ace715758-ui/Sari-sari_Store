<script setup lang="ts">
import { ref, onUnmounted, computed } from 'vue'
import QRCode from 'qrcode'
import { supabase } from '../lib/supabase'

type ScanResult = {
  barcode: string
  name: string
  category: string
  piecesPerPack: number
  sellingMode: 'pack' | 'per-piece'
  isNew: boolean
}

const emit = defineEmits<{
  'scan-result': [result: ScanResult]
  'close': []
}>()

type ModalState = 'generating' | 'waiting' | 'expired' | 'error'

const state = ref<ModalState>('generating')
const qrDataUrl = ref('')
const sessionId = ref('')
const errorMsg = ref('')
const scanCount = ref(0)
const EXPIRY_MINUTES = 20

let realtimeChannel: any = null
let expiryTimer: ReturnType<typeof setTimeout> | null = null

const scanUrl = computed(() => {
  // In production, window.location.origin is the real domain (e.g. https://your-app.vercel.app).
  // For LOCAL DEV only: phones can't reach "localhost" — set VITE_APP_URL in your .env file
  // to your machine's local IP, e.g. VITE_APP_URL=http://192.168.1.42:5173
  // Phone and desktop must be on the same WiFi for this to work locally.
  // This env var is NOT needed once deployed to a real domain.
  const base = import.meta.env.VITE_APP_URL || window.location.origin
  return `${base}/scan?session=${sessionId.value}`
})

// ── Create session and generate QR ────────────────────────────────
async function createSession() {
  if (!supabase) { state.value = 'error'; errorMsg.value = 'Supabase not configured.'; return }

  state.value = 'generating'
  cleanup()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) { state.value = 'error'; errorMsg.value = 'Not signed in.'; return }

  const { data, error } = await supabase
    .from('scan_sessions')
    .insert({ user_id: user.id, status: 'waiting' })
    .select('id')
    .single()

  if (error || !data) {
    state.value = 'error'
    errorMsg.value = 'Could not create scan session.'
    return
  }

  sessionId.value = data.id

  // Generate QR code
  qrDataUrl.value = await QRCode.toDataURL(scanUrl.value, {
    width: 260,
    margin: 2,
    color: { dark: '#0f172a', light: '#f8fafc' },
  })

  state.value = 'waiting'
  subscribeToSession(data.id)

  // Auto-expire after 10 minutes
  expiryTimer = setTimeout(() => {
    if (state.value === 'waiting') {
      state.value = 'expired'
      cleanup()
    }
  }, EXPIRY_MINUTES * 60 * 1000)
}

// ── Realtime subscription ─────────────────────────────────────────
function subscribeToSession(id: string) {
  if (!supabase) return

  realtimeChannel = supabase
    .channel(`scan-session-${id}`)
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'scan_sessions',
        filter: `id=eq.${id}`,
      },
      async (payload) => {
        const row = payload.new as { status: string; scanned_barcode: string | null }
        // Only process 'scanned' status — ignore the reset back to 'waiting'
        if (row.status === 'scanned' && row.scanned_barcode) {
          scanCount.value++
          await handleScannedBarcode(row.scanned_barcode)
          // Don't cleanup — keep listening for more scans
        }
      }
    )
    .subscribe()
}

// ── Look up barcode and emit result ──────────────────────────────
async function handleScannedBarcode(barcode: string) {
  if (!supabase) return

  const { data } = await supabase
    .from('barcode_products')
    .select('name, category, pieces_per_pack, selling_mode')
    .eq('barcode', barcode)
    .maybeSingle()

  if (data) {
    emit('scan-result', {
      barcode,
      name: data.name,
      category: data.category,
      piecesPerPack: data.pieces_per_pack ?? 1,
      sellingMode: data.selling_mode ?? 'pack',
      isNew: false,
    })
  } else {
    emit('scan-result', {
      barcode,
      name: '',
      category: '',
      piecesPerPack: 1,
      sellingMode: 'pack',
      isNew: true,
    })
  }
}

function cleanup() {
  if (realtimeChannel && supabase) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  if (expiryTimer) {
    clearTimeout(expiryTimer)
    expiryTimer = null
  }
}

function cancel() {
  cleanup()
  emit('close')
}

function copyUrl() {
  navigator.clipboard.writeText(scanUrl.value)
}

onUnmounted(cleanup)

// Start immediately
createSession()
</script>

<template>
  <div class="modal-backdrop" @click.self="cancel">
    <div class="modal">

      <!-- Generating -->
      <div v-if="state === 'generating'" class="center-state">
        <div class="spinner"></div>
        <p>Creating scan session...</p>
      </div>

      <!-- Error -->
      <div v-else-if="state === 'error'" class="center-state">
        <p class="err-text">{{ errorMsg }}</p>
        <button class="btn-secondary" @click="cancel">Close</button>
      </div>

      <!-- Expired -->
      <div v-else-if="state === 'expired'" class="center-state">
        <div class="expired-icon">⏱</div>
        <h3>Session Expired</h3>
        <p>The QR code has expired (10 minutes).</p>
        <button class="btn-primary" @click="createSession">Generate New Code</button>
        <button class="btn-secondary" @click="cancel">Cancel</button>
      </div>

      <!-- Waiting for scan -->
      <template v-else>
        <div class="modal-header">
          <h3>Scan with Phone</h3>
          <button class="close-btn" @click="cancel">✕</button>
        </div>

        <p class="instruction">
          Open this link on your phone and scan the product barcode.
        </p>

        <!-- QR Code -->
        <div class="qr-wrap">
          <img :src="qrDataUrl" alt="Scan QR code" class="qr-img" />
        </div>

        <!-- Plain-text URL for copy/paste -->
        <div class="url-box">
          <span class="url-text">{{ scanUrl }}</span>
          <button class="copy-btn" @click="copyUrl">Copy</button>
        </div>

        <!-- Waiting indicator -->
        <div class="waiting-row">
          <div class="pulse-dot"></div>
          <span>{{ scanCount > 0 ? `${scanCount} scanned — waiting for more...` : 'Waiting for scan...' }}</span>
        </div>

        <p class="expiry-note">Session expires in {{ EXPIRY_MINUTES }} minutes · <span class="end-link" @click="cancel">End session</span></p>
      </template>

    </div>
  </div>
</template>

<style scoped>
.modal-backdrop {
  position: fixed; inset: 0; z-index: 500;
  background: rgba(0,0,0,0.72);
  backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
  padding: 16px;
}

.modal {
  background: #0f172a;
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 20px;
  padding: 28px 24px;
  width: min(420px, 100%);
  display: flex;
  flex-direction: column;
  gap: 14px;
  box-shadow: 0 24px 60px rgba(0,0,0,0.6);
  animation: slide-up 0.2s ease;
}
@keyframes slide-up {
  from { transform: translateY(20px); opacity: 0; }
  to   { transform: translateY(0);    opacity: 1; }
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.modal-header h3 { margin: 0; font-size: 18px; }

.close-btn {
  padding: 4px 10px; border: 1px solid rgba(255,255,255,0.12); border-radius: 8px;
  background: rgba(255,255,255,0.06); color: #cbd5e1; cursor: pointer; font-size: 14px;
}

.instruction {
  font-size: 14px; color: #94a3b8; line-height: 1.5; margin: 0;
}

.qr-wrap {
  display: flex; justify-content: center;
  background: #f8fafc; border-radius: 14px; padding: 12px;
}
.qr-img { width: 220px; height: 220px; display: block; }

.url-box {
  display: flex; align-items: center; gap: 8px;
  background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1);
  border-radius: 10px; padding: 8px 12px;
}
.url-text {
  flex: 1; font-size: 11px; color: #64748b;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-family: monospace;
}
.copy-btn {
  padding: 4px 10px; border-radius: 7px; border: 1px solid rgba(34,197,94,0.35);
  background: rgba(34,197,94,0.1); color: #22c55e; font-size: 12px;
  font-weight: 700; cursor: pointer; white-space: nowrap;
}

.waiting-row {
  display: flex; align-items: center; gap: 10px;
  font-size: 14px; color: #94a3b8;
}
.pulse-dot {
  width: 10px; height: 10px; border-radius: 50%; background: #22c55e;
  animation: pulse 1.4s ease-in-out infinite;
  flex-shrink: 0;
}
@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%       { opacity: 0.4; transform: scale(0.8); }
}

.expiry-note {
  font-size: 12px; color: #475569; margin: 0; text-align: center;
}
.end-link {
  color: #f87171; cursor: pointer; text-decoration: underline;
}

/* Center states */
.center-state {
  display: flex; flex-direction: column; align-items: center;
  gap: 14px; text-align: center; padding: 16px 0;
}
.center-state p { color: #94a3b8; font-size: 14px; }
.expired-icon { font-size: 48px; color: #fbbf24; }
.center-state h3 { margin: 0; font-size: 18px; }
.err-text { color: #fca5a5; font-size: 14px; }

.btn-primary {
  padding: 10px 24px; border: none; border-radius: 10px;
  background: linear-gradient(135deg, #059669, #34d399);
  color: white; font-weight: 700; cursor: pointer; font-size: 14px; width: 100%;
}
.btn-secondary {
  padding: 9px 24px; border-radius: 10px; width: 100%;
  background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.12);
  color: #cbd5e1; font-size: 14px; font-weight: 600; cursor: pointer;
}

.spinner {
  width: 36px; height: 36px;
  border: 3px solid rgba(255,255,255,0.1); border-top-color: #22c55e;
  border-radius: 50%; animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
