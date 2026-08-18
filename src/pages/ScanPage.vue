<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../lib/supabase'
import { BrowserMultiFormatReader } from '@zxing/browser'

const route = useRoute()
const sessionId = route.query.session as string | undefined

type PageState = 'loading' | 'invalid' | 'expired' | 'ready' | 'scanning' | 'success' | 'error'
const state = ref<PageState>('loading')
const errorMsg = ref('')
const scannedCode = ref('')

const videoRef = ref<HTMLVideoElement | null>(null)
let reader: BrowserMultiFormatReader | null = null
let stopScan: (() => void) | null = null

// ── Validate the session ──────────────────────────────────────────
async function validateSession() {
  if (!sessionId || !supabase) {
    state.value = 'invalid'
    return
  }

  const { data, error } = await supabase
    .from('scan_sessions')
    .select('status, expires_at')
    .eq('id', sessionId)
    .single()

  if (error || !data) {
    state.value = 'invalid'
    return
  }

  if (data.status !== 'waiting' || new Date(data.expires_at) < new Date()) {
    state.value = 'expired'
    return
  }

  state.value = 'ready'
  startScanning()
}

// ── Start camera / barcode scanning ──────────────────────────────
async function startScanning() {
  state.value = 'scanning'
  reader = new BrowserMultiFormatReader()

  try {
    const devices = await BrowserMultiFormatReader.listVideoInputDevices()
    // Prefer back camera
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
      async (result, err) => {
        if (result) {
          const code = result.getText()
          if (code && code !== scannedCode.value) {
            scannedCode.value = code
            controls.stop()
            stopScan = null
            await submitScan(code)
          }
        }
        // Ignore err — it fires every frame when nothing is detected
      }
    )
    stopScan = () => controls.stop()
  } catch (e: any) {
    state.value = 'error'
    if (e?.name === 'NotAllowedError') {
      errorMsg.value = 'Camera permission denied. Please allow camera access and try again.'
    } else {
      errorMsg.value = 'Could not start camera. Please try again.'
    }
  }
}

// ── Submit scan result to Supabase ────────────────────────────────
async function submitScan(barcode: string) {
  if (!supabase || !sessionId) return

  // Re-validate before submitting (prevent race / double-submit)
  const { data: session } = await supabase
    .from('scan_sessions')
    .select('status, expires_at')
    .eq('id', sessionId)
    .single()

  if (!session || session.status !== 'waiting' || new Date(session.expires_at) < new Date()) {
    state.value = 'expired'
    return
  }

  const { error } = await supabase
    .from('scan_sessions')
    .update({ status: 'scanned', scanned_barcode: barcode })
    .eq('id', sessionId)
    .eq('status', 'waiting') // atomic guard — only succeeds if still waiting

  if (error) {
    state.value = 'error'
    errorMsg.value = 'Failed to send scan. Please try again.'
    return
  }

  state.value = 'success'
}

async function retry() {
  scannedCode.value = ''
  stopScan?.()
  stopScan = null
  errorMsg.value = ''
  await validateSession()
}

onMounted(() => {
  validateSession()
})

onUnmounted(() => {
  stopScan?.()
})
</script>

<template>
  <div class="scan-page">

    <!-- Loading -->
    <div v-if="state === 'loading'" class="center-state">
      <div class="spinner"></div>
      <p>Checking session...</p>
    </div>

    <!-- Invalid session -->
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
      <button class="action-btn" @click="retry">Try Again</button>
    </div>

    <!-- Success -->
    <div v-else-if="state === 'success'" class="center-state success">
      <div class="big-icon">✓</div>
      <h2>Scanned!</h2>
      <p>Check your other device.</p>
      <p class="code-display">{{ scannedCode }}</p>
    </div>

    <!-- Scanning -->
    <div v-else class="scanner-view">
      <div class="instructions">
        <p>Point camera at the barcode</p>
      </div>

      <div class="viewfinder-wrap">
        <video ref="videoRef" class="viewfinder" autoplay muted playsinline></video>
        <!-- Scan guide overlay -->
        <div class="guide-overlay">
          <div class="guide-box"></div>
        </div>
      </div>

      <p class="scan-hint">Hold steady over the barcode</p>
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

/* ── Centered states ── */
.center-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 32px 24px;
  text-align: center;
  gap: 16px;
}

.big-icon {
  font-size: 72px;
  line-height: 1;
}

.center-state h2 {
  font-size: 32px;
  font-weight: 700;
}

.center-state p {
  font-size: 20px;
  color: #94a3b8;
  line-height: 1.5;
}

.center-state.warn .big-icon { color: #fbbf24; }
.center-state.success .big-icon { color: #22c55e; font-size: 96px; }
.center-state.success h2 { color: #22c55e; font-size: 48px; }
.center-state.success p { font-size: 24px; color: #cbd5e1; }

.code-display {
  margin-top: 8px;
  font-size: 16px !important;
  color: #475569 !important;
  font-family: monospace;
  background: rgba(255,255,255,0.06);
  padding: 8px 16px;
  border-radius: 8px;
}

.action-btn {
  margin-top: 8px;
  padding: 16px 40px;
  font-size: 20px;
  font-weight: 700;
  border: none;
  border-radius: 14px;
  background: linear-gradient(135deg, #059669, #34d399);
  color: white;
  cursor: pointer;
}

/* ── Scanner view ── */
.scanner-view {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.instructions {
  padding: 20px 16px 12px;
  text-align: center;
  background: #0a0f1e;
}

.instructions p {
  font-size: 24px;
  font-weight: 600;
  color: #f1f5f9;
}

.viewfinder-wrap {
  flex: 1;
  position: relative;
  background: #000;
  overflow: hidden;
}

.viewfinder {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.guide-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}

.guide-box {
  width: 72%;
  max-width: 320px;
  aspect-ratio: 2 / 1;
  border: 3px solid #22c55e;
  border-radius: 12px;
  box-shadow: 0 0 0 9999px rgba(0,0,0,0.45);
}

.scan-hint {
  padding: 14px 16px;
  text-align: center;
  font-size: 16px;
  color: #64748b;
  background: #0a0f1e;
}

/* Spinner */
.spinner {
  width: 48px; height: 48px;
  border: 4px solid rgba(255,255,255,0.1);
  border-top-color: #22c55e;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
