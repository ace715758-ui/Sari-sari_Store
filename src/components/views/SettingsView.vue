<script setup lang="ts">
import { ref } from 'vue'
import { storeName, ownerName, currency, lowStockThreshold, expiryWarningDays, perProductThresholdsEnabled, darkMode } from '../../composables/useSettings'
import { supabase } from '../../lib/supabase'

const saved = ref(false)
const showModal = ref(false)

async function confirmClear() {
  const { data } = await supabase!.auth.getUser()
  const userId = data.user?.id
  if (!userId) return

  await supabase!.from('sales').delete().eq('user_id', userId)
  await supabase!.from('expiry_batches').delete().eq('user_id', userId)
  await supabase!.from('products').delete().eq('user_id', userId)
  await supabase!.from('store_settings').delete().eq('user_id', userId)
  localStorage.clear()
  location.reload()
}

const tiltX = ref(0)
const tiltY = ref(0)
const glowX = ref(50)
const glowY = ref(50)

function onMouseMove(e: MouseEvent) {
  const el = e.currentTarget as HTMLElement
  const rect = el.getBoundingClientRect()
  const x = (e.clientX - rect.left) / rect.width
  const y = (e.clientY - rect.top) / rect.height
  tiltX.value = (y - 0.5) * -14
  tiltY.value = (x - 0.5) * 14
  glowX.value = x * 100
  glowY.value = y * 100
}

function onMouseLeave() {
  tiltX.value = 0
  tiltY.value = 0
  glowX.value = 50
  glowY.value = 50
}

function saveSettings() {
  saved.value = true
  setTimeout(() => (saved.value = false), 2500)
}
</script>

<template>
  <div class="view">
    <div class="view-header">
      <h2>Settings</h2>
      <p>Configure your store preferences.</p>
    </div>

    <div class="layout">
      <div class="left">
        <div class="panel">
          <div class="field">
            <label>Store Name</label>
            <input v-model="storeName" type="text" />
          </div>
          <div class="field">
            <label>Owner Name</label>
            <input v-model="ownerName" type="text" />
          </div>
          <div class="field">
            <label>Currency Symbol</label>
            <input v-model="currency" type="text" style="max-width: 100px;" />
          </div>
          <div class="field">
            <label>Low Stock Threshold</label>
            <input v-model.number="lowStockThreshold" type="number" style="max-width: 120px;" />
          </div>
          <div class="field">
            <label>Expiry Warning Window</label>
            <input v-model.number="expiryWarningDays" type="number" min="0" style="max-width: 120px;" />
          </div>
          <div class="field">
            <label>Stock Thresholds</label>
            <div class="toggle-row">
              <span>{{ perProductThresholdsEnabled ? 'Per-product thresholds enabled' : 'Using global threshold only' }}</span>
              <button class="toggle-btn" :class="{ active: perProductThresholdsEnabled }" @click="perProductThresholdsEnabled = !perProductThresholdsEnabled">
                <span class="toggle-thumb"></span>
              </button>
            </div>
          </div>

          <div class="field">
            <label>Appearance</label>
            <div class="toggle-row">
              <span>{{ darkMode ? 'Dark Mode' : 'Light Mode' }}</span>
              <button class="toggle-btn" :class="{ active: !darkMode }" @click="darkMode = !darkMode">
                <span class="toggle-thumb"></span>
              </button>
            </div>
          </div>

          <div class="actions">
            <button @click="saveSettings">Save Settings</button>
            <span v-if="saved" class="saved-msg">Settings saved.</span>
          </div>
        </div>

        <div class="panel danger-zone">
          <h3>Danger Zone</h3>
          <p>Permanently delete all store data for this account.</p>
          <button class="danger-btn" @click="showModal = true">Clear All Data</button>
        </div>
      </div>

      <div
        class="right"
        @mousemove="onMouseMove"
        @mouseleave="onMouseLeave"
        :style="{ transform: `perspective(800px) rotateX(${tiltX}deg) rotateY(${tiltY}deg)` }"
      >
        <img src="/img.jpg" alt="Store" class="store-img" />

        <!-- moving radial glow that follows cursor -->
        <div class="cursor-glow" :style="{ background: `radial-gradient(circle at ${glowX}% ${glowY}%, rgba(34,197,94,0.18), transparent 60%)` }"></div>

        <!-- shimmer scan line -->
        <div class="shimmer"></div>

        <!-- corner badge -->
        <div class="corner-badge">LIVE</div>

        <div class="img-overlay">
          <strong>{{ storeName }}</strong>
          <p>{{ ownerName }}</p>
        </div>
      </div>
    </div>
  </div>

  <!-- Confirmation Modal -->
  <Teleport to="body">
    <div v-if="showModal" class="modal-backdrop" @click.self="showModal = false">
      <div class="modal">
        <div class="modal-icon">!</div>
        <h3>Clear All Data?</h3>
        <p>This will permanently delete all products, sales, and settings. This action cannot be undone.</p>
        <div class="modal-actions">
          <button class="modal-cancel" @click="showModal = false">Cancel</button>
          <button class="modal-confirm" @click="confirmClear">Yes, Clear Everything</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.view { padding: 24px; height: 100%; overflow-y: auto; }
.view-header { margin-bottom: 16px; }
.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

.layout { display: grid; grid-template-columns: 480px 1fr; gap: 20px; align-items: start; }

.left { display: flex; flex-direction: column; gap: 16px; }

.panel {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 20px;
}

.field { margin-bottom: 14px; }
label { display: block; margin-bottom: 6px; color: #d1d5db; font-size: 13px; font-weight: 600; }

input {
  width: 100%; padding: 9px 12px; border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827;
  color: white; outline: none; font-size: 13px;
}
input:focus { border-color: #22c55e; }

.actions { display: flex; align-items: center; gap: 14px; margin-top: 6px; }

.toggle-row {
  display: flex; align-items: center; gap: 12px;
  font-size: 13px; color: #d1d5db;
}

.toggle-btn {
  width: 44px; height: 24px; border-radius: 999px; padding: 0;
  background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.15);
  cursor: pointer; position: relative; transition: background 0.25s;
}
.toggle-btn.active {
  background: #22c55e; border-color: #22c55e;
}
.toggle-thumb {
  position: absolute; top: 3px; left: 3px;
  width: 16px; height: 16px; border-radius: 50%;
  background: white; transition: transform 0.25s;
  display: block;
}
.toggle-btn.active .toggle-thumb {
  transform: translateX(20px);
}

button {
  padding: 10px 20px; border: none; border-radius: 10px;
  background: linear-gradient(135deg, #059669, #34d399);
  color: white; font-weight: 700; cursor: pointer; font-size: 13px;
}

.saved-msg { color: #6ee7b7; font-size: 13px; }

.danger-zone h3 { margin: 0 0 6px; font-size: 15px; color: #f87171; }
.danger-zone p { margin: 0 0 12px; color: #94a3b8; font-size: 13px; }
.danger-btn { background: rgba(239,68,68,0.2); border: 1px solid rgba(239,68,68,0.4); color: #f87171; }

.right {
  position: relative;
  border-radius: 20px;
  overflow: hidden;
  height: 100%;
  min-height: 300px;
  transition: transform 0.1s ease;
  transform-style: preserve-3d;
  cursor: crosshair;
  border: 1px solid rgba(255,255,255,0.1);
  box-shadow: 0 24px 60px rgba(0,0,0,0.5);
}

.right:hover .store-img {
  transform: scale(1.05);
}

.store-img {
  width: 100%; height: 100%; object-fit: cover;
  display: block; border-radius: 20px;
  transition: transform 0.5s ease;
}

.cursor-glow {
  position: absolute; inset: 0;
  border-radius: 20px;
  pointer-events: none;
  transition: background 0.05s ease;
}

.shimmer {
  position: absolute; inset: 0;
  border-radius: 20px;
  pointer-events: none;
  overflow: hidden;
}
.shimmer::after {
  content: '';
  position: absolute;
  top: -100%;
  left: 0;
  width: 100%;
  height: 60%;
  background: linear-gradient(to bottom, transparent, rgba(255,255,255,0.06), transparent);
  transform: skewY(-8deg);
  animation: scan 4s linear infinite;
}
@keyframes scan {
  0%   { top: -60%; }
  100% { top: 160%; }
}

.corner-badge {
  position: absolute; top: 14px; right: 14px;
  background: rgba(34,197,94,0.2);
  border: 1px solid rgba(34,197,94,0.5);
  color: #22c55e;
  font-size: 11px; font-weight: 700;
  padding: 4px 10px; border-radius: 999px;
  letter-spacing: 1px;
  animation: pulse-badge 2s ease-in-out infinite;
}
@keyframes pulse-badge {
  0%, 100% { opacity: 1; }
  50%       { opacity: 0.4; }
}

.img-overlay {
  position: absolute; bottom: 0; left: 0; right: 0;
  padding: 20px 24px;
  background: linear-gradient(to top, rgba(7,16,20,0.92), transparent);
  border-radius: 0 0 20px 20px;
}
.img-overlay strong { font-size: 18px; display: block; }
.img-overlay p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

/* Modal */
.modal-backdrop {
  position: fixed; inset: 0; z-index: 1000;
  background: rgba(0,0,0,0.7);
  backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
  animation: fade-in 0.15s ease;
}
@keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }

.modal {
  background: #0f172a;
  border: 1px solid rgba(239,68,68,0.3);
  border-radius: 20px;
  padding: 32px 28px;
  max-width: 400px;
  width: 90%;
  text-align: center;
  box-shadow: 0 24px 60px rgba(0,0,0,0.6);
  animation: slide-up 0.2s ease;
}
@keyframes slide-up { from { transform: translateY(16px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }

.modal-icon {
  width: 52px; height: 52px; border-radius: 50%;
  background: rgba(239,68,68,0.15);
  border: 1px solid rgba(239,68,68,0.4);
  color: #f87171; font-size: 26px; font-weight: 900;
  display: grid; place-items: center;
  margin: 0 auto 16px;
}

.modal h3 { margin: 0 0 10px; font-size: 18px; color: #f1f5f9; }
.modal p { margin: 0 0 24px; color: #94a3b8; font-size: 13px; line-height: 1.6; }

.modal-actions { display: flex; gap: 10px; }

.modal-cancel {
  flex: 1; padding: 11px; border: 1px solid rgba(255,255,255,0.1);
  border-radius: 10px; background: rgba(255,255,255,0.06);
  color: #cbd5e1; font-weight: 700; cursor: pointer; font-size: 13px;
}
.modal-cancel:hover { background: rgba(255,255,255,0.1); }

.modal-confirm {
  flex: 1; padding: 11px; border: none;
  border-radius: 10px; background: rgba(239,68,68,0.2);
  border: 1px solid rgba(239,68,68,0.4);
  color: #f87171; font-weight: 700; cursor: pointer; font-size: 13px;
}
.modal-confirm:hover { background: rgba(239,68,68,0.35); }

@media (max-width: 980px) {
  .view {
    padding: 14px;
  }

  .layout {
    grid-template-columns: 1fr;
  }

  .right {
    min-height: 240px;
  }
}

@media (max-width: 560px) {
  .panel {
    border-radius: 12px;
    padding: 16px;
  }

  .actions {
    align-items: stretch;
    flex-direction: column;
    gap: 8px;
  }

  .actions button,
  .danger-btn {
    width: 100%;
  }

  .right {
    min-height: 200px;
    cursor: default;
  }

  .modal {
    padding: 24px 18px;
  }

  .modal-actions {
    flex-direction: column;
  }
}
</style>
