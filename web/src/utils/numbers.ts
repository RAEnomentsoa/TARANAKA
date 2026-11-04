import { INTL_LOCALE } from './dates'

/** DRF sends decimals as strings ("12.40"): read them safely. */
export function toNumber(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null
  const n = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

export function formatNumber(value: number, digits = 1): string {
  return new Intl.NumberFormat(INTL_LOCALE, {
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  }).format(value)
}
