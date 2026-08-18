<script setup lang="ts">
import { ref, computed } from 'vue'
import { fmt } from '../../composables/useSettings'
import type { DailyClosing, CashPayout, SaleItem } from '../../types'

const props = defineProps<{
  sales: SaleItem[]
  closings: DailyClosing[]
  currency: string
}>()

const emit = defineEmits<{
  'save-closing': [data: {
    date: string
    openingCash: number
    expectedCashSales: number
    expectedCreditSales: number
    cashPayouts: CashPayout[]
    actualCashCounted: number
    variance: number
    notes: string
    status: 'open' | 'closed'
  }]
  'reopen-closing': [id: string]
}>()

const today = new Date().toISOString().slice(0, 10)

const todayClosing = computed(() =>
  props.closings.find(c => c.date === today) ?? null
)

const lastClosed = computed(() =>
  [...props.closings]
    .filter(c => c.status === 'closed' && c.date < today)
    .sort((a, b) => b.date.localeCompare(a.date))[0] ?? null
)

const todaySales = computed(() =>
  props.sales.filter(s => {
    const d = new Date(s.date)
    const t = new Date(today)
    return d.toDateString() === t.toDateString()
  })
)

const todayCashSales = computed(() =>
  todaySales.value
    .filter(s => (s as any).paymentMethod !== 'credit')
    .reduce((sum, s) => sum + s.total, 0)
)

const todayCreditSales = computed(() =>
  todaySales.value
    .filter(s => (s as any).paymentMethod === 'credit')
    .reduce((sum, s) => sum + s.total, 0)
)

// Opening cash: from last closing or manual
const openingCash = ref<number>(
  todayClosing.value?.openingCash ?? lastClosed.value?.actualCashCounted ?? 0
)
const isFirstDay = computed(() => !lastClosed.value && !todayClosing.value)

// Payouts
const payouts = ref<CashPayout[]>(
  todayClosing.value?.cashPayouts ?? []
)
const newPayoutAmount = ref<number | null>(null)
const newPayoutNote = ref('')
const showPayoutForm = ref(false)

function addPayout() {
  if (!newPayoutAmount.value || newPayoutAmount.value <= 0) return
  payouts.value.push({ amount: newPayoutAmount.value, note: newPayoutNote.value.trim() })
  newPayoutAmount.value = null
  newPayoutNote.value = ''
  showPayoutForm.value = false
}

function removePayout(i: number) {
  payouts.value.splice(i, 1)
}

const totalPayouts = computed(() =>
  payouts.value.reduce((s, p) => s + p.amount, 0)
)

const expectedInDrawer = computed(() =>
  openingCash.value + todayCashSales.value - totalPayouts.value
)

const actualCash = ref<number | null>(
  todayClosing.value?.actualCashCounted ?? null
)
const closingNotes = ref(todayClosing.value?.notes ?? '')

const variance = computed(() => {
  if (actualCash.value === null) return null
  return actualCash.value - expectedInDrawer.value
})

const varianceClass = computed(() => {
  if (variance.value === null) return ''
  if (variance.value === 0) return 'zero'
  if (variance.value < 0) return 'negative'
  return 'positive'
})

const varianceLabel = computed(() => {
  if (variance.value === null) return ''
  if (variance.value === 0) return 'Exact match'
  if (variance.value < 0) return `Short by ${props.currency}${fmt(Math.abs(variance.value))}`
  return `Over by ${props.currency}${fmt(variance.value)}`
})

function saveClosing(close: boolean) {
  if (actualCash.value === null) return
  emit('save-closing', {
    date: today,
    openingCash: openingCash.value,
    expectedCashSales: todayCashSales.value,
    expectedCreditSales: todayCreditSales.value,
    cashPayouts: payouts.value,
    actualCashCounted: actualCash.value,
    variance: variance.value!,
    notes: closingNotes.value,
    status: close ? 'closed' : 'open',
  })
}

// History view
const showHistory = ref(false)
const selectedClosing = ref<DailyClosing | null>(null)
</script>

<template>
  <div class="view">
    <div class="view-header">
      <div>
        <h2>Close Day</h2>
        <p>End-of-day cash reconciliation — compare expected vs actual cash in the drawer.</p>
      </div>
      <button class="history-btn" @click="showHistory = !showHistory; selectedClosing = null">
        {{ showHistory ? 'Back to Today' : 'View History' }}
      </button>
    </div>

    <!-- ── HISTORY ── -->
    <template v-if="showHistory && !selectedClosing">
      <div class="panel flex-panel">
        <div v-if="!closings.length" class="empty">No closing records yet.</div>
        <table v-else>
          <thead>
            <tr>
              <th>Date</th>
              <th>Opening</th>
              <th>Expected</th>
              <th>Actual</th>
              <th>Variance</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="c in [...closings].sort((a,b) => b.date.localeCompare(a.date))"
              :key="c.id"
              class="clickable"
              @click="selectedClosing = c"
            >
              <td>{{ new Date(c.date + 'T00:00:00').toLocaleDateString('en-PH', { weekday:'short', month:'short', day:'numeric' }) }}</td>
              <td>{{ currency }}{{ fmt(c.openingCash) }}</td>
              <td>{{ currency }}{{ fmt(c.openingCash + c.expectedCashSales - c.cashPayouts.reduce((s,p)=>s+p.amount,0)) }}</td>
              <td>{{ c.actualCashCounted !== null ? currency + fmt(c.actualCashCounted) : '—' }}</td>
              <td>
                <span v-if="c.variance !== null" :class="['var-badge', c.variance === 0 ? 'zero' : c.variance < 0 ? 'negative' : 'positive']">
                  {{ c.variance === 0 ? '✓ 0' : c.variance > 0 ? `+${currency}${fmt(c.variance)}` : `-${currency}${fmt(Math.abs(c.variance))}` }}
                </span>
                <span v-else class="muted">—</span>
              </td>
              <td>
                <span :class="['status-badge', c.status]">{{ c.status }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <!-- ── HISTORY DETAIL ── -->
    <template v-else-if="showHistory && selectedClosing">
      <button class="back-btn" @click="selectedClosing = null">← Back to History</button>
      <div class="detail-grid">
        <div class="panel">
          <h3>{{ new Date(selectedClosing.date + 'T00:00:00').toLocaleDateString('en-PH', { weekday:'long', year:'numeric', month:'long', day:'numeric' }) }}</h3>
          <div class="summary-row">
            <span>Opening Cash</span><strong>{{ currency }}{{ fmt(selectedClosing.openingCash) }}</strong>
          </div>
          <div class="summary-row">
            <span>Cash Sales</span><strong class="green">+{{ currency }}{{ fmt(selectedClosing.expectedCashSales) }}</strong>
          </div>
          <div class="summary-row">
            <span>Credit Sales (info only)</span><strong class="muted">{{ currency }}{{ fmt(selectedClosing.expectedCreditSales) }}</strong>
          </div>
          <div v-if="selectedClosing.cashPayouts.length" class="summary-row">
            <span>Cash Payouts</span><strong class="red">-{{ currency }}{{ fmt(selectedClosing.cashPayouts.reduce((s,p)=>s+p.amount,0)) }}</strong>
          </div>
          <div class="summary-row divider">
            <span>Expected in Drawer</span>
            <strong>{{ currency }}{{ fmt(selectedClosing.openingCash + selectedClosing.expectedCashSales - selectedClosing.cashPayouts.reduce((s,p)=>s+p.amount,0)) }}</strong>
          </div>
          <div class="summary-row">
            <span>Actual Counted</span>
            <strong>{{ selectedClosing.actualCashCounted !== null ? currency + fmt(selectedClosing.actualCashCounted) : '—' }}</strong>
          </div>
          <div v-if="selectedClosing.variance !== null" class="summary-row">
            <span>Variance</span>
            <strong :class="selectedClosing.variance === 0 ? 'green' : selectedClosing.variance < 0 ? 'red' : 'amber'">
              {{ selectedClosing.variance > 0 ? '+' : '' }}{{ currency }}{{ fmt(selectedClosing.variance) }}
            </strong>
          </div>
          <p v-if="selectedClosing.notes" class="notes-text">{{ selectedClosing.notes }}</p>
          <button v-if="selectedClosing.status === 'closed'" class="reopen-btn" @click="emit('reopen-closing', selectedClosing.id)">
            Reopen Day
          </button>
        </div>

        <div v-if="selectedClosing.cashPayouts.length" class="panel">
          <h3>Cash Payouts</h3>
          <div v-for="(p, i) in selectedClosing.cashPayouts" :key="i" class="payout-item">
            <span>{{ p.note || 'No note' }}</span>
            <strong class="red">-{{ currency }}{{ fmt(p.amount) }}</strong>
          </div>
        </div>
      </div>
    </template>

    <!-- ── TODAY ── -->
    <template v-else>
      <!-- Already closed banner -->
      <div v-if="todayClosing?.status === 'closed'" class="closed-banner">
        Today is closed. Actual: {{ currency }}{{ fmt(todayClosing.actualCashCounted!) }}
        · Variance:
        <span :class="todayClosing.variance === 0 ? 'green' : todayClosing.variance! < 0 ? 'red' : 'amber'">
          {{ todayClosing.variance! > 0 ? '+' : '' }}{{ currency }}{{ fmt(todayClosing.variance!) }}
        </span>
        <button class="reopen-btn-sm" @click="emit('reopen-closing', todayClosing.id)">Reopen</button>
      </div>

      <div class="today-grid" :class="{ dimmed: todayClosing?.status === 'closed' }">
        <!-- Left: summary -->
        <div class="panel">
          <h3>Today's Summary · {{ new Date().toLocaleDateString('en-PH', { weekday:'short', month:'short', day:'numeric' }) }}</h3>

          <div v-if="isFirstDay" class="first-day-notice">
            First closing ever — please enter your starting cash amount.
          </div>

          <div class="line">
            <span>Opening Cash</span>
            <input
              v-if="!todayClosing || todayClosing.status === 'open'"
              v-model.number="openingCash"
              type="number"
              class="inline-input"
              :disabled="!!lastClosed"
            />
            <strong v-else>{{ currency }}{{ fmt(openingCash) }}</strong>
          </div>

          <div class="line green-line">
            <span>Cash Sales Today</span>
            <strong class="green">+{{ currency }}{{ fmt(todayCashSales) }}</strong>
          </div>

          <div class="line muted-line">
            <span>Credit Sales Today <small>(not in cash)</small></span>
            <span class="muted">{{ currency }}{{ fmt(todayCreditSales) }}</span>
          </div>

          <div v-if="payouts.length" class="line">
            <span>Cash Payouts</span>
            <strong class="red">-{{ currency }}{{ fmt(totalPayouts) }}</strong>
          </div>

          <div class="line expected-line">
            <span>Expected in Drawer</span>
            <strong>{{ currency }}{{ fmt(expectedInDrawer) }}</strong>
          </div>
        </div>

        <!-- Right: count + close -->
        <div class="panel">
          <h3>Count & Close</h3>

          <!-- Payouts -->
          <div class="payout-section">
            <div class="payout-header">
              <span class="label">Cash Payouts</span>
              <button class="add-payout-btn" @click="showPayoutForm = !showPayoutForm"
                :disabled="todayClosing?.status === 'closed'">
                + Add Payout
              </button>
            </div>
            <div v-if="showPayoutForm" class="payout-form">
              <input v-model.number="newPayoutAmount" type="number" placeholder="Amount" />
              <input v-model="newPayoutNote" type="text" placeholder="Note (e.g. ice restock)" />
              <button class="confirm-btn" @click="addPayout">Add</button>
              <button class="cancel-btn" @click="showPayoutForm = false">✕</button>
            </div>
            <div v-for="(p, i) in payouts" :key="i" class="payout-item">
              <span>{{ p.note || 'No note' }}</span>
              <div>
                <strong class="red">-{{ currency }}{{ fmt(p.amount) }}</strong>
                <button v-if="todayClosing?.status !== 'closed'" class="remove-btn" @click="removePayout(i)">✕</button>
              </div>
            </div>
            <p v-if="!payouts.length" class="muted" style="font-size:12px;margin:4px 0 0">No payouts logged.</p>
          </div>

          <!-- Actual count -->
          <label class="count-label">Actual Cash Counted</label>
          <input
            v-model.number="actualCash"
            type="number"
            class="count-input"
            placeholder="Enter amount..."
            :disabled="todayClosing?.status === 'closed'"
          />

          <!-- Variance display -->
          <div v-if="variance !== null" :class="['variance-box', varianceClass]">
            <span class="var-label">{{ varianceLabel }}</span>
            <strong>{{ variance > 0 ? '+' : '' }}{{ currency }}{{ fmt(variance) }}</strong>
          </div>

          <!-- Notes -->
          <label class="count-label" style="margin-top:10px">Notes (optional)</label>
          <input
            v-model="closingNotes"
            type="text"
            placeholder="e.g. short because of change given"
            :disabled="todayClosing?.status === 'closed'"
          />

          <!-- Actions -->
          <template v-if="todayClosing?.status !== 'closed'">
            <button class="save-btn" @click="saveClosing(false)" :disabled="actualCash === null">
              Save Draft
            </button>
            <button class="close-btn" @click="saveClosing(true)" :disabled="actualCash === null">
              Close Day
            </button>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.view { padding: 24px; height: 100%; min-height: 0; display: flex; flex-direction: column; gap: 12px; overflow-y: auto; }
.view-header { display: flex; align-items: flex-start; justify-content: space-between; }
.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }

.history-btn {
  padding: 7px 16px; border: 1px solid rgba(255,255,255,0.12); border-radius: 10px;
  background: rgba(255,255,255,0.06); color: #cbd5e1; cursor: pointer; font-size: 13px;
  white-space: nowrap;
}

.panel {
  background: rgba(15,23,42,0.86); border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 18px;
}
.panel h3 { margin: 0 0 14px; font-size: 15px; }

.flex-panel { flex: 1; min-height: 0; overflow-y: auto; }

/* Today grid */
.today-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.today-grid.dimmed { opacity: 0.6; pointer-events: none; }

/* Summary lines */
.line { display: flex; justify-content: space-between; align-items: center; padding: 8px 0; font-size: 13px; border-bottom: 1px solid rgba(255,255,255,0.05); }
.expected-line { border-top: 1px solid rgba(255,255,255,0.12); margin-top: 4px; padding-top: 10px; font-weight: 700; border-bottom: none; }
.muted-line span { color: #94a3b8; }

.inline-input {
  width: 120px; padding: 5px 10px; border-radius: 8px; text-align: right;
  border: 1px solid rgba(34,197,94,0.4); background: #111827; color: white; font-size: 13px; outline: none;
}

/* Payouts */
.payout-section { margin-bottom: 14px; }
.payout-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.label { font-size: 13px; font-weight: 600; color: #d1d5db; }

.add-payout-btn {
  padding: 4px 12px; border: 1px solid rgba(251,191,36,0.3); border-radius: 8px;
  background: rgba(251,191,36,0.08); color: #fbbf24; font-size: 12px; font-weight: 700; cursor: pointer;
}
.add-payout-btn:disabled { opacity: 0.4; cursor: not-allowed; }

.payout-form { display: flex; gap: 6px; margin-bottom: 8px; flex-wrap: wrap; }
.payout-form input {
  padding: 7px 10px; border-radius: 8px; font-size: 13px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827; color: white; outline: none;
}
.payout-form input:first-child { width: 100px; }
.payout-form input:nth-child(2) { flex: 1; min-width: 120px; }

.payout-item { display: flex; justify-content: space-between; align-items: center; font-size: 13px; padding: 4px 0; color: #e5e7eb; }
.payout-item > div { display: flex; align-items: center; gap: 8px; }
.remove-btn { padding: 2px 7px; border-radius: 6px; border: none; background: rgba(239,68,68,0.15); color: #f87171; cursor: pointer; font-size: 11px; }

/* Count */
.count-label { display: block; font-size: 13px; font-weight: 600; color: #d1d5db; margin-bottom: 6px; }
.count-input {
  width: 100%; padding: 12px; border-radius: 10px; font-size: 20px; font-weight: 700; text-align: center;
  border: 2px solid rgba(34,197,94,0.3); background: #111827; color: white; outline: none; box-sizing: border-box;
}
.count-input:focus { border-color: #22c55e; }
.count-input:disabled { opacity: 0.5; }

/* Variance */
.variance-box {
  margin-top: 10px; padding: 12px 16px; border-radius: 12px;
  display: flex; justify-content: space-between; align-items: center;
  font-size: 14px;
}
.variance-box.zero    { background: rgba(34,197,94,0.12); border: 1px solid rgba(34,197,94,0.3); color: #6ee7b7; }
.variance-box.negative { background: rgba(239,68,68,0.12); border: 1px solid rgba(239,68,68,0.3); color: #fca5a5; }
.variance-box.positive { background: rgba(251,191,36,0.1); border: 1px solid rgba(251,191,36,0.3); color: #fbbf24; }
.variance-box strong { font-size: 18px; }

/* Buttons */
.save-btn, .close-btn {
  width: 100%; margin-top: 10px; padding: 10px; border: none; border-radius: 10px;
  font-weight: 700; cursor: pointer; font-size: 13px;
}
.save-btn { background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12); color: #cbd5e1; }
.close-btn { background: linear-gradient(135deg, #059669, #34d399); color: white; }
.save-btn:disabled, .close-btn:disabled { opacity: 0.4; cursor: not-allowed; }

/* Closed banner */
.closed-banner {
  padding: 12px 16px; border-radius: 12px;
  background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.2);
  font-size: 13px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
}
.reopen-btn-sm {
  margin-left: auto; padding: 5px 12px; border-radius: 8px;
  background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12);
  color: #cbd5e1; cursor: pointer; font-size: 12px;
}

/* History */
table { width: 100%; border-collapse: collapse; }
th { padding: 10px 12px; text-align: left; color: #6ee7b7; font-size: 12px; text-transform: uppercase; white-space: nowrap; position: sticky; top: 0; background: rgba(15,23,42,0.98); }
td { padding: 10px 12px; color: #e5e7eb; font-size: 13px; }
tr.clickable { cursor: pointer; }
tr.clickable:hover td { background: rgba(255,255,255,0.04); }

.var-badge { padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
.var-badge.zero     { background: rgba(34,197,94,0.15); color: #6ee7b7; }
.var-badge.negative { background: rgba(239,68,68,0.15); color: #fca5a5; }
.var-badge.positive { background: rgba(251,191,36,0.12); color: #fbbf24; }

.status-badge { padding: 3px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; text-transform: capitalize; }
.status-badge.closed { background: rgba(34,197,94,0.15); color: #6ee7b7; }
.status-badge.open   { background: rgba(251,191,36,0.12); color: #fbbf24; }

/* Detail */
.detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.back-btn { padding: 7px 14px; border-radius: 8px; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); color: #cbd5e1; cursor: pointer; font-size: 13px; width: fit-content; }
.summary-row { display: flex; justify-content: space-between; padding: 7px 0; font-size: 13px; border-bottom: 1px solid rgba(255,255,255,0.05); }
.summary-row.divider { border-top: 1px solid rgba(255,255,255,0.12); font-weight: 700; border-bottom: none; padding-top: 10px; }
.notes-text { margin: 12px 0 0; font-size: 13px; color: #94a3b8; font-style: italic; }
.reopen-btn { margin-top: 14px; padding: 9px 16px; border-radius: 10px; background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.12); color: #cbd5e1; cursor: pointer; font-size: 13px; width: 100%; }

/* Shared colors */
.green { color: #22c55e; }
.red   { color: #f87171; }
.amber { color: #fbbf24; }
.muted { color: #475569; }

.confirm-btn { padding: 7px 14px; border: none; border-radius: 8px; background: linear-gradient(135deg,#059669,#34d399); color: white; font-weight: 700; cursor: pointer; font-size: 12px; }
.cancel-btn  { padding: 7px 10px; border-radius: 8px; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.1); color: #cbd5e1; cursor: pointer; font-size: 12px; }

.first-day-notice { background: rgba(251,191,36,0.1); border: 1px solid rgba(251,191,36,0.3); border-radius: 10px; padding: 10px 12px; font-size: 13px; color: #fbbf24; margin-bottom: 12px; }
.empty { color: #94a3b8; text-align: center; padding: 40px; font-size: 14px; }
</style>
