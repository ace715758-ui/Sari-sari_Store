<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import type { Session } from '@supabase/supabase-js'
import ProductForm from './components/ProductForm.vue'
import ProductList from './components/ProductList.vue'
import AuthView from './components/AuthView.vue'
import InventoryView from './components/views/InventoryView.vue'
import SalesView from './components/views/SalesView.vue'
import ReportsView from './components/views/ReportsView.vue'
import SettingsView from './components/views/SettingsView.vue'
import CustomersView from './components/views/CustomersView.vue'
import CloseDayView from './components/views/CloseDayView.vue'
import { storeName, ownerName, currency, lowStockThreshold, expiryWarningDays, perProductThresholdsEnabled, darkMode, fmt } from './composables/useSettings'
import { isSupabaseConfigured, supabase } from './lib/supabase'
import { getExpiryStatuses, isLowStock } from './lib/stockHealth'
import type { Product, ExpiryBatch, SaleItem, Customer, CreditTransaction, DailyClosing, CashPayout } from './types'
import { inventoryValue, capitalValue } from './types'

const activeView = ref<'dashboard' | 'products' | 'inventory' | 'sales' | 'customers' | 'closeday' | 'reports' | 'settings'>('dashboard')

const products = ref<Product[]>([])
const expiryBatches = ref<ExpiryBatch[]>([])
const sales = ref<SaleItem[]>([])
const customers = ref<Customer[]>([])
const creditTransactions = ref<CreditTransaction[]>([])
const closings = ref<DailyClosing[]>([])
const session = ref<Session | null>(null)
const loading = ref(true)
const dataError = ref('')
const authNotice = ref('')
const syncingSettings = ref(false)

const editingProduct = ref<Product | null>(null)
const inventoryFilter = ref<'all' | 'low' | 'expiring'>('all')

const totalValue = computed(() =>
  products.value.reduce((sum, p) => sum + inventoryValue(p), 0)
)

const totalRevenue = computed(() =>
  sales.value.reduce((sum, s) => sum + s.total, 0)
)

const totalProfit = computed(() =>
  sales.value.reduce((sum, s) => sum + (s.total - (s.cost ?? 0)), 0)
)

const totalExpenses = computed(() =>
  products.value.reduce((sum, p) => sum + capitalValue(p), 0)
)

const totalCredit = computed(() =>
  customers.value.reduce((sum, c) => sum + c.currentBalance, 0)
)

const todayRevenue = computed(() =>
  sales.value.filter(s => isSameDay(s.date, new Date())).reduce((sum, s) => sum + s.total, 0)
)

const lowStockItems = computed(() =>
  products.value.filter(p => isLowStock(p, lowStockThreshold.value, perProductThresholdsEnabled.value))
)

const expiryAlerts = computed(() =>
  getExpiryStatuses(products.value, expiryBatches.value, expiryWarningDays.value)
    .filter(status => status.expired || status.expiringSoon)
)

const expiringSoonCount = computed(() => expiryAlerts.value.filter(status => status.expiringSoon).length)
const expiredCount = computed(() => expiryAlerts.value.filter(status => status.expired).length)

function isSameDay(date: string, target: Date) {
  const value = new Date(date)
  return value.getFullYear() === target.getFullYear()
    && value.getMonth() === target.getMonth()
    && value.getDate() === target.getDate()
}

function mapProduct(row: any): Product {
  return {
    id: row.id,
    name: row.name ?? '',
    category: row.category ?? '',
    price: Number(row.price ?? 0),
    costPrice: Number(row.cost_price ?? 0),
    quantity: Number(row.quantity ?? 0),
    piecesPerPack: Number(row.pieces_per_pack ?? 1) || 1,
    perPiecePrice: Number(row.per_piece_price ?? 0),
    isPerPieceEnabled: Boolean(row.per_piece_enabled ?? false),
    lowStockThreshold: row.low_stock_threshold === null || row.low_stock_threshold === undefined ? null : Number(row.low_stock_threshold),
    hasExpiry: Boolean(row.has_expiry ?? false),
    expiryTrackingMode: row.expiry_tracking_mode ?? 'product-level',
    expiryDate: row.expiry_date ?? null,
  }
}

function mapExpiryBatch(row: any): ExpiryBatch {
  return {
    id: row.id,
    productId: row.product_id,
    quantity: Number(row.quantity ?? 0),
    expiryDate: row.expiry_date,
    dateAdded: row.date_added ?? row.created_at ?? new Date().toISOString(),
    notes: row.notes ?? '',
  }
}

function mapSale(row: any): SaleItem {
  return {
    id: row.id,
    productId: row.product_id ?? null,
    product: row.product_name ?? '',
    qty: Number(row.qty ?? 0),
    total: Number(row.total ?? 0),
    cost: Number(row.cost ?? 0),
    date: row.sold_at ?? new Date().toISOString(),
    paymentMethod: row.payment_method ?? 'cash',
    creditCustomerId: row.credit_customer_id ?? null,
    sellMode: row.sell_mode ?? 'pack',
  }
}

function mapCustomer(row: any): Customer {
  return {
    id: row.id,
    name: row.name,
    contactNumber: row.contact_number ?? '',
    notes: row.notes ?? '',
    currentBalance: Number(row.current_balance),
    createdAt: row.created_at,
  }
}

function mapCreditTx(row: any): CreditTransaction {
  return {
    id: row.id,
    customerId: row.customer_id,
    customerName: row.customer_name ?? '',
    type: row.type,
    amount: Number(row.amount),
    relatedSaleId: row.related_sale_id ?? null,
    note: row.note ?? '',
    date: row.created_at,
  }
}

function mapClosing(row: any): DailyClosing {
  return {
    id: row.id,
    date: row.date,
    openingCash: Number(row.opening_cash ?? 0),
    expectedCashSales: Number(row.expected_cash_sales ?? 0),
    expectedCreditSales: Number(row.expected_credit_sales ?? 0),
    cashPayouts: Array.isArray(row.cash_payouts) ? row.cash_payouts : [],
    actualCashCounted: row.actual_cash_counted !== null ? Number(row.actual_cash_counted) : null,
    variance: row.variance !== null ? Number(row.variance) : null,
    status: row.status ?? 'open',
    notes: row.notes ?? '',
    closedAt: row.closed_at ?? null,
    createdAt: row.created_at,
  }
}

async function loadData() {
  if (!supabase || !session.value?.user) return
  loading.value = true
  dataError.value = ''

  const [productsResult, batchesResult, salesResult, settingsResult, customersResult, creditTxResult, closingsResult] = await Promise.all([
    supabase.from('products').select('*').order('created_at', { ascending: false }),
    supabase.from('expiry_batches').select('*').order('expiry_date', { ascending: true }),
    supabase.from('sales').select('*').order('sold_at', { ascending: false }),
    supabase.from('store_settings').select('*').eq('user_id', session.value.user.id).maybeSingle(),
    supabase.from('customers').select('*').order('created_at', { ascending: false }),
    supabase.from('credit_transactions').select('*').order('created_at', { ascending: false }),
    supabase.from('daily_closings').select('*').order('date', { ascending: false }),
  ])

  if (productsResult.error || batchesResult.error || salesResult.error || settingsResult.error || customersResult.error) {
    dataError.value = productsResult.error?.message || batchesResult.error?.message || salesResult.error?.message || settingsResult.error?.message || customersResult.error?.message || 'Unable to load store data.'
    loading.value = false
    return
  }

  products.value = (productsResult.data ?? []).map(mapProduct)
  expiryBatches.value = (batchesResult.data ?? []).map(mapExpiryBatch)
  sales.value = (salesResult.data ?? []).map(mapSale)
  customers.value = (customersResult.data ?? []).map(mapCustomer)
  creditTransactions.value = (creditTxResult.data ?? []).map(mapCreditTx)
  closings.value = (closingsResult.data ?? []).map(mapClosing)

  if (settingsResult.data) {
    syncingSettings.value = true
    storeName.value = settingsResult.data.store_name
    ownerName.value = settingsResult.data.owner_name
    currency.value = settingsResult.data.currency
    lowStockThreshold.value = settingsResult.data.low_stock_threshold
    expiryWarningDays.value = Number(settingsResult.data.expiry_warning_days ?? 7)
    perProductThresholdsEnabled.value = Boolean(settingsResult.data.per_product_thresholds_enabled ?? true)
    darkMode.value = settingsResult.data.dark_mode
    syncingSettings.value = false
  } else {
    await saveSettings()
  }

  loading.value = false
}

async function addProduct(product: Omit<Product, 'id'>) {
  if (!supabase || !session.value?.user) return
  dataError.value = ''
  const { data, error } = await supabase
    .from('products')
    .insert({
      user_id: session.value.user.id,
      name: product.name,
      category: product.category,
      price: product.price,
      cost_price: product.costPrice,
      quantity: product.quantity,
      pieces_per_pack: product.piecesPerPack,
      per_piece_price: product.perPiecePrice,
      per_piece_enabled: product.isPerPieceEnabled,
      low_stock_threshold: product.lowStockThreshold ?? null,
      has_expiry: product.hasExpiry,
      expiry_tracking_mode: product.expiryTrackingMode,
      expiry_date: product.expiryDate ?? null,
    })
    .select()
    .single()

  if (error) {
    dataError.value = error.message
    return
  }
  products.value.unshift(mapProduct(data))
}

async function sellProduct(productId: string, qty: number, paymentMethod: 'cash' | 'credit' = 'cash', creditCustomerId: string | null = null, newCustomerName: string | null = null, sellMode: 'pack' | 'piece' = 'pack') {
  if (!supabase || !session.value?.user) return
  const index = products.value.findIndex(p => p.id === productId)
  if (index === -1) return
  const product = products.value[index]
  if (!product) return

  dataError.value = ''

  // Convert qty to pieces for stock deduction
  const piecesDeducted = sellMode === 'piece' ? qty : qty * product.piecesPerPack

  // Calculate revenue and cost based on sell mode
  const unitPrice = sellMode === 'piece' ? product.perPiecePrice : product.price
  const unitCost = sellMode === 'piece' ? product.costPrice / product.piecesPerPack : product.costPrice
  const saleTotal = unitPrice * qty
  const saleCost = unitCost * qty

  // If new customer name provided, create the customer first
  let resolvedCustomerId = creditCustomerId
  if (paymentMethod === 'credit' && newCustomerName) {
    const { data: custData, error: custErr } = await supabase.from('customers').insert({
      user_id: session.value.user.id,
      name: newCustomerName,
      contact_number: '',
      notes: '',
      current_balance: 0,
    }).select().single()
    if (custErr) { dataError.value = custErr.message; return }
    const newCust = mapCustomer(custData)
    customers.value.unshift(newCust)
    resolvedCustomerId = newCust.id
  }

  const nextQuantity = Math.max(0, product.quantity - piecesDeducted)
  const soldAt = new Date().toISOString()

  const [productResult, saleResult] = await Promise.all([
    supabase.from('products').update({ quantity: nextQuantity }).eq('id', productId).select().single(),
    supabase.from('sales').insert({
      user_id: session.value.user.id,
      product_id: product.id,
      product_name: product.name,
      qty,
      total: saleTotal,
      cost: saleCost,
      sold_at: soldAt,
      payment_method: paymentMethod,
      credit_customer_id: resolvedCustomerId,
      sell_mode: sellMode,
    }).select().single(),
  ])

  if (productResult.error || saleResult.error) {
    dataError.value = productResult.error?.message || saleResult.error?.message || 'Unable to record sale.'
    return
  }

  products.value[index] = mapProduct(productResult.data)
  const newSale = mapSale(saleResult.data)
  sales.value.unshift(newSale)

  if (product.hasExpiry && product.expiryTrackingMode === 'batch') {
    await deductExpiryBatches(product.id, piecesDeducted)
  }

  // If credit sale, create transaction and update customer balance
  if (paymentMethod === 'credit' && resolvedCustomerId) {
    const custIndex = customers.value.findIndex(c => c.id === resolvedCustomerId)
    if (custIndex !== -1) {
      const cust = customers.value[custIndex]!
      const newBalance = cust.currentBalance + saleTotal

      const [txResult, custResult] = await Promise.all([
        supabase.from('credit_transactions').insert({
          user_id: session.value!.user!.id,
          customer_id: resolvedCustomerId,
          type: 'charge',
          amount: saleTotal,
          related_sale_id: newSale.id,
          note: `Sale: ${product.name} x${qty} (${sellMode})`,
        }).select().single(),
        supabase.from('customers').update({ current_balance: newBalance }).eq('id', resolvedCustomerId).select().single(),
      ])

      if (!txResult.error && txResult.data) creditTransactions.value.unshift(mapCreditTx(txResult.data))
      if (!custResult.error && custResult.data) customers.value[custIndex] = mapCustomer(custResult.data)
    }
  }
}

async function deductExpiryBatches(productId: string, piecesDeducted: number) {
  if (!supabase) return
  let remaining = piecesDeducted
  const batches = expiryBatches.value
    .filter(batch => batch.productId === productId && batch.quantity > 0)
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate))

  for (const batch of batches) {
    if (remaining <= 0) break
    const nextQuantity = Math.max(0, batch.quantity - remaining)
    remaining -= batch.quantity - nextQuantity

    const { data, error } = await supabase
      .from('expiry_batches')
      .update({ quantity: nextQuantity })
      .eq('id', batch.id)
      .select()
      .single()

    if (error) {
      dataError.value = error.message
      return
    }

    const batchIndex = expiryBatches.value.findIndex(item => item.id === batch.id)
    if (batchIndex !== -1) expiryBatches.value[batchIndex] = mapExpiryBatch(data)
  }
}

function editProduct(product: Product) {
  editingProduct.value = { ...product }
}

function openInventory(filter: 'all' | 'low' | 'expiring' = 'all') {
  inventoryFilter.value = filter
  activeView.value = 'inventory'
}

const todayStr = new Date().toISOString().slice(0, 10)
const yesterdayStr = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
const todayClosing = computed(() => closings.value.find(c => c.date === todayStr) ?? null)
const yesterdayClosing = computed(() => closings.value.find(c => c.date === yesterdayStr && c.status === 'closed') ?? null)

async function updateProduct(product: Product) {
  if (!supabase) return
  const index = products.value.findIndex(p => p.id === product.id)
  if (index === -1) return

  dataError.value = ''
  const { data, error } = await supabase
    .from('products')
    .update({
      name: product.name,
      category: product.category,
      price: product.price,
      cost_price: product.costPrice,
      quantity: product.quantity,
      pieces_per_pack: product.piecesPerPack,
      per_piece_price: product.perPiecePrice,
      per_piece_enabled: product.isPerPieceEnabled,
      low_stock_threshold: product.lowStockThreshold ?? null,
      has_expiry: product.hasExpiry,
      expiry_tracking_mode: product.expiryTrackingMode,
      expiry_date: product.expiryDate ?? null,
    })
    .eq('id', product.id)
    .select()
    .single()

  if (error) {
    dataError.value = error.message
    return
  }

  products.value[index] = mapProduct(data)
  editingProduct.value = null
}

async function deleteProduct(id: string) {
  if (!supabase) return
  if (confirm('Delete this product?')) {
    const { error } = await supabase.from('products').delete().eq('id', id)
    if (error) {
      dataError.value = error.message
      return
    }
    products.value = products.value.filter(p => p.id !== id)
  }
}

async function restockProduct(productId: string, qty: number, unit: 'pack' | 'piece' = 'pack', expiryDate: string | null = null, notes = '') {
  if (!supabase || !session.value?.user) return
  const index = products.value.findIndex(p => p.id === productId)
  if (index === -1) return
  const product = products.value[index]
  if (!product) return

  // Convert to pieces
  const piecesToAdd = unit === 'piece' ? qty : qty * product.piecesPerPack
  const updates: Record<string, unknown> = { quantity: product.quantity + piecesToAdd }
  if (product.hasExpiry && product.expiryTrackingMode === 'product-level' && expiryDate) {
    updates.expiry_date = expiryDate
  }

  const { data, error } = await supabase
    .from('products')
    .update(updates)
    .eq('id', productId)
    .select()
    .single()

  if (error) { dataError.value = error.message; return }
  products.value[index] = mapProduct(data)

  if (product.hasExpiry && product.expiryTrackingMode === 'batch' && expiryDate) {
    const { data: batch, error: batchError } = await supabase
      .from('expiry_batches')
      .insert({
        user_id: session.value.user.id,
        product_id: productId,
        quantity: piecesToAdd,
        expiry_date: expiryDate,
        notes,
      })
      .select()
      .single()

    if (batchError) { dataError.value = batchError.message; return }
    expiryBatches.value.push(mapExpiryBatch(batch))
    expiryBatches.value.sort((a, b) => a.expiryDate.localeCompare(b.expiryDate))
  }
}

async function breakPack(productId: string) {
  // Breaking a pack doesn't change total piece count — stock is already in pieces.
  // This is a display-only action; nothing to update in the DB.
  // We just confirm to the user. Stock already stored in pieces so it's already "broken".
  alert('Pack broken — stock is already tracked in pieces. You can now sell individual pieces.')
}

async function recordPayment(customerId: string, amount: number, note: string) {
  if (!supabase || !session.value?.user) return
  const custIndex = customers.value.findIndex(c => c.id === customerId)
  if (custIndex === -1) return
  const cust = customers.value[custIndex]!
  const newBalance = Math.max(0, cust.currentBalance - amount)

  const [txResult, custResult] = await Promise.all([
    supabase.from('credit_transactions').insert({
      user_id: session.value.user.id,
      customer_id: customerId,
      type: 'payment',
      amount,
      note,
    }).select().single(),
    supabase.from('customers').update({ current_balance: newBalance }).eq('id', customerId).select().single(),
  ])

  if (txResult.error || custResult.error) {
    dataError.value = txResult.error?.message || custResult.error?.message || 'Unable to record payment.'
    return
  }
  if (txResult.data) creditTransactions.value.unshift(mapCreditTx(txResult.data))
  if (custResult.data) customers.value[custIndex] = mapCustomer(custResult.data)
}

async function deleteCustomer(id: string) {
  if (!supabase) return
  const { error } = await supabase.from('customers').delete().eq('id', id)
  if (error) { dataError.value = error.message; return }
  customers.value = customers.value.filter(c => c.id !== id)
  creditTransactions.value = creditTransactions.value.filter(t => t.customerId !== id)
}

async function saveClosing(data: {
  date: string
  openingCash: number
  expectedCashSales: number
  expectedCreditSales: number
  cashPayouts: CashPayout[]
  actualCashCounted: number
  variance: number
  notes: string
  status: 'open' | 'closed'
}) {
  if (!supabase || !session.value?.user) return
  dataError.value = ''

  const payload = {
    user_id: session.value.user.id,
    date: data.date,
    opening_cash: data.openingCash,
    expected_cash_sales: data.expectedCashSales,
    expected_credit_sales: data.expectedCreditSales,
    cash_payouts: data.cashPayouts,
    actual_cash_counted: data.actualCashCounted,
    variance: data.variance,
    notes: data.notes,
    status: data.status,
    closed_at: data.status === 'closed' ? new Date().toISOString() : null,
  }

  const { data: row, error } = await supabase
    .from('daily_closings')
    .upsert(payload, { onConflict: 'user_id,date' })
    .select()
    .single()

  if (error) { dataError.value = error.message; return }

  const mapped = mapClosing(row)
  const idx = closings.value.findIndex(c => c.date === data.date)
  if (idx !== -1) closings.value[idx] = mapped
  else closings.value.unshift(mapped)
}

async function reopenClosing(id: string) {
  if (!supabase) return
  if (!confirm('Reopen this day? This will allow editing the closing record.')) return
  const { data: row, error } = await supabase
    .from('daily_closings')
    .update({ status: 'open', closed_at: null })
    .eq('id', id)
    .select()
    .single()
  if (error) { dataError.value = error.message; return }
  const idx = closings.value.findIndex(c => c.id === id)
  if (idx !== -1) closings.value[idx] = mapClosing(row)
}

function cancelEdit() {
  editingProduct.value = null
}

let settingsTimer: ReturnType<typeof setTimeout> | undefined
async function saveSettings() {
  if (!supabase || !session.value?.user) return
  const { error } = await supabase.from('store_settings').upsert({
    user_id: session.value.user.id,
    store_name: storeName.value,
    owner_name: ownerName.value,
    currency: currency.value,
    low_stock_threshold: lowStockThreshold.value,
    expiry_warning_days: expiryWarningDays.value,
    per_product_thresholds_enabled: perProductThresholdsEnabled.value,
    dark_mode: darkMode.value,
    updated_at: new Date().toISOString(),
  })
  if (error) dataError.value = error.message
}

watch([storeName, ownerName, currency, lowStockThreshold, expiryWarningDays, perProductThresholdsEnabled, darkMode], () => {
  if (syncingSettings.value || !session.value) return
  clearTimeout(settingsTimer)
  settingsTimer = setTimeout(saveSettings, 500)
})

async function signOut() {
  await supabase?.auth.signOut()
}

onMounted(async () => {
  if (!supabase) {
    loading.value = false
    return
  }

  const url = new URL(window.location.href)
  const hasAuthCallback = url.searchParams.has('code')
    || url.searchParams.has('token_hash')
    || window.location.hash.includes('access_token')

  if (hasAuthCallback) {
    authNotice.value = 'Account confirmed. Redirecting to your dashboard...'
  }

  const { data } = await supabase.auth.getSession()
  session.value = data.session
  if (session.value) {
    await loadData()
    if (hasAuthCallback) {
      window.history.replaceState({}, document.title, window.location.pathname)
      setTimeout(() => (authNotice.value = ''), 3500)
    }
  } else {
    loading.value = false
  }

  supabase.auth.onAuthStateChange(async (_event, nextSession) => {
    session.value = nextSession
    if (nextSession) {
      if (authNotice.value) authNotice.value = 'Account confirmed. Opening your dashboard...'
      await loadData()
      if (authNotice.value) setTimeout(() => (authNotice.value = ''), 3500)
    } else {
      products.value = []
      expiryBatches.value = []
      sales.value = []
      loading.value = false
    }
  })
})
</script>

<template>
  <div v-if="!isSupabaseConfigured" class="setup-page">
    <section class="setup-panel">
      <h1>Supabase setup needed</h1>
      <p>Create a Supabase project, run <code>supabase/schema.sql</code>, then add your keys to a local <code>.env</code> file and to your hosting provider.</p>
      <pre>VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...</pre>
    </section>
  </div>

  <AuthView v-else-if="!session && !loading" />

  <div v-else-if="loading" class="loading-page">
    <div class="loader"></div>
    <p>{{ authNotice || 'Loading your store...' }}</p>
  </div>

    <div v-else class="page" :class="{ light: !darkMode }">
    <div v-if="authNotice" class="auth-notice">{{ authNotice }}</div>
    <div class="dashboard">
      <aside class="sidebar">
        <div>
          <h1 class="brand">{{ storeName }}</h1>
          <p class="brand-sub">STORE MANAGEMENT</p>

          <nav>
            <a :class="{ active: activeView === 'dashboard' }" @click="activeView = 'dashboard'">Dashboard</a>
            <a :class="{ active: activeView === 'products' }" @click="activeView = 'products'">Products</a>
            <a :class="{ active: activeView === 'inventory' }" @click="activeView = 'inventory'">Inventory</a>
            <a :class="{ active: activeView === 'sales' }" @click="activeView = 'sales'">Sales</a>
            <a :class="{ active: activeView === 'customers' }" @click="activeView = 'customers'">Customers</a>
            <a :class="{ active: activeView === 'closeday' }" @click="activeView = 'closeday'">Close Day</a>
            <a :class="{ active: activeView === 'reports' }" @click="activeView = 'reports'">Reports</a>
            <a :class="{ active: activeView === 'settings' }" @click="activeView = 'settings'">Settings</a>
          </nav>
        </div>

        <div class="profile">
          <div class="avatar">{{ ownerName.charAt(0).toUpperCase() }}</div>
          <div>
            <strong>{{ ownerName }}</strong>
            <p>Administrator</p>
          </div>
          <button class="sign-out" @click="signOut">Sign out</button>
        </div>
      </aside>

      <main class="main">
        <p v-if="dataError" class="data-error">{{ dataError }}</p>
        <!-- Dashboard -->
        <div v-show="activeView === 'dashboard'" class="view-wrap">
          <section class="hero">
            <div class="hero-top">
              <div>
                <h2>Welcome back, {{ ownerName }}</h2>
                <p>Here's what's happening in your store today.</p>
              </div>
              <div class="system-label">
                <p>Sari-Sari Store Information Management System</p>
              </div>
            </div>
            <div class="hero-stats">
              <div class="hero-card">
                <div class="card-icon">$</div>
                <div>
                  <p>Total Inventory Value</p>
                  <h3>{{ currency }}{{ fmt(totalValue) }}</h3>
                </div>
              </div>
              <div class="hero-card expense">
                <div class="card-icon expense-icon">E</div>
                <div>
                  <p>Total Capital</p>
                  <h3>{{ currency }}{{ fmt(totalExpenses) }}</h3>
                </div>
              </div>
              <div class="hero-card">
                <div class="card-icon">#</div>
                <div>
                  <p>Total Products</p>
                  <h3>{{ products.length }}</h3>
                </div>
              </div>
              <div class="hero-card warn-card" @click="openInventory('low')" style="cursor:pointer">
                <div class="card-icon warn-icon">!</div>
                <div>
                  <p>Low Stock Items</p>
                  <h3>{{ lowStockItems.length }}</h3>
                </div>
              </div>
              <div class="hero-card expiry-card" @click="openInventory('expiring')" style="cursor:pointer">
                <div class="card-icon expiry-icon">D</div>
                <div>
                  <p>Expiring Soon</p>
                  <h3>{{ expiringSoonCount }}<span v-if="expiredCount"> / {{ expiredCount }} expired</span></h3>
                </div>
              </div>
              <div class="hero-card">
                <div class="card-icon">R</div>
                <div>
                  <p>Total Revenue</p>
                  <h3>{{ currency }}{{ fmt(totalRevenue) }}</h3>
                </div>
              </div>
              <div class="hero-card">
                <div class="card-icon">T</div>
                <div>
                  <p>Today's Revenue</p>
                  <h3>{{ currency }}{{ fmt(todayRevenue) }}</h3>
                </div>
              </div>
              <div class="hero-card">
                <div class="card-icon">P</div>
                <div>
                  <p>Total Profit</p>
                  <h3>{{ currency }}{{ fmt(totalProfit) }}</h3>
                </div>
              </div>
              <div
                class="hero-card"
                :class="todayClosing?.status === 'closed' ? 'closed-card' : 'open-card'"
                style="cursor:pointer"
                @click="activeView = 'closeday'"
              >
                <div class="card-icon" :class="todayClosing?.status === 'closed' ? 'closed-icon' : 'open-icon'">
                  {{ todayClosing?.status === 'closed' ? '✓' : '!' }}
                </div>
                <div>
                  <p>Day Status</p>
                  <h3>{{ todayClosing?.status === 'closed' ? 'Closed' : 'Open' }}</h3>
                </div>
              </div>
              <div class="hero-card credit-card" @click="activeView = 'customers'" style="cursor:pointer">
                <div class="card-icon credit-icon">C</div>
                <div>
                  <p>Total Credit</p>
                  <h3>{{ currency }}{{ fmt(totalCredit) }}</h3>
                </div>
              </div>
            </div>
          </section>
          <div v-if="yesterdayClosing && yesterdayClosing.variance !== 0 && yesterdayClosing.variance !== null" class="variance-notice" @click="activeView = 'closeday'">
              Yesterday's variance:
              <strong :class="yesterdayClosing.variance < 0 ? 'red' : 'amber'">
                {{ yesterdayClosing.variance > 0 ? '+' : '' }}{{ currency }}{{ fmt(yesterdayClosing.variance) }}
              </strong>
              — tap to review
            </div>
          <section class="content-grid">
            <ProductList :products="products" :expiry-batches="expiryBatches" :currency="currency" :low-stock-threshold="lowStockThreshold" :expiry-warning-days="expiryWarningDays" :per-product-thresholds-enabled="perProductThresholdsEnabled" @edit-product="editProduct" @delete-product="deleteProduct" />
            <ProductForm :editing-product="editingProduct" :low-stock-threshold="lowStockThreshold" :per-product-thresholds-enabled="perProductThresholdsEnabled" @add-product="addProduct" @update-product="updateProduct" @cancel-edit="cancelEdit" />
          </section>
        </div>

        <!-- Products -->
        <div v-show="activeView === 'products'" class="view-wrap full-height">
          <section class="content-grid full-height">
            <ProductList :products="products" :expiry-batches="expiryBatches" :currency="currency" :low-stock-threshold="lowStockThreshold" :expiry-warning-days="expiryWarningDays" :per-product-thresholds-enabled="perProductThresholdsEnabled" @edit-product="editProduct" @delete-product="deleteProduct" />
            <ProductForm :editing-product="editingProduct" :low-stock-threshold="lowStockThreshold" :per-product-thresholds-enabled="perProductThresholdsEnabled" @add-product="addProduct" @update-product="updateProduct" @cancel-edit="cancelEdit" />
          </section>
        </div>

        <!-- Other views -->
        <InventoryView v-show="activeView === 'inventory'" :products="products" :expiry-batches="expiryBatches" :currency="currency" :low-stock-threshold="lowStockThreshold" :expiry-warning-days="expiryWarningDays" :per-product-thresholds-enabled="perProductThresholdsEnabled" :initial-filter="inventoryFilter" @restock="restockProduct" @break-pack="breakPack" />
        <SalesView v-show="activeView === 'sales'" :products="products" :sales="sales" :customers="customers" :currency="currency" :low-stock-threshold="lowStockThreshold" @sell="(pid, qty, pm, cid, name, mode) => sellProduct(pid, qty, pm, cid, name, mode)" />
        <CustomersView v-show="activeView === 'customers'" :customers="customers" :transactions="creditTransactions" :currency="currency" @record-payment="recordPayment" @delete-customer="deleteCustomer" />
        <CloseDayView v-show="activeView === 'closeday'" :sales="sales" :closings="closings" :currency="currency" @save-closing="saveClosing" @reopen-closing="reopenClosing" />
        <ReportsView v-show="activeView === 'reports'" :products="products" :expiry-batches="expiryBatches" :sales="sales" :customers="customers" :closings="closings" :currency="currency" :low-stock-threshold="lowStockThreshold" :expiry-warning-days="expiryWarningDays" :per-product-thresholds-enabled="perProductThresholdsEnabled" :total-profit="totalProfit" :total-expenses="totalExpenses" :total-credit="totalCredit" />
        <SettingsView v-show="activeView === 'settings'" />
      </main>
    </div>
  </div>
</template>

<style scoped>
.page {
  width: 100vw;
  height: 100vh;
  overflow: auto;
}

.setup-page,
.loading-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 24px;
  background: linear-gradient(135deg, #0f172a, #111827, #020617);
  color: #f8fafc;
}

.setup-panel {
  width: min(620px, 100%);
  background: rgba(15, 23, 42, 0.92);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 24px 70px rgba(0,0,0,0.45);
}

.setup-panel h1 {
  margin: 0 0 10px;
}

.setup-panel p {
  color: #cbd5e1;
  line-height: 1.6;
}

.setup-panel code,
.setup-panel pre {
  color: #6ee7b7;
}

.loader {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(255,255,255,0.16);
  border-top-color: #22c55e;
  border-radius: 50%;
  animation: page-spin 0.7s linear infinite;
}

@keyframes page-spin {
  to { transform: rotate(360deg); }
}

.dashboard {
  width: 100%;
  min-height: 100vh;
  display: grid;
  grid-template-columns: 220px 1fr;
}

.sidebar {
  min-height: 100vh;
  background: rgba(15, 23, 42, 0.88);
  border-right: 1px solid rgba(255,255,255,0.1);
  padding: 18px 14px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.brand {
  margin: 0;
  font-size: 20px;
}

.brand span {
  color: #22c55e;
}

.brand-sub {
  margin: 2px 0 16px;
  color: #94a3b8;
  font-size: 11px;
}

nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

nav a {
  padding: 8px 12px;
  border-radius: 10px;
  color: #cbd5e1;
  cursor: pointer;
  font-size: 13px;
}

nav a:hover,
nav .active {
  background: rgba(34, 197, 94, 0.18);
  color: #22c55e;
}

.profile {
  display: flex;
  align-items: center;
  gap: 10px;
  background: rgba(255,255,255,0.05);
  padding: 10px;
  border-radius: 12px;
}

.sign-out {
  margin-left: auto;
  padding: 6px 8px;
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 8px;
  background: rgba(255,255,255,0.08);
  color: #cbd5e1;
  cursor: pointer;
  font-size: 11px;
  font-weight: 700;
}

.avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: #22c55e;
  display: grid;
  place-items: center;
  font-weight: bold;
  font-size: 13px;
  flex-shrink: 0;
}

.profile strong {
  font-size: 12px;
}

.profile p {
  margin: 2px 0 0;
  color: #22c55e;
  font-size: 11px;
}

.main {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  height: 100vh;
  overflow: hidden;
}

.data-error {
  margin: 0;
  padding: 10px 12px;
  border-radius: 10px;
  color: #fca5a5;
  background: rgba(239,68,68,0.15);
  font-size: 13px;
}

.auth-notice {
  position: fixed;
  top: 18px;
  right: 18px;
  z-index: 200;
  max-width: min(360px, calc(100vw - 36px));
  padding: 12px 14px;
  border-radius: 12px;
  border: 1px solid rgba(34,197,94,0.32);
  background: rgba(15, 23, 42, 0.94);
  color: #6ee7b7;
  box-shadow: 0 16px 42px rgba(0,0,0,0.35);
  font-size: 13px;
  font-weight: 700;
}

.hero {
  border-radius: 18px;
  padding: 18px 24px;
  background:
    linear-gradient(90deg, rgba(7,16,20,0.92), rgba(7,16,20,0.48)),
    url('/img.jpg');
  background-size: cover;
  background-position: center;
  border: 1px solid rgba(255,255,255,0.1);
}

.hero-top {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 12px;
}

.hero h2 {
  margin: 0;
  font-size: 22px;
}

.hero p {
  color: #cbd5e1;
  font-size: 13px;
  margin: 2px 0 0;
}

.system-label {
  text-align: right;
  font-size: 13px;
}

.hero-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 12px;
}

.hero-card {
  background: rgba(15, 23, 42, 0.82);
  backdrop-filter: blur(18px);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 12px;
  padding: 10px 12px;
  display: flex;
  align-items: center;
  gap: 10px;
}

.card-icon {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  background: rgba(34, 197, 94, 0.15);
  border: 1px solid rgba(34, 197, 94, 0.3);
  display: grid;
  place-items: center;
  font-size: 13px;
  font-weight: 700;
  color: #22c55e;
  flex-shrink: 0;
}

.hero-card.expense .card-icon,
.expense-icon {
  background: rgba(239, 68, 68, 0.15);
  border-color: rgba(239, 68, 68, 0.3);
  color: #f87171;
}
.hero-card.expense h3 { color: #f87171; }

.hero-card.closed-card .card-icon,
.closed-icon {
  background: rgba(34,197,94,0.15);
  border-color: rgba(34,197,94,0.3);
  color: #22c55e;
}
.hero-card.closed-card h3 { color: #22c55e; }

.hero-card.open-card .card-icon,
.open-icon {
  background: rgba(251,191,36,0.15);
  border-color: rgba(251,191,36,0.3);
  color: #fbbf24;
}
.hero-card.open-card h3 { color: #fbbf24; }
.hero-card.open-card:hover { border-color: rgba(251,191,36,0.35); }
.hero-card.closed-card:hover { border-color: rgba(34,197,94,0.35); }

.variance-notice {
  padding: 8px 14px; border-radius: 10px; font-size: 13px; cursor: pointer;
  background: rgba(251,191,36,0.08); border: 1px solid rgba(251,191,36,0.25);
  color: #e5e7eb; margin-bottom: -4px;
}
.variance-notice .red { color: #f87171; }
.variance-notice .amber { color: #fbbf24; }

.hero-card.credit-card .card-icon,
.credit-icon {
  background: rgba(251, 191, 36, 0.15);
  border-color: rgba(251, 191, 36, 0.3);
  color: #fbbf24;
}

.hero-card.credit-card h3 {
  color: #fbbf24;
}

.hero-card.warn-card .card-icon,
.warn-icon,
.hero-card.expiry-card .card-icon,
.expiry-icon {
  background: rgba(251, 191, 36, 0.15);
  border-color: rgba(251, 191, 36, 0.3);
  color: #fbbf24;
}

.hero-card.warn-card h3,
.hero-card.expiry-card h3 {
  color: #fbbf24;
}

.hero-card.expiry-card h3 span {
  color: #f87171;
  font-size: 11px;
}

.hero-card.credit-card:hover {
  border-color: rgba(251, 191, 36, 0.4);
}

.hero-card p {
  margin: 0;
  font-size: 11px;
  white-space: nowrap;
}

.hero-card h3 {
  margin: 2px 0 0;
  font-size: 15px;
  color: #22c55e;
}

.content-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 12px;
  align-items: stretch;
  flex: 1;
  min-height: 0;
}

.full-height {
  flex: 1;
  min-height: 0;
}

.view-wrap {
  display: contents;
}

@media (max-width: 1180px) {
  .hero-stats {
    grid-template-columns: repeat(3, 1fr);
  }

  .content-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

@media (max-width: 820px) {
  .page {
    width: 100%;
    min-height: 100vh;
  }

  .dashboard {
    display: block;
  }

  .sidebar {
    position: sticky;
    top: 0;
    z-index: 50;
    min-height: 0;
    padding: 12px;
    border-right: none;
    border-bottom: 1px solid rgba(255,255,255,0.1);
    gap: 10px;
  }

  .brand {
    font-size: 18px;
  }

  .brand-sub {
    margin-bottom: 10px;
  }

  nav {
    flex-direction: row;
    gap: 6px;
    overflow-x: auto;
    padding-bottom: 2px;
    scrollbar-width: none;
  }

  nav::-webkit-scrollbar {
    display: none;
  }

  nav a {
    flex: 0 0 auto;
    padding: 8px 10px;
    white-space: nowrap;
  }

  .profile {
    margin-top: 10px;
  }

  .main {
    height: auto;
    min-height: calc(100vh - 150px);
    overflow: visible;
    padding: 12px;
  }

  .hero {
    padding: 16px;
  }

  .hero-top {
    flex-direction: column;
    gap: 8px;
  }

  .system-label {
    text-align: left;
  }

  .hero-stats {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .hero-card {
    min-width: 0;
  }

  .hero-card p {
    white-space: normal;
  }
}

@media (max-width: 520px) {
  .sidebar {
    padding: 10px;
  }

  .profile {
    align-items: center;
  }

  .profile > div:nth-child(2) {
    min-width: 0;
  }

  .profile strong,
  .profile p {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .sign-out {
    padding: 6px 7px;
  }

  .hero h2 {
    font-size: 19px;
  }

  .hero-stats {
    grid-template-columns: 1fr;
  }

  .content-grid {
    gap: 10px;
  }

  .auth-notice {
    left: 12px;
    right: 12px;
    top: 12px;
  }
}
</style>
