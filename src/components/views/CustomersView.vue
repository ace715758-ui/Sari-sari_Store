<script setup lang="ts">
import { ref, computed } from 'vue'
import { fmt } from '../../composables/useSettings'
import type { Customer, CreditTransaction } from '../../types'

const props = defineProps<{
  customers: Customer[]
  transactions: CreditTransaction[]
  currency: string
}>()

const emit = defineEmits<{
  'record-payment': [customerId: string, amount: number, note: string]
  'delete-customer': [id: string]
}>()

// ── List state ──────────────────────────────────────────────
const search = ref('')
const sortBy = ref<'balance' | 'name'>('balance')
const selectedId = ref<string | null>(null)

const totalOutstanding = computed(() =>
  props.customers.reduce((s, c) => s + c.currentBalance, 0)
)
const customersWithBalance = computed(() =>
  props.customers.filter(c => c.currentBalance > 0).length
)

const filteredCustomers = computed(() => {
  let list = props.customers.filter(c =>
    c.name.toLowerCase().includes(search.value.toLowerCase())
  )
  if (sortBy.value === 'balance') {
    list = [...list].sort((a, b) => b.currentBalance - a.currentBalance)
  } else {
    list = [...list].sort((a, b) => a.name.localeCompare(b.name))
  }
  return list
})

const selectedCustomer = computed(() =>
  props.customers.find(c => c.id === selectedId.value) ?? null
)

const customerTransactions = computed(() =>
  props.transactions
    .filter(t => t.customerId === selectedId.value)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
)

// ── Payment form ─────────────────────────────────────────────
const showPayment = ref(false)
const payAmount = ref<number | null>(null)
const payNote = ref('')
const payError = ref('')

function submitPayment() {
  if (!selectedCustomer.value) return
  if (!payAmount.value || payAmount.value <= 0) {
    payError.value = 'Enter a valid amount.'
    return
  }
  if (payAmount.value > selectedCustomer.value.currentBalance) {
    payError.value = `Amount exceeds balance of ${props.currency}${fmt(selectedCustomer.value.currentBalance)}.`
    return
  }
  emit('record-payment', selectedCustomer.value.id, payAmount.value, payNote.value.trim())
  payAmount.value = null
  payNote.value = ''
  payError.value = ''
  showPayment.value = false
}

// ── Delete ───────────────────────────────────────────────────
function requestDelete(c: Customer) {
  const msg = c.currentBalance > 0
    ? `${c.name} still has an outstanding balance of ${props.currency}${fmt(c.currentBalance)}. Delete anyway?`
    : `Delete ${c.name}?`
  if (confirm(msg)) emit('delete-customer', c.id)
}

// ── Running balance helper ───────────────────────────────────
function runningBalance(txns: CreditTransaction[], upToIndex: number) {
  let bal = 0
  for (let i = txns.length - 1; i >= upToIndex; i--) {
    const txn = txns[i]
    if (!txn) continue
    bal += txn.type === 'charge' ? txn.amount : -txn.amount
  }
  return bal
}
</script>

<template>
  <div class="view">

    <!-- ── DETAIL VIEW ── -->
    <template v-if="selectedId && selectedCustomer">
      <div class="detail-header">
        <button class="back-btn" @click="selectedId = null; showPayment = false">← Back</button>
        <div class="detail-title">
          <h2>{{ selectedCustomer.name }}</h2>
          <p v-if="selectedCustomer.contactNumber">{{ selectedCustomer.contactNumber }}</p>
        </div>
        <div class="balance-badge" :class="selectedCustomer.currentBalance > 0 ? 'owed' : 'clear'">
          {{ selectedCustomer.currentBalance > 0
            ? `${currency}${fmt(selectedCustomer.currentBalance)} owed`
            : 'No balance' }}
        </div>
        <button
          class="pay-btn"
          :disabled="selectedCustomer.currentBalance === 0"
          @click="showPayment = !showPayment"
        >
          Record Payment
        </button>
        <button class="del-btn" @click="requestDelete(selectedCustomer)">Delete</button>
      </div>

      <!-- Payment form -->
      <div v-if="showPayment" class="payment-bar">
        <span class="bar-label">Payment from <strong>{{ selectedCustomer.name }}</strong></span>
        <input v-model.number="payAmount" type="number" placeholder="Amount" min="0.01" />
        <input v-model="payNote" type="text" placeholder="Note (optional)" class="note-input" />
        <span v-if="payError" class="bar-error">{{ payError }}</span>
        <button class="confirm-btn" @click="submitPayment">Confirm</button>
        <button class="cancel-btn" @click="showPayment = false; payError = ''">Cancel</button>
      </div>

      <p v-if="selectedCustomer.notes" class="customer-notes">{{ selectedCustomer.notes }}</p>

      <!-- Transaction history -->
      <div class="panel flex-panel">
        <p class="panel-title">Transaction History</p>
        <div v-if="!customerTransactions.length" class="empty">No transactions yet.</div>
        <table v-else>
          <thead>
            <tr>
              <th>Date</th>
              <th>Type</th>
              <th>Note</th>
              <th>Amount</th>
              <th>Balance After</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(t, i) in customerTransactions" :key="t.id">
              <td>{{ new Date(t.date).toLocaleDateString() }}</td>
              <td>
                <span class="type-badge" :class="t.type">
                  {{ t.type === 'charge' ? 'Credit' : 'Payment' }}
                </span>
              </td>
              <td class="note-cell">{{ t.note || '—' }}</td>
              <td :class="t.type === 'charge' ? 'charge-amt' : 'pay-amt'">
                {{ t.type === 'charge' ? '+' : '-' }}{{ currency }}{{ fmt(t.amount) }}
              </td>
              <td>{{ currency }}{{ fmt(runningBalance(customerTransactions, i)) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <!-- ── LIST / OVERVIEW ── -->
    <template v-else>
      <div class="view-header">
        <div>
          <h2>Customers</h2>
          <p>Overview of customer credit. Customers are added automatically when a sale is recorded on credit.</p>
        </div>
      </div>

      <!-- Summary cards -->
      <div class="summary-row">
        <div class="summary-card owed">
          <p>Total Outstanding</p>
          <h3>{{ currency }}{{ fmt(totalOutstanding) }}</h3>
        </div>
        <div class="summary-card">
          <p>Customers with Balance</p>
          <h3>{{ customersWithBalance }}</h3>
        </div>
        <div class="summary-card">
          <p>Total Customers</p>
          <h3>{{ customers.length }}</h3>
        </div>
      </div>

      <!-- Controls -->
      <div class="controls">
        <input v-model="search" type="text" placeholder="Search customer..." class="search-input" />
        <select v-model="sortBy">
          <option value="balance">Sort: Highest Balance</option>
          <option value="name">Sort: Name A–Z</option>
        </select>
      </div>

      <!-- Customer list -->
      <div class="panel flex-panel">
        <div v-if="!filteredCustomers.length" class="empty">
          {{ customers.length === 0
            ? 'No customers yet. Record a credit sale to add the first customer.'
            : 'No customers match your search.' }}
        </div>
        <table v-else>
          <thead>
            <tr>
              <th>Name</th>
              <th>Contact</th>
              <th>Balance Owed</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in filteredCustomers" :key="c.id">
              <td class="cust-name" @click="selectedId = c.id">{{ c.name }}</td>
              <td>{{ c.contactNumber || '—' }}</td>
              <td :class="c.currentBalance > 0 ? 'owed-amt' : ''">
                {{ currency }}{{ fmt(c.currentBalance) }}
              </td>
              <td>
                <span class="status-badge" :class="c.currentBalance > 0 ? 'owed' : 'clear'">
                  {{ c.currentBalance > 0 ? 'Has Balance' : 'Settled' }}
                </span>
              </td>
              <td>
                <button class="view-btn" @click="selectedId = c.id">View</button>
                <button class="del-btn-sm" @click="requestDelete(c)">Delete</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

<style scoped>
.view { padding: 24px; height: 100%; min-height: 0; display: flex; flex-direction: column; gap: 12px; overflow: hidden; }

.view-header h2 { margin: 0; font-size: 20px; }
.view-header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; max-width: 560px; }

/* Summary cards */
.summary-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.summary-card {
  background: rgba(15,23,42,0.86); border: 1px solid rgba(255,255,255,0.1);
  border-radius: 14px; padding: 14px 18px;
}
.summary-card p { margin: 0; font-size: 12px; color: #94a3b8; }
.summary-card h3 { margin: 6px 0 0; font-size: 22px; color: #22c55e; }
.summary-card.owed h3 { color: #fbbf24; }

/* Controls */
.controls { display: flex; gap: 10px; align-items: center; }
.search-input { flex: 1; max-width: 280px; }

input, select {
  padding: 8px 12px; border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1); background: #111827;
  color: white; outline: none; font-size: 13px;
}
input:focus, select:focus { border-color: #22c55e; }
select option { background: #111827; }

/* Panel */
.panel {
  background: rgba(15,23,42,0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px; padding: 16px;
}
.flex-panel { flex: 1; min-height: 0; overflow-y: auto; }
.panel-title { margin: 0 0 12px; font-size: 14px; font-weight: 700; color: #e5e7eb; }

/* Table */
table { width: 100%; border-collapse: collapse; }
th { position: sticky; top: 0; z-index: 2; background: rgba(15,23,42,0.98); padding: 10px 12px; text-align: left; color: #6ee7b7; font-size: 12px; text-transform: uppercase; white-space: nowrap; }
td { padding: 10px 12px; color: #e5e7eb; font-size: 13px; white-space: nowrap; }
tbody tr:nth-child(even) { background: rgba(255,255,255,0.04); }
tbody tr:hover { background: rgba(255,255,255,0.07); }

.cust-name { font-weight: 700; cursor: pointer; color: #22c55e; }
.cust-name:hover { text-decoration: underline; }
.owed-amt { color: #fbbf24; font-weight: 700; }
.charge-amt { color: #f87171; font-weight: 700; }
.pay-amt { color: #22c55e; font-weight: 700; }
.note-cell { color: #94a3b8; max-width: 200px; overflow: hidden; text-overflow: ellipsis; }

.status-badge, .type-badge {
  padding: 3px 10px; border-radius: 999px; font-size: 11px; font-weight: 700;
}
.status-badge.owed, .type-badge.charge { background: rgba(251,191,36,0.15); color: #fbbf24; }
.status-badge.clear { background: rgba(34,197,94,0.15); color: #6ee7b7; }
.type-badge.payment { background: rgba(34,197,94,0.15); color: #6ee7b7; }

/* Detail header */
.detail-header {
  display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
}
.back-btn {
  padding: 7px 14px; border: 1px solid rgba(255,255,255,0.12); border-radius: 8px;
  background: rgba(255,255,255,0.06); color: #cbd5e1; cursor: pointer; font-size: 13px;
}
.detail-title h2 { margin: 0; }
.detail-title p { margin: 2px 0 0; color: #94a3b8; font-size: 12px; }

.balance-badge {
  padding: 6px 14px; border-radius: 999px; font-size: 13px; font-weight: 700;
}
.balance-badge.owed { background: rgba(251,191,36,0.15); color: #fbbf24; border: 1px solid rgba(251,191,36,0.3); }
.balance-badge.clear { background: rgba(34,197,94,0.12); color: #6ee7b7; border: 1px solid rgba(34,197,94,0.3); }

.pay-btn {
  margin-left: auto; padding: 7px 16px; border: none; border-radius: 10px;
  background: linear-gradient(135deg, #d97706, #fbbf24);
  color: white; font-weight: 700; cursor: pointer; font-size: 13px;
}
.pay-btn:disabled { opacity: 0.4; cursor: not-allowed; }

.del-btn {
  padding: 7px 14px; border-radius: 10px; cursor: pointer; font-size: 13px; font-weight: 700;
  background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.3); color: #f87171;
}

/* Payment bar */
.payment-bar {
  display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
  background: rgba(251,191,36,0.07); border: 1px solid rgba(251,191,36,0.25);
  border-radius: 12px; padding: 10px 16px;
}
.bar-label { font-size: 13px; color: #fbbf24; white-space: nowrap; }
.bar-label strong { color: white; }
.bar-error { color: #fca5a5; font-size: 12px; }
.note-input { width: 180px; }

.confirm-btn {
  padding: 7px 16px; border: none; border-radius: 8px;
  background: linear-gradient(135deg, #059669, #34d399);
  color: white; font-weight: 700; cursor: pointer; font-size: 12px;
}
.cancel-btn {
  padding: 7px 14px; border-radius: 8px; cursor: pointer; font-size: 12px; font-weight: 700;
  background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.12); color: #cbd5e1;
}

.customer-notes {
  margin: 0; padding: 10px 14px; border-radius: 10px;
  background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08);
  color: #94a3b8; font-size: 13px;
}

/* Action buttons */
.view-btn {
  padding: 5px 12px; border-radius: 8px; margin-right: 6px;
  background: rgba(99,102,241,0.15); border: 1px solid rgba(99,102,241,0.35);
  color: #a5b4fc; font-weight: 700; cursor: pointer; font-size: 12px;
}
.del-btn-sm {
  padding: 5px 12px; border-radius: 8px;
  background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.3);
  color: #f87171; font-weight: 700; cursor: pointer; font-size: 12px;
}

.empty { color: #94a3b8; text-align: center; padding: 40px; font-size: 14px; }
</style>
