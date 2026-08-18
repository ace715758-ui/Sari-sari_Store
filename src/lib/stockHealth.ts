import type { ExpiryBatch, Product } from '../types'

export type ExpiryStatus = {
  product: Product
  batch?: ExpiryBatch
  expiryDate: string
  daysRemaining: number
  expired: boolean
  expiringSoon: boolean
  label: string
  quantity: number
}

export function effectiveLowStockThreshold(
  product: Product,
  globalThreshold: number,
  perProductEnabled = true,
) {
  const custom = product.lowStockThreshold
  if (!perProductEnabled || custom === null || custom === undefined || Number.isNaN(custom)) {
    return globalThreshold
  }
  return custom
}

export function isLowStock(
  product: Product,
  globalThreshold: number,
  perProductEnabled = true,
) {
  return product.quantity > 0
    && product.quantity <= effectiveLowStockThreshold(product, globalThreshold, perProductEnabled)
}

export function isOutOfStock(product: Product) {
  return product.quantity === 0
}

export function daysUntilDate(date: string) {
  const target = new Date(`${date}T00:00:00`)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return Math.ceil((target.getTime() - today.getTime()) / 86400000)
}

export function expiryLabel(daysRemaining: number) {
  if (daysRemaining < 0) return `Expired ${Math.abs(daysRemaining)} day${Math.abs(daysRemaining) === 1 ? '' : 's'} ago`
  if (daysRemaining === 0) return 'Expires today'
  return `Expires in ${daysRemaining} day${daysRemaining === 1 ? '' : 's'}`
}

export function getExpiryStatuses(
  products: Product[],
  batches: ExpiryBatch[],
  warningDays: number,
) {
  const statuses: ExpiryStatus[] = []

  products.filter(p => p.hasExpiry).forEach(product => {
    if (product.expiryTrackingMode === 'batch') {
      batches
        .filter(batch => batch.productId === product.id && batch.expiryDate && batch.quantity > 0)
        .forEach(batch => {
          const daysRemaining = daysUntilDate(batch.expiryDate)
          statuses.push({
            product,
            batch,
            expiryDate: batch.expiryDate,
            daysRemaining,
            expired: daysRemaining < 0,
            expiringSoon: daysRemaining >= 0 && daysRemaining <= warningDays,
            label: expiryLabel(daysRemaining),
            quantity: batch.quantity,
          })
        })
      return
    }

    if (!product.expiryDate) return
    const daysRemaining = daysUntilDate(product.expiryDate)
    statuses.push({
      product,
      expiryDate: product.expiryDate,
      daysRemaining,
      expired: daysRemaining < 0,
      expiringSoon: daysRemaining >= 0 && daysRemaining <= warningDays,
      label: expiryLabel(daysRemaining),
      quantity: product.quantity,
    })
  })

  return statuses.sort((a, b) => a.daysRemaining - b.daysRemaining)
}

export function getNearestExpiry(
  product: Product,
  batches: ExpiryBatch[],
  warningDays: number,
) {
  return getExpiryStatuses([product], batches, warningDays)[0] ?? null
}
