<script setup lang="ts">
import { computed, ref } from 'vue'
import { fmt } from '../composables/useSettings'
import type { ExpiryBatch, Product } from '../types'
import { stockDisplay, inventoryValue } from '../types'
import { effectiveLowStockThreshold, getNearestExpiry, isLowStock } from '../lib/stockHealth'

const props = defineProps<{
  products: Product[]
  expiryBatches: ExpiryBatch[]
  currency: string
  lowStockThreshold: number
  expiryWarningDays: number
  perProductThresholdsEnabled: boolean
}>()

const emit = defineEmits<{
  'edit-product': [product: Product]
  'delete-product': [id: string]
}>()

const search = ref('')
const categoryFilter = ref('All')

const categories = computed(() => ['All', ...new Set(props.products.map(p => p.category).filter(Boolean))])

const filteredProducts = computed(() =>
  props.products.filter(p => {
    const matchSearch = p.name.toLowerCase().includes(search.value.toLowerCase())
    const matchCat = categoryFilter.value === 'All' || p.category === categoryFilter.value
    return matchSearch && matchCat
  })
)

function thresholdFor(product: Product) {
  return effectiveLowStockThreshold(product, props.lowStockThreshold, props.perProductThresholdsEnabled)
}

function expiryFor(product: Product) {
  return getNearestExpiry(product, props.expiryBatches, props.expiryWarningDays)
}
</script>

<template>
  <section class="list-panel">
    <div class="list-header">
      <div>
        <h2>Product List</h2>
        <p>View, update, and delete your store products.</p>
      </div>
      <input v-model="search" type="text" placeholder="Search product..." />
    </div>

    <div class="category-tabs">
      <button
        v-for="cat in categories" :key="cat"
        :class="{ active: categoryFilter === cat }"
        @click="categoryFilter = cat"
      >{{ cat }}</button>
    </div>

    <div class="table-wrapper">
      <table v-if="filteredProducts.length">
        <thead>
          <tr>
            <th>Product</th>
            <th>Category</th>
            <th>Cost Price</th>
            <th>Pack Price</th>
            <th>Per-Piece Price</th>
            <th>Stock</th>
            <th>Total Value</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>

        <tbody>
          <tr v-for="product in filteredProducts" :key="product.id">
            <td class="product-name">
              {{ product.name }}
              <span v-if="isLowStock(product, lowStockThreshold, perProductThresholdsEnabled)" class="mini-badge low">Low</span>
              <span v-if="expiryFor(product)?.expired" class="mini-badge out">Expired</span>
              <span v-else-if="expiryFor(product)?.expiringSoon" class="mini-badge expiring">Expiry</span>
              <span v-else-if="product.hasExpiry && !expiryFor(product)" class="mini-badge missing">Add date</span>
            </td>
            <td><span class="cat-badge">{{ product.category || '-' }}</span></td>
            <td class="cost-price">{{ currency }}{{ fmt(product.costPrice) }}</td>
            <td>{{ currency }}{{ fmt(product.price) }}</td>
            <td>
              <span v-if="product.isPerPieceEnabled" class="per-piece-price">
                {{ currency }}{{ fmt(product.perPiecePrice) }}/pc
              </span>
              <span v-else class="muted">—</span>
            </td>
            <td>{{ stockDisplay(product) }}</td>
            <td>{{ currency }}{{ fmt(inventoryValue(product)) }}</td>
            <td>
              <span :class="product.quantity === 0 ? 'out' : isLowStock(product, lowStockThreshold, perProductThresholdsEnabled) ? 'low' : 'good'">
                {{ product.quantity === 0 ? 'Out of Stock' : isLowStock(product, lowStockThreshold, perProductThresholdsEnabled) ? `Low Stock <= ${thresholdFor(product)}` : 'Available' }}
              </span>
            </td>
            <td>
              <button class="edit-btn" @click="emit('edit-product', product)">Edit</button>
              <button class="delete-btn" @click="emit('delete-product', product.id)">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>

      <div v-else class="empty">
        <h3>No products found</h3>
        <p>Add your first product using the form.</p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.list-panel {
  background: rgba(15, 23, 42, 0.86);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px;
  padding: 16px;
  box-shadow: 0 22px 65px rgba(0,0,0,0.38);
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.list-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
}

.list-header h2 {
  margin: 0;
  font-size: 18px;
}

.list-header p {
  margin: 2px 0 0;
  color: #94a3b8;
  font-size: 12px;
}

.list-header input {
  width: 200px;
  padding: 8px 12px;
  border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1);
  background: #111827;
  color: white;
  outline: none;
  font-size: 13px;
}

.category-tabs {
  display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px;
}
.category-tabs button {
  padding: 4px 12px; border-radius: 999px; font-size: 12px; font-weight: 600;
  border: 1px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.05);
  color: #94a3b8; cursor: pointer; margin-right: 0;
}
.category-tabs button.active {
  background: rgba(34,197,94,0.18); border-color: rgba(34,197,94,0.4); color: #22c55e;
}

.cat-badge {
  padding: 3px 8px; border-radius: 6px; font-size: 11px; font-weight: 600;
  background: rgba(99,102,241,0.15); color: #a5b4fc;
}

.table-wrapper {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: auto;
  scroll-behavior: smooth;
  scrollbar-color: rgba(148, 163, 184, 0.48) transparent;
  scrollbar-width: thin;
  padding-right: 4px;
}

.table-wrapper::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}

.table-wrapper::-webkit-scrollbar-track {
  background: transparent;
  border-radius: 999px;
}

.table-wrapper::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, rgba(45, 212, 191, 0.7), rgba(34, 197, 94, 0.7));
  border-radius: 999px;
  min-height: 44px;
}

.table-wrapper::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(180deg, rgba(94, 234, 212, 0.95), rgba(74, 222, 128, 0.95));
}

table {
  width: 100%;
  min-width: 700px;
  border-collapse: collapse;
}

th {
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(15, 23, 42, 0.98);
  padding: 10px 12px;
  text-align: left;
  color: #6ee7b7;
  font-size: 12px;
  text-transform: uppercase;
}

td {
  padding: 10px 12px;
  color: #e5e7eb;
  font-size: 13px;
  white-space: nowrap;
}

tbody tr {
  background: rgba(255,255,255,0.035);
}

tbody tr:nth-child(even) {
  background: rgba(255,255,255,0.065);
}

tbody tr:hover {
  background: rgba(34,197,94,0.12);
}

.product-name {
  font-weight: 800;
}

.mini-badge {
  display: inline-block;
  margin-left: 6px;
  padding: 2px 7px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 800;
  vertical-align: middle;
}

.mini-badge.low,
.mini-badge.expiring {
  background: rgba(245,158,11,0.18);
  color: #fbbf24;
  border: 1px solid rgba(245,158,11,0.34);
}

.mini-badge.out {
  background: rgba(239,68,68,0.18);
  color: #fca5a5;
  border: 1px solid rgba(239,68,68,0.34);
}

.mini-badge.missing {
  background: rgba(148,163,184,0.12);
  color: #cbd5e1;
  border: 1px solid rgba(148,163,184,0.22);
}

.cost-price {
  color: #f87171;
  font-weight: 600;
}

.per-piece-price {
  color: #a5b4fc;
  font-weight: 600;
}

.muted { color: #475569; }

.good,
.low,
.out {
  padding: 7px 12px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 800;
}

.good {
  background: rgba(34,197,94,0.18);
  color: #6ee7b7;
}

.low {
  background: rgba(245,158,11,0.2);
  color: #fbbf24;
}

.out {
  background: rgba(239,68,68,0.18);
  color: #fca5a5;
}

button {
  border: none;
  padding: 6px 10px;
  border-radius: 8px;
  color: white;
  font-weight: 800;
  cursor: pointer;
  margin-right: 6px;
  font-size: 12px;
}

.edit-btn {
  background: rgba(34,197,94,0.12);
  border: 1px solid rgba(34,197,94,0.35);
  color: #22c55e;
}

.edit-btn:hover {
  background: rgba(34,197,94,0.22);
}

.delete-btn {
  background: rgba(245,158,11,0.12);
  border: 1px solid rgba(245,158,11,0.35);
  color: #f59e0b;
}

.delete-btn:hover {
  background: rgba(245,158,11,0.22);
}

.empty {
  text-align: center;
  padding: 70px 20px;
  color: #94a3b8;
}

.empty h3 {
  color: white;
}

@media (max-width: 700px) {
  .list-panel {
    border-radius: 12px;
    padding: 14px;
    height: auto;
    min-height: 420px;
  }

  .list-header {
    flex-direction: column;
    align-items: stretch;
  }

  .list-header input {
    width: 100%;
    min-height: 42px;
    font-size: 14px;
  }

  .category-tabs {
    flex-wrap: nowrap;
    overflow-x: auto;
    padding-bottom: 4px;
    scrollbar-width: none;
  }

  .category-tabs::-webkit-scrollbar {
    display: none;
  }

  .category-tabs button {
    flex: 0 0 auto;
  }

  .table-wrapper {
    max-height: none;
    padding-right: 0;
  }

  table {
    min-width: 760px;
  }

  th,
  td {
    padding: 9px 10px;
  }
}
</style>
