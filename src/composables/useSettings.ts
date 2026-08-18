import { ref, watch } from 'vue'

export const storeName = ref(localStorage.getItem('storeName') || 'SariSari Store')
export const ownerName = ref(localStorage.getItem('ownerName') || 'Ace Magbanua')
export const currency = ref(localStorage.getItem('currency') || '₱')
export const lowStockThreshold = ref(Number(localStorage.getItem('lowStockThreshold') || 5))
export const expiryWarningDays = ref(Number(localStorage.getItem('expiryWarningDays') || 7))
export const perProductThresholdsEnabled = ref(localStorage.getItem('perProductThresholdsEnabled') !== 'false')
export const darkMode = ref(localStorage.getItem('darkMode') !== 'false')

watch(storeName, v => localStorage.setItem('storeName', v))
watch(ownerName, v => localStorage.setItem('ownerName', v))
watch(currency, v => localStorage.setItem('currency', v))
watch(lowStockThreshold, v => localStorage.setItem('lowStockThreshold', String(v)))
watch(expiryWarningDays, v => localStorage.setItem('expiryWarningDays', String(v)))
watch(perProductThresholdsEnabled, v => localStorage.setItem('perProductThresholdsEnabled', String(v)))
watch(darkMode, v => localStorage.setItem('darkMode', String(v)))

export function fmt(amount: number): string {
  return amount.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
