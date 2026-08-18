<script setup lang="ts">
import { computed } from 'vue'
import { fmt } from '../../composables/useSettings'
import type { ExpiryBatch, Product, SaleItem, Customer, DailyClosing } from '../../types'
import { effectiveLowStockThreshold, getExpiryStatuses, isLowStock } from '../../lib/stockHealth'
import { inventoryValue, capitalValue } from '../../types'

const props = defineProps<{
  products: Product[]
  expiryBatches: ExpiryBatch[]
  sales: SaleItem[]
  customers: Customer[]
  closings: DailyClosing[]
  currency: string
  lowStockThreshold: number
  expiryWarningDays: number
  perProductThresholdsEnabled: boolean
  totalProfit: number
  totalExpenses: number
  totalCredit: number
}>()

const totalInventoryValue = computed(() =>
  props.products.reduce((s, p) => s + inventoryValue(p), 0)
)
const totalRevenue = computed(() => props.sales.reduce((s, i) => s + i.total, 0))
const lowStockItems = computed(() =>
  props.products.filter(p => isLowStock(p, props.lowStockThreshold, props.perProductThresholdsEnabled))
)
const lowStockCount = computed(() => lowStockItems.value.length)
const outOfStockCount = computed(() => props.products.filter(p => p.quantity === 0).length)
const customersWithBalance = computed(() => props.customers.filter(c => c.currentBalance > 0).length)
const expiryItems = computed(() =>
  getExpiryStatuses(props.products, props.expiryBatches, props.expiryWarningDays)
    .filter(status => status.expired || status.expiringSoon)
)

function thresholdFor(product: Product) {
  return effectiveLowStockThreshold(product, props.lowStockThreshold, props.perProductThresholdsEnabled)
}

const topProducts = computed(() => {
  const map: Record<string, { revenue: number; profit: number }> = {}
  props.sales.forEach(s => {
    const t = map[s.product] ??= { revenue: 0, profit: 0 }
    t.revenue += s.total
    t.profit += s.total - (s.cost ?? 0)
  })
  return Object.entries(map).sort((a, b) => b[1].revenue - a[1].revenue).slice(0, 5)
})

const categoryBreakdown = computed(() => {
  const map: Record<string, number> = {}
  props.products.forEach(p => {
    map[p.category || 'Uncategorized'] = (map[p.category || 'Uncategorized'] || 0) + 1
  })
  return Object.entries(map).sort((a, b) => b[1] - a[1])
})

const topDebtors = computed(() =>
  [...props.customers]
    .filter(c => c.currentBalance > 0)
    .sort((a, b) => b.currentBalance - a.currentBalance)
    .slice(0, 5)
)

// Cash accuracy
const closedDays = computed(() => props.closings.filter(c => c.status === 'closed' && c.variance !== null))

const last7Days = computed(() => {
  const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - 7)
  return closedDays.value.filter(c => new Date(c.date) >= cutoff)
})

const last30Days = computed(() => {
  const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - 30)
  return closedDays.value.filter(c => new Date(c.date) >= cutoff)
})

const totalVariance7 = computed(() => last7Days.value.reduce((s, c) => s + (c.variance ?? 0), 0))
const totalVariance30 = computed(() => last30Days.value.reduce((s, c) => s + (c.variance ?? 0), 0))
const daysWithDiscrepancy7 = computed(() => last7Days.value.filter(c => c.variance !== 0).length)
const avgVariance30 = computed(() => last30Days.value.length ? totalVariance30.value / last30Days.value.length : 0)

const thisWeekCreditCollected = computed(() => {
  const weekAgo = new Date()
  weekAgo.setDate(weekAgo.getDate() - 7)
  // Sum payments in the last 7 days; transaction data is required for the exact value.
  return 0 // placeholder — real value needs credit transactions passed in
})
</script>

<template>
  <div class="view">
    <div class="view-header">
      <h2>Reports</h2>
      <p>Overview of your store performance.</p>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <p>Total Inventory Value</p>
        <h3>{{ currency }}{{ fmt(totalInventoryValue) }}</h3>
      </div>
      <div class="stat-card">
        <p>Total Revenue</p>
        <h3>{{ currency }}{{ fmt(totalRevenue) }}</h3>
      </div>
      <div class="stat-card profit">
        <p>Total Profit</p>
        <h3>{{ currency }}{{ fmt(totalProfit) }}</h3>
      </div>
      <div class="stat-card expense">
        <p>Total Capital (Cost × Qty)</p>
        <h3>{{ currency }}{{ fmt(totalExpenses) }}</h3>
      </div>
      <div class="stat-card">
        <p>Total Products</p>
        <h3>{{ products.length }}</h3>
      </div>
      <div class="stat-card warn">
        <p>Low Stock Items</p>
        <h3>{{ lowStockCount }}</h3>
      </div>
      <div class="stat-card danger">
        <p>Out of Stock</p>
        <h3>{{ outOfStockCount }}</h3>
      </div>
      <div class="stat-card credit">
        <p>Total Outstanding Credit</p>
        <h3>{{ currency }}{{ fmt(totalCredit) }}</h3>
      </div>
      <div class="stat-card">
        <p>Customers with Balance</p>
        <h3>{{ customersWithBalance }}</h3>
      </div>
    </div>

    <div class="bottom-grid">
      <div class="panel stock-health-panel">
        <h3>Stock Health</h3>
        <div class="health-grid">
          <div>
            <h4>Low Stock Action List</h4>
            <table v-if="lowStockItems.length">
              <thead>
                <tr><th>Product</th><th>Current Qty</th><th>Threshold</th></tr>
              </thead>
              <tbody>
                <tr v-for="p in lowStockItems" :key="p.id">
                  <td class="name">{{ p.name }}</td>
                  <td class="amber">{{ p.quantity }} pcs</td>
                  <td>{{ thresholdFor(p) }} pcs</td>
                </tr>
              </tbody>
            </table>
            <div v-else class="empty compact">No low-stock items right now.</div>
          </div>
          <div>
            <h4>Expiry Action List</h4>
            <table v-if="expiryItems.length">
              <thead>
                <tr><th>Product</th><th>Qty</th><th>Expiry</th><th>Status</th></tr>
              </thead>
              <tbody>
                <tr v-for="item in expiryItems" :key="`${item.product.id}-${item.batch?.id ?? item.expiryDate}`">
                  <td class="name">{{ item.product.name }}</td>
                  <td>{{ item.quantity }} pcs</td>
                  <td>{{ new Date(item.expiryDate + 'T00:00:00').toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' }) }}</td>
                  <td :class="item.expired ? 'red' : 'amber'">{{ item.label }}</td>
                </tr>
              </tbody>
            </table>
            <div v-else class="empty compact">No expiring or expired items in the warning window.</div>
          </div>
        </div>
      </div>

      <div class="panel">
        <h3>Top Selling Products</h3>
        <table v-if="topProducts.length">
          <thead>
            <tr><th>Product</th><th>Revenue</th><th>Profit</th></tr>
          </thead>
          <tbody>
            <tr v-for="[name, data] in topProducts" :key="name">
              <td class="name">{{ name }}</td>
              <td>{{ currency }}{{ fmt(data.revenue) }}</td>
              <td class="profit-cell">{{ currency }}{{ fmt(data.profit) }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">No sales data available.</div>
      </div>

      <div class="panel">
        <h3>Products by Category</h3>
        <table v-if="categoryBreakdown.length">
          <thead>
            <tr><th>Category</th><th>Products</th></tr>
          </thead>
          <tbody>
            <tr v-for="[cat, count] in categoryBreakdown" :key="cat">
              <td><span class="cat-badge">{{ cat }}</span></td>
              <td>{{ count }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">No products added yet.</div>
      </div>

      <div class="panel credit-panel">
        <h3>Top 5 Customers by Credit</h3>
        <table v-if="topDebtors.length">
          <thead>
            <tr><th>Customer</th><th>Contact</th><th>Balance Owed</th></tr>
          </thead>
          <tbody>
            <tr v-for="c in topDebtors" :key="c.id">
              <td class="name">{{ c.name }}</td>
              <td>{{ c.contactNumber || '—' }}</td>
              <td class="owed-cell">{{ currency }}{{ fmt(c.currentBalance) }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">No outstanding balances.</div>
      </div>

      <div class="panel cash-panel">
        <h3>Cash Accuracy</h3>
        <div class="accuracy-grid">
          <div class="acc-card">
            <p>Variance (7 days)</p>
            <h3 :class="totalVariance7 === 0 ? 'green' : totalVariance7 < 0 ? 'red' : 'amber'">
              {{ totalVariance7 > 0 ? '+' : '' }}{{ currency }}{{ fmt(totalVariance7) }}
            </h3>
          </div>
          <div class="acc-card">
            <p>Variance (30 days)</p>
            <h3 :class="totalVariance30 === 0 ? 'green' : totalVariance30 < 0 ? 'red' : 'amber'">
              {{ totalVariance30 > 0 ? '+' : '' }}{{ currency }}{{ fmt(totalVariance30) }}
            </h3>
          </div>
          <div class="acc-card">
            <p>Days with Discrepancy (7d)</p>
            <h3 :class="daysWithDiscrepancy7 === 0 ? 'green' : 'red'">{{ daysWithDiscrepancy7 }}</h3>
          </div>
          <div class="acc-card">
            <p>Avg Daily Variance (30d)</p>
            <h3 :class="avgVariance30 === 0 ? 'green' : avgVariance30 < 0 ? 'red' : 'amber'">
              {{ avgVariance30 > 0 ? '+' : '' }}{{ currency }}{{ fmt(avgVariance30) }}
            </h3>
          </div>
        </div>
        <table v-if="closedDays.length" style="margin-top:12px">
          <thead>
            <tr><th>Date</th><th>Expected</th><th>Actual</th><th>Variance</th></tr>
          </thead>
          <tbody>
            <tr v-for="c in [...closedDays].slice(0,10)" :key="c.id">
              <td>{{ new Date(c.date + 'T00:00:00').toLocaleDateString('en-PH', { month:'short', day:'numeric' }) }}</td>
              <td>{{ currency }}{{ fmt(c.openingCash + c.expectedCashSales - c.cashPayouts.reduce((s,p)=>s+p.amount,0)) }}</td>
              <td>{{ c.actualCashCounted !== null ? currency + fmt(c.actualCashCounted) : '—' }}</td>
              <td>
                <span :class="['var-dot', c.variance === 0 ? 'green' : c.variance! < 0 ? 'red' : 'amber']">
                  {{ c.variance! > 0 ? '+' : '' }}{{ currency }}{{ fmt(c.variance!) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">No closed days yet. Close your first day to see cash accuracy.</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.view { padding: 24px; height: 100%; overflow-y: auto; }
.view-header { margin-bottom: 16px; }
.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

.stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }

.stat-card {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 14px; padding: 16px 20px;
}
.stat-card p { margin: 0; font-size: 12px; color: #94a3b8; }
.stat-card h3 { margin: 6px 0 0; font-size: 24px; color: #22c55e; }
.stat-card.profit h3 { color: #818cf8; }
.stat-card.warn h3 { color: #fbbf24; }
.stat-card.danger h3 { color: #f87171; }
.stat-card.expense h3 { color: #f87171; }
.stat-card.credit h3 { color: #fbbf24; }

.bottom-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 16px; }
.stock-health-panel { grid-column: 1 / -1; }
.credit-panel { grid-column: 1 / -1; }
.cash-panel  { grid-column: 1 / -1; }

.health-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.health-grid h4 { margin: 0 0 8px; color: #cbd5e1; font-size: 13px; }

.accuracy-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 12px; margin-bottom: 4px; }
.acc-card { background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); border-radius: 12px; padding: 12px 16px; }
.acc-card p { margin: 0; font-size: 12px; color: #94a3b8; }
.acc-card h3 { margin: 6px 0 0; font-size: 20px; }

.var-dot { font-weight: 700; font-size: 13px; }

.green { color: #22c55e; }
.red   { color: #f87171; }
.amber { color: #fbbf24; }

.cat-badge {
  padding: 3px 8px; border-radius: 6px; font-size: 11px; font-weight: 600;
  background: rgba(99,102,241,0.15); color: #a5b4fc;
}

.profit-cell { color: #818cf8; font-weight: 700; }
.owed-cell { color: #fbbf24; font-weight: 700; }

.panel {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 16px;
}
.panel h3 { margin: 0 0 12px; font-size: 15px; }

table { width: 100%; border-collapse: collapse; }
th { padding: 10px 12px; text-align: left; color: #6ee7b7; font-size: 12px; text-transform: uppercase; }
td { padding: 10px 12px; color: #e5e7eb; font-size: 13px; }
tbody tr:nth-child(even) { background: rgba(255,255,255,0.04); }
tbody tr:hover { background: rgba(255,255,255,0.06); }
.name { font-weight: 700; }
.empty { color: #94a3b8; text-align: center; padding: 30px; }
.empty.compact { padding: 18px; background: rgba(255,255,255,0.035); border-radius: 10px; }

@media (max-width: 900px) {
  .view { padding: 14px; }
  .stats-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .bottom-grid { grid-template-columns: 1fr; }
  .health-grid { grid-template-columns: 1fr; }
  .panel { overflow-x: auto; }
  table { min-width: 420px; }
}

@media (max-width: 520px) {
  .stats-grid { grid-template-columns: 1fr; }
  .stat-card { padding: 13px 14px; }
  .stat-card h3 { font-size: 20px; }
}
</style>
