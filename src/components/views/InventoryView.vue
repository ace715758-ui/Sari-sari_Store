<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { fmt } from '../../composables/useSettings'
import type { ExpiryBatch, Product } from '../../types'
import { stockDisplay, inventoryValue } from '../../types'
import { effectiveLowStockThreshold, getExpiryStatuses, getNearestExpiry, isLowStock } from '../../lib/stockHealth'

const props = defineProps<{
  products: Product[]
  expiryBatches: ExpiryBatch[]
  currency: string
  lowStockThreshold: number
  expiryWarningDays: number
  perProductThresholdsEnabled: boolean
  initialFilter: 'all' | 'low' | 'expiring'
}>()

const emit = defineEmits<{
  restock: [productId: string, qty: number, unit: 'pack' | 'piece', expiryDate: string | null, notes: string]
  'break-pack': [productId: string]
}>()

const restockId = ref<string | null>(null)
const restockQty = ref<number | null>(null)
const restockUnit = ref<'pack' | 'piece'>('pack')
const restockExpiryDate = ref('')
const restockNotes = ref('')
const restockError = ref('')
const filter = ref<'all' | 'low' | 'expiring'>(props.initialFilter)

watch(() => props.initialFilter, value => {
  filter.value = value
})

const expiringStatuses = computed(() =>
  getExpiryStatuses(props.products, props.expiryBatches, props.expiryWarningDays)
    .filter(status => status.expired || status.expiringSoon)
)

const filteredProducts = computed(() => {
  if (filter.value === 'low') {
    return props.products.filter(p => isLowStock(p, props.lowStockThreshold, props.perProductThresholdsEnabled))
  }
  if (filter.value === 'expiring') {
    const ids = new Set(expiringStatuses.value.map(status => status.product.id))
    return [...props.products]
      .filter(p => ids.has(p.id))
      .sort((a, b) => (nearestExpiry(a)?.daysRemaining ?? 99999) - (nearestExpiry(b)?.daysRemaining ?? 99999))
  }
  return props.products
})

const selectedRestockProduct = computed(() => props.products.find(p => p.id === restockId.value) ?? null)

function openRestock(id: string) {
  restockId.value = id
  restockQty.value = null
  restockUnit.value = 'pack'
  restockExpiryDate.value = ''
  restockNotes.value = ''
  restockError.value = ''
}

function confirmRestock() {
  if (!restockQty.value || restockQty.value <= 0) {
    restockError.value = 'Enter a valid quantity.'
    return
  }
  if (selectedRestockProduct.value?.hasExpiry && !restockExpiryDate.value) {
    restockError.value = 'Enter an expiry date for this restock.'
    return
  }
  emit('restock', restockId.value!, restockQty.value, restockUnit.value, restockExpiryDate.value || null, restockNotes.value.trim())
  restockId.value = null
  restockQty.value = null
  restockExpiryDate.value = ''
  restockNotes.value = ''
  restockError.value = ''
}

function hasPacks(p: Product) {
  return p.isPerPieceEnabled && p.piecesPerPack > 1 && p.quantity >= p.piecesPerPack
}

function thresholdFor(product: Product) {
  return effectiveLowStockThreshold(product, props.lowStockThreshold, props.perProductThresholdsEnabled)
}

function nearestExpiry(product: Product) {
  return getNearestExpiry(product, props.expiryBatches, props.expiryWarningDays)
}
</script>

<template>
  <div class="view">
    <div class="view-header">
      <h2>Inventory</h2>
      <p>Current stock levels. Restock in packs or pieces. Break a Pack splits one pack into loose pieces.</p>
    </div>

    <div class="filter-tabs">
      <button :class="{ active: filter === 'all' }" @click="filter = 'all'">All</button>
      <button :class="{ active: filter === 'low' }" @click="filter = 'low'">Low Stock</button>
      <button :class="{ active: filter === 'expiring' }" @click="filter = 'expiring'">Expiring Soon</button>
    </div>

    <!-- Restock bar -->
    <div v-if="restockId !== null" class="restock-bar">
      <span class="restock-label">
        Restocking: <strong>{{ selectedRestockProduct?.name }}</strong>
      </span>
      <template v-if="selectedRestockProduct?.isPerPieceEnabled">
        <div class="unit-toggle">
          <button :class="{ active: restockUnit === 'pack' }" @click="restockUnit = 'pack'">Packs</button>
          <button :class="{ active: restockUnit === 'piece' }" @click="restockUnit = 'piece'">Pieces</button>
        </div>
      </template>
      <input v-model.number="restockQty" type="number" :placeholder="`# of ${restockUnit}s`" min="1" />
      <template v-if="selectedRestockProduct?.hasExpiry">
        <input v-model="restockExpiryDate" type="date" title="Expiry date" />
        <input v-if="selectedRestockProduct.expiryTrackingMode === 'batch'" v-model="restockNotes" type="text" placeholder="Batch notes" />
      </template>
      <span v-if="restockError" class="error">{{ restockError }}</span>
      <button class="confirm-btn" @click="confirmRestock">Confirm</button>
      <button class="cancel-btn" @click="restockId = null">Cancel</button>
    </div>

    <div class="panel">
      <table v-if="filteredProducts.length">
        <thead>
          <tr>
            <th>Product</th>
            <th>Pack Price</th>
            <th>Per-Piece Price</th>
            <th>Stock</th>
            <th>Total Value</th>
            <th>Status</th>
            <th>Expiry</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in filteredProducts" :key="p.id" :class="{ 'row-active': p.id === restockId }">
            <td class="name">
              {{ p.name }}
              <span v-if="p.isPerPieceEnabled" class="per-piece-badge">Per-Piece</span>
            </td>
            <td>{{ currency }}{{ fmt(p.price) }}</td>
            <td>
              <span v-if="p.isPerPieceEnabled">{{ currency }}{{ fmt(p.perPiecePrice) }}/pc</span>
              <span v-else class="muted">—</span>
            </td>
            <td class="stock-cell">{{ stockDisplay(p) }}</td>
            <td>{{ currency }}{{ fmt(inventoryValue(p)) }}</td>
            <td>
              <span :class="p.quantity === 0 ? 'out' : isLowStock(p, lowStockThreshold, perProductThresholdsEnabled) ? 'low' : 'good'">
                {{ p.quantity === 0 ? 'Out of Stock' : isLowStock(p, lowStockThreshold, perProductThresholdsEnabled) ? `Low <= ${thresholdFor(p)}` : 'In Stock' }}
              </span>
            </td>
            <td>
              <span v-if="nearestExpiry(p)" :class="nearestExpiry(p)!.expired ? 'out' : nearestExpiry(p)!.expiringSoon ? 'low' : 'good'">
                {{ nearestExpiry(p)!.label }}
              </span>
              <span v-else-if="p.hasExpiry" class="missing-date">Add expiry date</span>
              <span v-else class="muted">Not tracked</span>
            </td>
            <td class="actions-cell">
              <button class="restock-btn" @click="openRestock(p.id)">Restock</button>
              <button v-if="hasPacks(p)" class="break-btn" @click="emit('break-pack', p.id)" title="Convert 1 pack into loose pieces">
                Break Pack
              </button>
            </td>
          </tr>
        </tbody>
      </table>
      <div v-else class="empty">{{ products.length ? 'No items match this inventory filter.' : 'No inventory data. Add products first.' }}</div>
    </div>
  </div>
</template>

<style scoped>
.view { padding: 24px; height: 100%; min-height: 0; display: flex; flex-direction: column; gap: 12px; overflow: hidden; }
.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

.restock-bar {
  display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
  background: rgba(59,130,246,0.1); border: 1px solid rgba(59,130,246,0.3);
  border-radius: 12px; padding: 10px 16px;
}
.restock-label { font-size: 13px; color: #93c5fd; white-space: nowrap; }
.restock-label strong { color: white; }

.unit-toggle { display: flex; gap: 6px; }
.unit-toggle button {
  padding: 5px 12px; border-radius: 8px; font-size: 12px; font-weight: 700;
  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12);
  color: #94a3b8; cursor: pointer;
}
.unit-toggle button.active {
  background: rgba(59,130,246,0.2); border-color: rgba(59,130,246,0.5); color: #93c5fd;
}

input {
  padding: 7px 10px; border-radius: 8px; width: 140px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827;
  color: white; outline: none; font-size: 13px;
}
input:focus { border-color: #22c55e; }

input[type="date"] { width: 150px; }
input[type="text"] { width: 180px; }

.filter-tabs {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.filter-tabs button {
  padding: 7px 14px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.1);
  background: rgba(255,255,255,0.05);
  color: #94a3b8;
  cursor: pointer;
  font-size: 12px;
  font-weight: 800;
}

.filter-tabs button.active {
  background: rgba(34,197,94,0.18);
  border-color: rgba(34,197,94,0.4);
  color: #22c55e;
}

.confirm-btn, .cancel-btn {
  padding: 7px 14px; border: none; border-radius: 8px;
  font-weight: 700; cursor: pointer; font-size: 12px;
}
.confirm-btn { background: linear-gradient(135deg, #059669, #34d399); color: white; }
.cancel-btn { background: rgba(255,255,255,0.08); color: #cbd5e1; border: 1px solid rgba(255,255,255,0.1); }
.error { color: #fca5a5; font-size: 12px; }

.panel {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 16px; flex: 1; min-height: 0; overflow-y: auto;
}

table { width: 100%; border-collapse: collapse; }
th { position: sticky; top: 0; z-index: 2; background: rgba(15,23,42,0.98); padding: 10px 12px; text-align: left; color: #6ee7b7; font-size: 12px; text-transform: uppercase; white-space: nowrap; }
td { padding: 10px 12px; color: #e5e7eb; font-size: 13px; white-space: nowrap; }
tbody tr:nth-child(even) { background: rgba(255,255,255,0.04); }
tbody tr:hover { background: rgba(34,197,94,0.08); }
tbody tr.row-active { background: rgba(59,130,246,0.1) !important; }
.name { font-weight: 700; }
.stock-cell { color: #a5b4fc; font-weight: 600; }
.muted { color: #475569; }
.missing-date { color: #cbd5e1; font-size: 12px; font-weight: 700; }

.per-piece-badge {
  display: inline-block; margin-left: 6px;
  padding: 1px 7px; border-radius: 999px; font-size: 10px; font-weight: 700;
  background: rgba(165,180,252,0.15); color: #a5b4fc; border: 1px solid rgba(165,180,252,0.3);
}

.good, .low, .out { padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 700; }
.good { background: rgba(34,197,94,0.18); color: #6ee7b7; }
.low  { background: rgba(245,158,11,0.2); color: #fbbf24; }
.out  { background: rgba(239,68,68,0.18); color: #fca5a5; }

.actions-cell { display: flex; gap: 6px; }

.restock-btn {
  padding: 5px 12px; border: none; border-radius: 8px;
  background: rgba(59,130,246,0.2); border: 1px solid rgba(59,130,246,0.4);
  color: #93c5fd; font-weight: 700; cursor: pointer; font-size: 12px;
}
.restock-btn:hover { background: rgba(59,130,246,0.35); }

.break-btn {
  padding: 5px 12px; border-radius: 8px;
  background: rgba(165,180,252,0.1); border: 1px solid rgba(165,180,252,0.3);
  color: #a5b4fc; font-weight: 700; cursor: pointer; font-size: 12px;
}
.break-btn:hover { background: rgba(165,180,252,0.2); }

.empty { color: #94a3b8; text-align: center; padding: 40px; }
</style>
