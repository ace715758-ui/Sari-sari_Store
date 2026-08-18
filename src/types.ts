export type Product = {
  id: string
  name: string
  category: string
  price: number        // pack / whole-unit selling price
  costPrice: number    // cost per pack / whole unit
  quantity: number     // stock in pieces (smallest unit)
  piecesPerPack: number  // 1 = not applicable (sold whole only)
  perPiecePrice: number  // price per individual piece
  isPerPieceEnabled: boolean  // whether this product supports per-piece selling
  lowStockThreshold?: number | null
  hasExpiry: boolean
  expiryTrackingMode: 'product-level' | 'batch'
  expiryDate?: string | null
}

export type ExpiryBatch = {
  id: string
  productId: string
  quantity: number
  expiryDate: string
  dateAdded: string
  notes: string
}

/** Derived helpers — not stored, computed from Product */
export function stockDisplay(p: Product): string {
  const ppp = p.piecesPerPack ?? 1
  const qty = p.quantity ?? 0
  if (ppp <= 1) return `${qty} pcs`
  const packs = Math.floor(qty / ppp)
  const loose = qty % ppp
  if (packs === 0) return `${loose} pcs`
  if (loose === 0) return `${packs} pack${packs !== 1 ? 's' : ''}`
  return `${packs} pack${packs !== 1 ? 's' : ''} + ${loose} pcs`
}

/** Number of whole packs currently in stock */
export function packCount(p: Product): number {
  const ppp = p.piecesPerPack ?? 1
  return ppp <= 1 ? p.quantity : Math.floor(p.quantity / ppp)
}

/** Total inventory value: Selling Price × packs in stock */
export function inventoryValue(p: Product): number {
  return p.price * packCount(p)
}

/** Total capital: Cost Price × packs in stock */
export function capitalValue(p: Product): number {
  return p.costPrice * packCount(p)
}

export type SaleItem = {
  id: string
  productId: string | null
  product: string
  qty: number       // in pieces if sellMode='piece', in packs if sellMode='pack'
  total: number
  cost: number
  date: string
  paymentMethod: 'cash' | 'credit'
  creditCustomerId: string | null
  sellMode: 'pack' | 'piece'
}

export type StoreSettings = {
  storeName: string
  ownerName: string
  currency: string
  lowStockThreshold: number
  expiryWarningDays: number
  perProductThresholdsEnabled: boolean
  darkMode: boolean
}

export type Customer = {
  id: string
  name: string
  contactNumber: string
  notes: string
  currentBalance: number
  createdAt: string
}

export type CreditTransaction = {
  id: string
  customerId: string
  customerName: string
  type: 'charge' | 'payment'
  amount: number
  relatedSaleId: string | null
  note: string
  date: string
}

export type CashPayout = {
  amount: number
  note: string
}

export type DailyClosing = {
  id: string
  date: string                // YYYY-MM-DD
  openingCash: number
  expectedCashSales: number
  expectedCreditSales: number
  cashPayouts: CashPayout[]
  actualCashCounted: number | null
  variance: number | null
  status: 'open' | 'closed'
  notes: string
  closedAt: string | null
  createdAt: string
}
