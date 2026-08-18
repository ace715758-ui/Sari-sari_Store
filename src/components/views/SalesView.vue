<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { fmt } from '../../composables/useSettings'
import type { Product, SaleItem, Customer } from '../../types'

const props = defineProps<{
  products: Product[]
  sales: SaleItem[]
  customers: Customer[]
  currency: string
  lowStockThreshold: number
}>()

const emit = defineEmits<{
  sell: [productId: string, qty: number, paymentMethod: 'cash' | 'credit', creditCustomerId: string | null, newCustomerName: string | null, sellMode: 'pack' | 'piece']
}>()

const selectedId = ref<string | null>(null)
const saleQty = ref<number | null>(null)
const sellMode = ref<'pack' | 'piece'>('pack')
const paymentMethod = ref<'cash' | 'credit'>('cash')
const creditCustomerId = ref<string | null>(null)
const newCustomerName = ref('')
const isNewCustomer = ref(false)
const error = ref('')
const dateFilter = ref<'all' | 'today' | 'week'>('all')

const selectedProduct = computed(() => props.products.find(p => p.id === selectedId.value) ?? null)

// Auto-set sell mode when product changes
watch(selectedId, () => {
  if (selectedProduct.value) {
    sellMode.value = selectedProduct.value.isPerPieceEnabled ? 'piece' : 'pack'
  }
})

const unitPrice = computed(() => {
  if (!selectedProduct.value) return 0
  return sellMode.value === 'piece' ? selectedProduct.value.perPiecePrice : selectedProduct.value.price
})

const previewTotal = computed(() => {
  if (!saleQty.value || !selectedProduct.value) return null
  return unitPrice.value * saleQty.value
})

// Stock available in the chosen unit
const availableInUnit = computed(() => {
  if (!selectedProduct.value) return 0
  if (sellMode.value === 'piece') return selectedProduct.value.quantity
  return Math.floor(selectedProduct.value.quantity / (selectedProduct.value.piecesPerPack || 1))
})

const filteredSales = computed(() => {
  if (dateFilter.value === 'all') return props.sales
  const now = new Date()
  return props.sales.filter(s => {
    const d = new Date(s.date)
    if (dateFilter.value === 'today') return d.toDateString() === now.toDateString()
    if (dateFilter.value === 'week') {
      const weekAgo = new Date(now); weekAgo.setDate(now.getDate() - 7)
      return d >= weekAgo
    }
    return true
  })
})

const totalRevenue = computed(() => props.sales.reduce((s, i) => s + i.total, 0))
const totalProfit = computed(() => props.sales.reduce((s, i) => s + (i.total - (i.cost ?? 0)), 0))
const todayRevenue = computed(() => {
  const today = new Date()
  return props.sales
    .filter(s => new Date(s.date).toDateString() === today.toDateString())
    .reduce((s, i) => s + i.total, 0)
})

function recordSale() {
  if (!selectedProduct.value || !saleQty.value || saleQty.value <= 0) {
    error.value = 'Select a product and enter a valid quantity.'
    return
  }
  if (saleQty.value > availableInUnit.value) {
    const unit = sellMode.value === 'piece' ? 'pieces' : 'packs'
    error.value = `Only ${availableInUnit.value} ${unit} available.`
    return
  }
  if (paymentMethod.value === 'credit') {
    if (isNewCustomer.value && !newCustomerName.value.trim()) {
      error.value = 'Enter a customer name.'
      return
    }
    if (!isNewCustomer.value && !creditCustomerId.value) {
      error.value = 'Select a customer for credit.'
      return
    }
  }
  error.value = ''
  emit('sell',
    selectedProduct.value.id,
    saleQty.value,
    paymentMethod.value,
    isNewCustomer.value ? null : creditCustomerId.value,
    isNewCustomer.value ? newCustomerName.value.trim() : null,
    sellMode.value
  )
  selectedId.value = null
  saleQty.value = null
  creditCustomerId.value = null
  newCustomerName.value = ''
  isNewCustomer.value = false
  paymentMethod.value = 'cash'
  sellMode.value = 'pack'
}
</script>

<template>
  <div class="view">
    <div class="view-header">
      <h2>Sales</h2>
      <p>Sell products and track revenue. Stock is deducted automatically.</p>
    </div>

    <div class="stat-row">
      <div class="stat-card">
        <p>Total Revenue</p>
        <h3>{{ currency }}{{ fmt(totalRevenue) }}</h3>
      </div>
      <div class="stat-card">
        <p>Today's Revenue</p>
        <h3>{{ currency }}{{ fmt(todayRevenue) }}</h3>
      </div>
      <div class="stat-card profit">
        <p>Total Profit</p>
        <h3>{{ currency }}{{ fmt(totalProfit) }}</h3>
      </div>
      <div class="stat-card">
        <p>Total Transactions</p>
        <h3>{{ sales.length }}</h3>
      </div>
    </div>

    <div class="grid">
      <!-- Sell form -->
      <div class="panel form-panel">
        <h3>Record a Sale</h3>

        <label>Product</label>
        <select v-model="selectedId">
          <option :value="null" disabled>Select product</option>
          <option v-for="p in products" :key="p.id" :value="p.id" :disabled="p.quantity === 0">
            {{ p.name }} ({{ p.quantity === 0 ? 'Out of Stock' : p.isPerPieceEnabled ? `${p.quantity} pcs` : `${Math.floor(p.quantity / (p.piecesPerPack||1))} packs` }})
          </option>
        </select>

        <template v-if="selectedProduct">
          <!-- Sell mode toggle — only shown when per-piece selling is enabled -->
          <template v-if="selectedProduct.isPerPieceEnabled">
            <label>Sell by</label>
            <div class="mode-toggle">
              <button :class="{ active: sellMode === 'piece' }" @click="sellMode = 'piece'">
                Per Piece · {{ currency }}{{ fmt(selectedProduct.perPiecePrice) }}
              </button>
              <button :class="{ active: sellMode === 'pack' }" @click="sellMode = 'pack'">
                Per Pack · {{ currency }}{{ fmt(selectedProduct.price) }}
              </button>
            </div>
          </template>

          <div class="stock-hint" :class="availableInUnit <= lowStockThreshold ? 'warn' : ''">
            {{ availableInUnit === 0 ? 'Out of stock' : `${availableInUnit} ${sellMode === 'piece' ? 'pieces' : 'packs'} available` }}
          </div>
        </template>

        <label>Quantity <span v-if="selectedProduct">({{ sellMode === 'piece' ? 'pieces' : 'packs' }})</span></label>
        <input v-model.number="saleQty" type="number" placeholder="0" min="1" />

        <div v-if="previewTotal !== null" class="price-preview">
          Total: <strong>{{ currency }}{{ fmt(previewTotal) }}</strong>
        </div>

        <label>Payment Method</label>
        <div class="method-toggle">
          <button
            :class="{ active: paymentMethod === 'cash' }"
            @click="paymentMethod = 'cash'; creditCustomerId = null"
          >Cash</button>
          <button
            :class="{ active: paymentMethod === 'credit' }"
            @click="paymentMethod = 'credit'"
          >Credit</button>
        </div>

        <template v-if="paymentMethod === 'credit'">
          <label>Customer</label>
          <div class="customer-toggle">
            <button :class="{ active: !isNewCustomer }" @click="isNewCustomer = false">Existing</button>
            <button :class="{ active: isNewCustomer }" @click="isNewCustomer = true">New Customer</button>
          </div>
          <template v-if="isNewCustomer">
            <input v-model="newCustomerName" type="text" placeholder="Enter customer name" />
          </template>
          <template v-else>
            <select v-model="creditCustomerId">
              <option :value="null" disabled>Select customer</option>
              <option v-for="c in customers" :key="c.id" :value="c.id">
                {{ c.name }}{{ c.currentBalance > 0 ? ` (${currency}${fmt(c.currentBalance)} owed)` : '' }}
              </option>
            </select>
            <p v-if="customers.length === 0" class="credit-note">No customers yet — switch to New Customer.</p>
          </template>
          <p class="credit-note">This sale will be charged to the customer's balance.</p>
        </template>

        <p v-if="error" class="error">{{ error }}</p>
        <button @click="recordSale">
          {{ paymentMethod === 'credit' ? 'Record as Credit' : 'Confirm Sale' }}
        </button>
      </div>

      <!-- Sales log -->
      <div class="panel log-panel">
        <div class="log-header">
          <span class="log-title">Sales Log</span>
          <div class="filters">
            <button :class="{ active: dateFilter === 'all' }" @click="dateFilter = 'all'">All</button>
            <button :class="{ active: dateFilter === 'today' }" @click="dateFilter = 'today'">Today</button>
            <button :class="{ active: dateFilter === 'week' }" @click="dateFilter = 'week'">This Week</button>
          </div>
        </div>
        <table v-if="filteredSales.length">
          <thead>
            <tr>
              <th>Product</th>
              <th>Qty</th>
              <th>Mode</th>
              <th>Total</th>
              <th>Profit</th>
              <th>Payment</th>
              <th>Date</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in filteredSales" :key="s.id">
              <td class="name">{{ s.product }}</td>
              <td>{{ s.qty }}</td>
              <td>
                <span class="mode-badge" :class="s.sellMode === 'piece' ? 'per-piece' : 'pack'">
                  {{ s.sellMode === 'piece' ? 'Per-Piece' : 'Pack' }}
                </span>
              </td>
              <td>{{ currency }}{{ fmt(s.total) }}</td>
              <td class="profit-cell">{{ currency }}{{ fmt(s.total - (s.cost ?? 0)) }}</td>
              <td>
                <span class="pay-badge" :class="(s as any).paymentMethod === 'credit' ? 'credit' : 'cash'">
                  {{ (s as any).paymentMethod === 'credit' ? 'Credit' : 'Cash' }}
                </span>
              </td>
              <td>{{ new Date(s.date).toLocaleDateString() }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">No sales for this period.</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.view { padding: 24px; height: 100%; min-height: 0; display: flex; flex-direction: column; gap: 12px; overflow: hidden; }
.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

.stat-row { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
.stat-card {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 14px; padding: 14px 18px;
}
.stat-card p { margin: 0; font-size: 12px; color: #94a3b8; }
.stat-card h3 { margin: 6px 0 0; font-size: 22px; color: #22c55e; }
.stat-card.profit h3 { color: #818cf8; }
.profit-cell { color: #818cf8; font-weight: 700; }

.grid { display: grid; grid-template-columns: 300px 1fr; gap: 16px; flex: 1; min-height: 0; }

.panel {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 16px;
  min-height: 0; overflow-y: auto;
}

.form-panel h3 { margin: 0 0 14px; font-size: 15px; }
label { display: block; margin: 12px 0 5px; color: #d1d5db; font-size: 13px; font-weight: 600; }

select, input {
  width: 100%; padding: 9px 12px; border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827;
  color: white; outline: none; font-size: 13px; box-sizing: border-box;
}
select option { background: #111827; }
input:focus, select:focus { border-color: #22c55e; }

.stock-hint { margin-top: 6px; font-size: 12px; color: #6ee7b7; }
.stock-hint.warn { color: #fbbf24; }

.mode-toggle { display: flex; gap: 8px; }
.mode-toggle button {
  flex: 1; padding: 8px; border-radius: 10px; margin-top: 0;
  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12);
  color: #94a3b8; font-weight: 700; cursor: pointer; font-size: 12px; line-height: 1.3;
}
.mode-toggle button.active {
  background: rgba(165,180,252,0.15); border-color: rgba(165,180,252,0.4); color: #a5b4fc;
}

.price-preview {
  margin-top: 8px; padding: 8px 12px; border-radius: 8px;
  background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.2);
  font-size: 13px; color: #94a3b8;
}
.price-preview strong { color: #22c55e; }

.mode-badge { padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
.mode-badge.per-piece { background: rgba(165,180,252,0.15); color: #a5b4fc; }
.mode-badge.pack { background: rgba(34,197,94,0.15); color: #6ee7b7; }

.method-toggle { display: flex; gap: 8px; }
.method-toggle button {
  flex: 1; padding: 9px; border-radius: 10px; margin-top: 0;
  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12);
  color: #94a3b8; font-weight: 700; cursor: pointer; font-size: 13px;
}
.method-toggle button.active {
  background: rgba(34,197,94,0.15); border-color: rgba(34,197,94,0.4); color: #22c55e;
}
.method-toggle button:last-child.active {
  background: rgba(251,191,36,0.12); border-color: rgba(251,191,36,0.4); color: #fbbf24;
}

.credit-note { margin: 6px 0 0; font-size: 12px; color: #fbbf24; }

.customer-toggle { display: flex; gap: 8px; margin-bottom: 2px; }
.customer-toggle button {
  flex: 1; padding: 7px; border-radius: 8px; margin-top: 0;
  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12);
  color: #94a3b8; font-weight: 700; cursor: pointer; font-size: 12px;
}
.customer-toggle button.active {
  background: rgba(251,191,36,0.15); border-color: rgba(251,191,36,0.4); color: #fbbf24;
}

button {
  width: 100%; margin-top: 14px; padding: 10px; border: none;
  border-radius: 10px; background: linear-gradient(135deg, #059669, #34d399);
  color: white; font-weight: 700; cursor: pointer; font-size: 13px;
}

.error { color: #fca5a5; background: rgba(239,68,68,0.15); padding: 8px 12px; border-radius: 8px; font-size: 12px; margin-top: 8px; }

.log-panel { display: flex; flex-direction: column; }
.log-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
.log-title { font-size: 14px; font-weight: 700; color: #e5e7eb; }
.filters { display: flex; gap: 6px; }
.filters button {
  width: auto; margin-top: 0; padding: 5px 12px;
  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.1);
  color: #94a3b8; font-size: 12px; font-weight: 600; border-radius: 8px; cursor: pointer;
}
.filters button.active { background: rgba(34,197,94,0.18); border-color: rgba(34,197,94,0.4); color: #22c55e; }

.pay-badge { padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
.pay-badge.cash { background: rgba(34,197,94,0.15); color: #6ee7b7; }
.pay-badge.credit { background: rgba(251,191,36,0.15); color: #fbbf24; }

table { width: 100%; border-collapse: collapse; }
th { padding: 10px 12px; text-align: left; color: #6ee7b7; font-size: 12px; text-transform: uppercase; white-space: nowrap; }
td { padding: 10px 12px; color: #e5e7eb; font-size: 13px; white-space: nowrap; }
tbody tr:nth-child(even) { background: rgba(255,255,255,0.04); }
tbody tr:hover { background: rgba(34,197,94,0.08); }
.name { font-weight: 700; }
.empty { color: #94a3b8; text-align: center; padding: 40px; font-size: 14px; }
</style>
