import { INTL_LOCALE } from './dates'

/**
 * DRF sends decimals as strings ("12.40"): read them safely.
 * @param {string | number | null | undefined} value
 * @returns {number | null}
 */
export function toNumber(value) {
  if (value === null || value === undefined || value === '') return null
  const n = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

/**
 * @param {number} value
 * @param {*} [digits=1]
 * @returns {string}
 */
export function formatNumber(value, digits = 1) {
  return new Intl.NumberFormat(INTL_LOCALE, {
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  }).format(value)
}
