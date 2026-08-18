<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import type { Product } from '../types'
import { fmt } from '../composables/useSettings'
import ScanWithPhone from './ScanWithPhone.vue'

type Suggestion = { id: number; title: string; price: number }

const CATEGORIES = ['Beverages', 'Snacks', 'Canned Goods', 'Toiletries', 'Condiments', 'Dairy', 'Bread & Pastries', 'Frozen Goods', 'Others']

const props = defineProps<{
  editingProduct: Product | null
  lowStockThreshold: number
  perProductThresholdsEnabled: boolean
}>()
const emit = defineEmits<{
  'add-product': [product: Omit<Product, 'id'>]
  'update-product': [product: Product]
  'cancel-edit': []
}>()

const name = ref('')
const category = ref('')
const price = ref<number | null>(null)
const costPrice = ref<number | null>(null)
const quantity = ref<number | null>(null)   // always in PACKS in the form UI
const sellMode = ref<'pack' | 'per-piece'>('pack')
const piecesPerPack = ref<number | null>(null)
const perPiecePrice = ref<number | null>(null)
const customLowStockThreshold = ref<number | null>(null)
const hasExpiry = ref(false)
const expiryTrackingMode = ref<'product-level' | 'batch'>('product-level')
const expiryDate = ref('')
const error = ref('')

const isPerPiece = computed(() => sellMode.value === 'per-piece')

// Auto-suggest per-piece price
const suggestedPerPiecePrice = computed(() => {
  if (!price.value || !piecesPerPack.value || piecesPerPack.value < 2) return null
  return Math.ceil(price.value / piecesPerPack.value)
})

watch([price, piecesPerPack], () => {
  if (isPerPiece.value && suggestedPerPiecePrice.value && !props.editingProduct) {
    perPiecePrice.value = suggestedPerPiecePrice.value
  }
})

watch(sellMode, (val) => {
  if (val === 'pack') {
    piecesPerPack.value = null
    perPiecePrice.value = null
  }
})

// ── Live summary ──────────────────────────────────────────────────
const summaryPieces = computed(() => {
  const q = quantity.value ?? 0
  const ppp = isPerPiece.value ? (piecesPerPack.value ?? 1) : 1
  return q * ppp
})
const summaryCapital = computed(() => (costPrice.value ?? 0) * (quantity.value ?? 0))
const summaryValue   = computed(() => (price.value ?? 0) * (quantity.value ?? 0))
const showSummary = computed(() =>
  (quantity.value ?? 0) > 0 || (price.value ?? 0) > 0 || (costPrice.value ?? 0) > 0
)

// ── API search ────────────────────────────────────────────────────
const suggestions = ref<Suggestion[]>([])
const searching = ref(false)
let debounceTimer: ReturnType<typeof setTimeout>

watch(name, (val) => {
  if (props.editingProduct) return
  clearTimeout(debounceTimer)
  if (val.trim().length < 2) { suggestions.value = []; return }
  searching.value = true
  debounceTimer = setTimeout(async () => {
    try {
      const res = await fetch(`https://dummyjson.com/products/search?q=${encodeURIComponent(val)}&limit=6&select=title,price`)
      const data = await res.json()
      suggestions.value = data.products ?? []
    } catch {
      suggestions.value = []
    } finally {
      searching.value = false
    }
  }, 350)
})

function pickSuggestion(s: Suggestion) {
  name.value = s.title
  price.value = parseFloat(s.price.toFixed(2))
  suggestions.value = []
}

// ── Populate form when editing ────────────────────────────────────
watch(() => props.editingProduct, product => {
  if (product) {
    name.value = product.name
    category.value = product.category
    price.value = product.price
    costPrice.value = product.costPrice
    sellMode.value = product.isPerPieceEnabled ? 'per-piece' : 'pack'
    piecesPerPack.value = product.piecesPerPack > 1 ? product.piecesPerPack : null
    perPiecePrice.value = product.isPerPieceEnabled ? product.perPiecePrice : null
    // Display quantity in packs
    quantity.value = product.isPerPieceEnabled
      ? Math.floor(product.quantity / product.piecesPerPack)
      : product.quantity
    customLowStockThreshold.value = product.lowStockThreshold ?? props.lowStockThreshold
    hasExpiry.value = product.hasExpiry
    expiryTrackingMode.value = product.expiryTrackingMode ?? 'product-level'
    expiryDate.value = product.expiryDate ?? ''
  } else {
    clearForm()
  }
})

watch(() => props.lowStockThreshold, threshold => {
  if (!props.editingProduct && customLowStockThreshold.value === null) {
    customLowStockThreshold.value = threshold
  }
}, { immediate: true })

// ── Scan with Phone ──────────────────────────────────────────────
const showScanModal = ref(false)
const scanNotice = ref('')

function onScanResult(result: {
  barcode: string
  name: string
  category: string
  piecesPerPack: number
  sellingMode: 'pack' | 'per-piece'
  isNew: boolean
}) {
  showScanModal.value = false
  if (!result.isNew) {
    name.value = result.name
    category.value = result.category
    sellMode.value = result.sellingMode
    if (result.sellingMode === 'per-piece' && result.piecesPerPack > 1) {
      piecesPerPack.value = result.piecesPerPack
    }
    scanNotice.value = `Product found: "${result.name}". Please fill in prices and quantity.`
  } else {
    scanNotice.value = 'New product — barcode scanned. Please fill in all details below.'
  }
  // Clear notice after 6 seconds
  setTimeout(() => { scanNotice.value = '' }, 6000)
}

// ── Submit ────────────────────────────────────────────────────────
function submitForm() {
  if (!name.value.trim() || !category.value || price.value === null || costPrice.value === null || quantity.value === null) {
    error.value = 'Please fill in all fields.'
    return
  }
  if (price.value <= 0 || costPrice.value < 0 || quantity.value <= 0) {
    error.value = 'Price and quantity must be greater than zero.'
    return
  }
  if (costPrice.value > price.value) {
    error.value = 'Cost price cannot be higher than selling price.'
    return
  }
  if (isPerPiece.value) {
    if (!piecesPerPack.value || piecesPerPack.value < 2) {
      error.value = 'Enter how many pieces are in one pack (at least 2).'
      return
    }
    if (!perPiecePrice.value || perPiecePrice.value <= 0) {
      error.value = 'Enter a valid per-piece price.'
      return
    }
  }
  if (props.perProductThresholdsEnabled && customLowStockThreshold.value !== null && customLowStockThreshold.value < 0) {
    error.value = 'Low stock threshold cannot be negative.'
    return
  }
  if (hasExpiry.value && expiryTrackingMode.value === 'product-level' && expiryDate.value) {
    if (Number.isNaN(new Date(`${expiryDate.value}T00:00:00`).getTime())) {
      error.value = 'Enter a valid expiry date.'
      return
    }
  }

  const resolvedPpp = isPerPiece.value ? piecesPerPack.value! : 1
  const stockInPieces = quantity.value * resolvedPpp

  const payload: Omit<Product, 'id'> = {
    name: name.value.trim(),
    category: category.value,
    price: price.value,
    costPrice: costPrice.value,
    quantity: stockInPieces,
    piecesPerPack: resolvedPpp,
    perPiecePrice: isPerPiece.value ? perPiecePrice.value! : 0,
    isPerPieceEnabled: isPerPiece.value,
    lowStockThreshold: props.perProductThresholdsEnabled ? customLowStockThreshold.value : null,
    hasExpiry: hasExpiry.value,
    expiryTrackingMode: hasExpiry.value ? expiryTrackingMode.value : 'product-level',
    expiryDate: hasExpiry.value && expiryTrackingMode.value === 'product-level' ? expiryDate.value || null : null,
  }

  if (props.editingProduct) {
    emit('update-product', { id: props.editingProduct.id, ...payload })
  } else {
    emit('add-product', payload)
  }
  clearForm()
}

function clearForm() {
  name.value = ''
  category.value = ''
  price.value = null
  costPrice.value = null
  quantity.value = null
  sellMode.value = 'pack'
  piecesPerPack.value = null
  perPiecePrice.value = null
  customLowStockThreshold.value = props.lowStockThreshold
  hasExpiry.value = false
  expiryTrackingMode.value = 'product-level'
  expiryDate.value = ''
  error.value = ''
  suggestions.value = []
}

function clearSuggestions() {
  setTimeout(() => { suggestions.value = [] }, 200)
}

function cancelEdit() {
  clearForm()
  emit('cancel-edit')
}
</script>

<template>
  <section class="form-panel">
    <div class="form-header">
      <h2>{{ editingProduct ? 'Update Product' : 'Add Product' }}</h2>
      <p>{{ editingProduct ? 'Edit selected product.' : 'Search a product to auto-fill name and price.' }}</p>
    </div>

    <!-- Scan with Phone button — only shown when adding -->
    <button v-if="!editingProduct" class="scan-btn" type="button" @click="showScanModal = true">
      Scan with Phone
    </button>

    <!-- Scan notice -->
    <div v-if="scanNotice" class="scan-notice">{{ scanNotice }}</div>

    <!-- Scan modal -->
    <ScanWithPhone
      v-if="showScanModal"
      @scan-result="onScanResult"
      @close="showScanModal = false"
    />

    <!-- Product Name -->
    <label>Product Name</label>
    <div class="search-wrap">
      <input v-model="name" type="text" placeholder="Search or type product name..." autocomplete="off" @blur="clearSuggestions" />
      <span v-if="searching" class="spinner"></span>
      <ul v-if="suggestions.length" class="suggestions">
        <li v-for="s in suggestions" :key="s.id" @mousedown.prevent="pickSuggestion(s)">
          <span class="sug-name">{{ s.title }}</span>
          <span class="sug-price">₱{{ s.price.toFixed(2) }}</span>
        </li>
      </ul>
    </div>

    <!-- Category -->
    <label>Category</label>
    <select v-model="category">
      <option value="" disabled>Select category</option>
      <option v-for="c in CATEGORIES" :key="c" :value="c">{{ c }}</option>
    </select>

    <!-- Step 1: Sell mode -->
    <label>How do you sell this product?</label>
    <div class="sell-mode-toggle">
      <button type="button" :class="{ active: sellMode === 'pack' }" @click="sellMode = 'pack'">
        Whole pack only
      </button>
      <button type="button" :class="{ active: sellMode === 'per-piece' }" @click="sellMode = 'per-piece'">
        Whole pack + Per Piece
      </button>
    </div>

    <!-- Step 2: Pieces per Pack (only for per-piece mode) -->
    <template v-if="isPerPiece">
      <label>
        How many individual pieces are in one pack?
        <span class="field-hint">e.g. 20 sticks in a cigarette pack</span>
      </label>
      <input v-model.number="piecesPerPack" type="number" min="2" placeholder="e.g. 20" />
    </template>

    <!-- Step 3 & 4: Prices -->
    <div class="price-row">
      <div>
        <label>Cost Price <span class="field-hint">per pack</span></label>
        <input v-model.number="costPrice" type="number" placeholder="0.00" />
      </div>
      <div>
        <label>Selling Price <span class="field-hint">per pack</span></label>
        <input v-model.number="price" type="number" placeholder="0.00" />
      </div>
    </div>

    <!-- Step 5: Per-piece price (only for per-piece mode) -->
    <template v-if="isPerPiece">
      <label>
        Per-Piece Price <span class="field-hint">price for a single piece</span>
        <span v-if="suggestedPerPiecePrice" class="suggested-tag">suggested: ₱{{ suggestedPerPiecePrice }}</span>
      </label>
      <input v-model.number="perPiecePrice" type="number" placeholder="0.00" />
    </template>

    <!-- Step 6: Quantity -->
    <label>Quantity <span class="field-hint">number of packs</span></label>
    <input v-model.number="quantity" type="number" placeholder="0" />

    <!-- Step 7: Custom low stock threshold -->
    <div v-if="perProductThresholdsEnabled" class="alert-panel">
      <label>Custom low stock threshold <span class="field-hint">measured in pieces</span></label>
      <input v-model.number="customLowStockThreshold" type="number" min="0" :placeholder="String(lowStockThreshold)" />
    </div>

    <!-- Expiry -->
    <div class="alert-panel">
      <label class="check-row">
        <input v-model="hasExpiry" type="checkbox" />
        <span>This product has an expiry date</span>
      </label>
      <template v-if="hasExpiry">
        <label style="margin-top:10px">Expiry Tracking</label>
        <div class="mode-toggle">
          <button type="button" :class="{ active: expiryTrackingMode === 'product-level' }" @click="expiryTrackingMode = 'product-level'">Single Date</button>
          <button type="button" :class="{ active: expiryTrackingMode === 'batch' }" @click="expiryTrackingMode = 'batch'">Batch Mode</button>
        </div>
        <template v-if="expiryTrackingMode === 'product-level'">
          <label>Expiry Date</label>
          <input v-model="expiryDate" type="date" />
        </template>
        <p v-else class="batch-note">Manage batch expiry dates from Inventory when restocking this product.</p>
      </template>
    </div>

    <!-- Step 8: Live summary -->
    <div v-if="showSummary" class="live-summary">
      <p class="summary-title">Stock Summary</p>
      <div class="summary-line">
        <span>Pieces in stock</span>
        <strong>{{ summaryPieces.toLocaleString() }} pcs</strong>
      </div>
      <div class="summary-line">
        <span>Total Capital (Cost × Qty)</span>
        <strong class="red">₱{{ fmt(summaryCapital) }}</strong>
      </div>
      <div class="summary-line">
        <span>Total Value (Price × Qty)</span>
        <strong class="green">₱{{ fmt(summaryValue) }}</strong>
      </div>
    </div>

    <p v-if="error" class="error">{{ error }}</p>

    <button class="save-btn" @click="submitForm">
      {{ editingProduct ? 'Update Product' : 'Add Product' }}
    </button>
    <button v-if="editingProduct" class="cancel-btn" @click="cancelEdit">Cancel</button>
  </section>
</template>

<style scoped>
.form-panel {
  background: rgba(30, 41, 59, 0.9);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 16px;
  box-shadow: 0 22px 65px rgba(0,0,0,0.38);
  max-height: 100%; overflow-y: auto;
}

.form-header { margin-bottom: 12px; }
.form-header h2 { margin: 0; font-size: 18px; }
.form-header p { margin: 2px 0 0; color: #94a3b8; font-size: 12px; }

.scan-btn {
  width: 100%; padding: 10px; border-radius: 10px; margin-bottom: 4px;
  border: 1px solid rgba(34,197,94,0.4);
  background: rgba(34,197,94,0.08);
  color: #22c55e; font-size: 13px; font-weight: 700; cursor: pointer;
  display: flex; align-items: center; justify-content: center; gap: 8px;
}
.scan-btn:hover { background: rgba(34,197,94,0.15); }

.scan-notice {
  padding: 10px 12px; border-radius: 10px; font-size: 13px;
  background: rgba(34,197,94,0.1); border: 1px solid rgba(34,197,94,0.25);
  color: #6ee7b7;
}

label { display: block; margin: 10px 0 5px; color: #d1d5db; font-weight: 700; font-size: 13px; }
.field-hint { color: #475569; font-size: 11px; font-weight: 400; margin-left: 6px; }
.suggested-tag { color: #6ee7b7; font-size: 11px; font-weight: 400; margin-left: 6px; }

.search-wrap { position: relative; }

input[type="text"], input[type="number"], input[type="date"], select {
  width: 100%; padding: 10px 12px; border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827;
  color: white; outline: none; font-size: 13px; box-sizing: border-box;
}
select option { background: #111827; }
input:focus, select:focus { border-color: #22c55e; }
input[type="checkbox"] { accent-color: #22c55e; width: auto; }

.price-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }

/* Sell mode toggle */
.sell-mode-toggle { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.sell-mode-toggle button {
  display: flex; flex-direction: column; align-items: center; gap: 4px;
  padding: 10px 8px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.1);
  background: rgba(255,255,255,0.05); color: #94a3b8;
  font-size: 12px; font-weight: 600; cursor: pointer; line-height: 1.3;
  text-align: center; width: 100%;
}
.sell-mode-toggle button.active {
  background: rgba(34,197,94,0.12); border-color: rgba(34,197,94,0.4); color: #22c55e;
}

/* Alert panel */
.alert-panel {
  margin-top: 10px; padding: 10px 12px; border-radius: 12px;
  background: rgba(251,191,36,0.06); border: 1px solid rgba(251,191,36,0.18);
}
.check-row { display: flex; align-items: center; gap: 8px; margin: 0; }
.mode-toggle { display: flex; gap: 8px; margin-bottom: 8px; }
.mode-toggle button {
  flex: 1; padding: 8px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.12);
  background: rgba(255,255,255,0.06); color: #94a3b8; font-size: 12px; font-weight: 600; cursor: pointer;
}
.mode-toggle button.active { background: rgba(251,191,36,0.14); border-color: rgba(251,191,36,0.38); color: #fbbf24; }
.batch-note { margin: 8px 0 0; color: #fbbf24; font-size: 12px; line-height: 1.4; }

/* Live summary */
.live-summary {
  margin-top: 12px; padding: 12px 14px; border-radius: 12px;
  background: rgba(34,197,94,0.06); border: 1px solid rgba(34,197,94,0.2);
}
.summary-title { margin: 0 0 8px; font-size: 12px; font-weight: 700; color: #6ee7b7; text-transform: uppercase; letter-spacing: 0.5px; }
.summary-line {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 13px; padding: 4px 0; border-bottom: 1px solid rgba(255,255,255,0.05);
}
.summary-line:last-child { border-bottom: none; }
.summary-line span { color: #94a3b8; }
.summary-line .green { color: #22c55e; }
.summary-line .red { color: #f87171; }

/* Spinner & suggestions */
.spinner {
  position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
  width: 14px; height: 14px; border: 2px solid rgba(255,255,255,0.15);
  border-top-color: #22c55e; border-radius: 50%;
  animation: spin 0.6s linear infinite;
}
@keyframes spin { to { transform: translateY(-50%) rotate(360deg); } }

.suggestions {
  position: absolute; top: calc(100% + 4px); left: 0; right: 0;
  background: #1e293b; border: 1px solid rgba(255,255,255,0.12);
  border-radius: 12px; list-style: none; margin: 0; padding: 4px;
  z-index: 100; box-shadow: 0 12px 30px rgba(0,0,0,0.5);
}
.suggestions li {
  display: flex; justify-content: space-between; align-items: center;
  padding: 9px 12px; border-radius: 8px; cursor: pointer; font-size: 13px;
}
.suggestions li:hover { background: rgba(34,197,94,0.12); }
.sug-name { color: #e5e7eb; }
.sug-price { color: #22c55e; font-weight: 700; font-size: 12px; }

.error { color: #fca5a5; background: rgba(239,68,68,0.15); padding: 10px 12px; border-radius: 10px; font-size: 12px; margin-top: 8px; }

button { width: 100%; margin-top: 10px; padding: 10px; border: none; border-radius: 10px; font-weight: 800; cursor: pointer; font-size: 13px; }
.save-btn { background: linear-gradient(135deg, #059669, #34d399); color: white; }
.cancel-btn { background: rgba(255,255,255,0.1); color: white; }
</style>
