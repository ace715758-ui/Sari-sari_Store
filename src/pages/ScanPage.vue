<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../lib/supabase'
import { BrowserMultiFormatReader } from '@zxing/browser'

const route = useRoute()
const sessionId = route.query.session as string | undefined

type PageState = 'loading' | 'invalid' | 'expired' | 'scanning' | 'success' | 'error'
const state = ref<PageState>('loading')
const errorMsg = ref('')
const scannedCode = ref('')
const scanCount = ref(0)

const videoRef = ref<HTMLVideoElement | null>(null)
let reader: BrowserMultiFormatReader | null = null
let scanControls: { stop: () => void } | null = null
let resumeTimer: ReturnType<typeof setTimeout> | null = null

// ── Validate the session ──────────────────────────────────────────
async function validateSession() {
  if (!sessionId || !supabase) { state.value = 'invalid'; return }

  const { data, error } = await supabase
    .from('scan_sessions')
    .select('status, expires_at')
    .eq('id', sessionId)
    .single()

  if (error || !data) { state.value = 'invalid'; return }

  if (new Date(data.expires_at) < new Date()) { state.value = 'expired'; return }

  // Accept both 'waiting' and 'scanned' — session is reusable
  startScanning()
}

// ── Start camera ──────────────────────────────────────────────────
async function startScanning() {
  state.value = 'scanning'
  if (!reader) reader = new BrowserMultiFormatReader()

  try {
    const devices = await BrowserMultiFormatReader.listVideoInputDevices()
    const backCam = devices.find(d =>
      d.label.toLowerCase().includes('back') ||
      d.label.toLowerCase().includes('rear') ||
      d.label.toLowerCase().includes('environment')
    ) ?? devices[devices.length - 1]

    if (!backCam || !videoRef.value) {
      state.value = 'error'
      errorMsg.value = 'No camera found on this device.'
      return
    }

    const controls = await reader.decodeFromVideoDevice(
      backCam.deviceId,
      videoRef.value,
      async (result) => {
        if (result) {
          const code = result.getText()
          if (code && code !== scannedCode.value && state.value === 'scanning') {
            scannedCode.value = code
            controls.stop()
            scanControls = null
            await submitScan(code)
          }
        }
      }
    )
    scanControls = controls
  } catch (e: any) {
    state.value = 'error'
    errorMsg.value = e?.name === 'NotAllowedError'
      ? 'Camera permission denied. Please allow camera access and try again.'
      : 'Could not start camera. Please try again.'
  }
}

// ── Submit scan ───────────────────────────────────────────────────
async function submitScan(barcode: string) {
  if (!supabase || !sessionId) return

  // Check session is still valid (not expired)
  const { data: session } = await supabase
    .from('scan_sessions')
    .select('expires_at')
    .eq('id', sessionId)
    .single()

  if (!session || new Date(session.expires_at) < new Date()) {
    state.value = 'expired'
    return
  }

  // Reset session to 'waiting' with new barcode — allows desktop to pick it up
  const { error } = await supabase
    .from('scan_sessions')
    .update({ status: 'scanned', scanned_barcode: barcode })
    .eq('id', sessionId)

  if (error) {
    state.value = 'error'
    errorMsg.value = 'Failed to send scan. Please try again.'
    return
  }

  scanCount.value++
  state.value = 'success'

  // Auto-return to scanning after 2 seconds — resets session to waiting
  resumeTimer = setTimeout(async () => {
    if (!supabase || !sessionId) return
    // Reset session back to waiting so it can accept the next scan
    await supabase
      .from('scan_sessions')
      .update({ status: 'waiting', scanned_barcode: null })
      .eq('id', sessionId)

    scannedCode.value = ''
    startScanning()
  }, 2000)
}

function endSession() {
  cleanup()
  state.value = 'invalid' // show "session ended" via invalid page
}

function cleanup() {
  scanControls?.stop()
  scanControls = null
  if (resumeTimer) { clearTimeout(resumeTimer); resumeTimer = null }
}

onMounted(() => validateSession())
onUnmounted(() => cleanup())
</script>

<template>
  <div class="scan-page">

    <!-- Loading -->
    <div v-if="state === 'loading'" class="center-state">
      <div class="spinner"></div>
      <p>Checking session...</p>
    </div>

    <!-- Invalid / ended -->
    <div v-else-if="state === 'invalid'" class="center-state warn">
      <div class="big-icon">✗</div>
      <h2>Invalid Link</h2>
      <p>This scan link is not valid.<br>Please generate a new one from the store app.</p>
    </div>

    <!-- Expired -->
    <div v-else-if="state === 'expired'" class="center-state warn">
      <div class="big-icon">⏱</div>
      <h2>Session Expired</h2>
      <p>This scan session has expired.<br>Please generate a new QR code from the store app.</p>
    </div>

    <!-- Error -->
    <div v-else-if="state === 'error'" class="center-state warn">
      <div class="big-icon">!</div>
      <h2>Something went wrong</h2>
      <p>{{ errorMsg }}</p>
      <button class="action-btn" @click="scannedCode = ''; errorMsg = ''; startScanning()">Try Again</button>
    </div>

    <!-- Success — auto-returns to scanning after 2s -->
    <div v-else-if="state === 'success'" class="center-state success">
      <div class="big-icon">✓</div>
      <h2>Scanned!</h2>
      <p>Check your other device.</p>
      <p class="code-display">{{ scannedCode }}</p>
      <p class="counter">{{ scanCount }} scanned this session</p>
      <p class="resuming">Returning to camera in 2 seconds...</p>
    </div>

    <!-- Scanning -->
    <div v-else class="scanner-view">
      <div class="instructions">
        <p>Point camera at the barcode</p>
        <span v-if="scanCount > 0" class="counter-badge">{{ scanCount }} scanned</span>
      </div>

      <div class="viewfinder-wrap">
        <video ref="videoRef" class="viewfinder" autoplay muted playsinline></video>
        <div class="guide-overlay">
          <div class="guide-box"></div>
        </div>
      </div>

      <div class="bottom-bar">
        <p class="scan-hint">Hold steady over the barcode</p>
        <button class="end-btn" @click="endSession">End Scanning</button>
      </div>
    </div>

  </div>
</template>

<style scoped>
* { box-sizing: border-box; margin: 0; padding: 0; }

.scan-page {
  min-height: 100dvh;
  background: #0a0f1e;
  color: #f1f5f9;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  display: flex;
  flex-direction: column;
}

.center-state {
  flex: 1; display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  padding: 32px 24px; text-align: center; gap: 16px;
}
.big-icon { font-size: 72px; line-height: 1; }
.center-state h2 { font-size: 32px; font-weight: 700; }
.center-state p { font-size: 20px; color: #94a3b8; line-height: 1.5; }
.center-state.warn .big-icon { color: #fbbf24; }
.center-state.success .big-icon { color: #22c55e; font-size: 96px; }
.center-state.success h2 { color: #22c55e; font-size: 48px; }
.center-state.success p { font-size: 22px; color: #cbd5e1; }
.code-display {
  font-size: 15px !important; color: #475569 !important;
  font-family: monospace; background: rgba(255,255,255,0.06);
  padding: 8px 16px; border-radius: 8px;
}
.counter { font-size: 16px !important; color: #22c55e !important; }
.resuming { font-size: 15px !important; color: #475569 !important; }

.action-btn {
  margin-top: 8px; padding: 16px 40px; font-size: 20px; font-weight: 700;
  border: none; border-radius: 14px;
  background: linear-gradient(135deg, #059669, #34d399); color: white; cursor: pointer;
}

/* Scanner */
.scanner-view { flex: 1; display: flex; flex-direction: column; }
.instructions {
  padding: 16px; text-align: center; background: #0a0f1e;
  display: flex; align-items: center; justify-content: center; gap: 12px;
}
.instructions p { font-size: 22px; font-weight: 600; color: #f1f5f9; }
.counter-badge {
  background: rgba(34,197,94,0.2); border: 1px solid rgba(34,197,94,0.4);
  color: #22c55e; font-size: 13px; font-weight: 700;
  padding: 4px 10px; border-radius: 999px;
}

.viewfinder-wrap { flex: 1; position: relative; background: #000; overflow: hidden; }
.viewfinder { width: 100%; height: 100%; object-fit: cover; display: block; }
.guide-overlay {
  position: absolute; inset: 0;
  display: flex; align-items: center; justify-content: center; pointer-events: none;
}
.guide-box {
  width: 72%; max-width: 320px; aspect-ratio: 2 / 1;
  border: 3px solid #22c55e; border-radius: 12px;
  box-shadow: 0 0 0 9999px rgba(0,0,0,0.45);
}

.bottom-bar {
  padding: 12px 16px; background: #0a0f1e;
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
}
.scan-hint { font-size: 15px; color: #64748b; }
.end-btn {
  padding: 8px 16px; border-radius: 8px; font-size: 13px; font-weight: 700;
  background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.3);
  color: #f87171; cursor: pointer;
}

.spinner {
  width: 48px; height: 48px;
  border: 4px solid rgba(255,255,255,0.1); border-top-color: #22c55e;
  border-radius: 50%; animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
