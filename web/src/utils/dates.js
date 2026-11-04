/** Date helpers. Ages are always computed from the birth date, never typed. */

const DAY_MS = 86_400_000
const DAYS_PER_MONTH = 30.4375 // same constant as nutrition/services.py

/**
 * @param {string} value
 * @returns {Date}
 */
export function parseIsoDate(value) {
  const [y, m, d] = value.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(y ?? 1970, (m ?? 1) - 1, d ?? 1))
}

/**
 * @param {Date} date
 * @returns {string}
 */
export function toIsoDate(date) {
  return date.toISOString().slice(0, 10)
}

/**
 * @param {Date} [now=new Date()]
 * @returns {string}
 */
export function todayIso(now = new Date()) {
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000)
  return toIsoDate(local)
}

/**
 * @param {string} iso
 * @param {number} days
 * @returns {string}
 */
export function addDays(iso, days) {
  return toIsoDate(new Date(parseIsoDate(iso).getTime() + days * DAY_MS))
}

/**
 * @param {string} birth
 * @param {string} on
 * @returns {number}
 */
export function ageInDays(birth, on) {
  return Math.floor((parseIsoDate(on).getTime() - parseIsoDate(birth).getTime()) / DAY_MS)
}

/**
 * @param {string} birth
 * @param {string} on
 * @returns {number}
 */
export function ageInMonths(birth, on) {
  return Math.floor(ageInDays(birth, on) / DAYS_PER_MONTH)
}

/** @typedef {'minutes' | 'hours' | 'days'} DurationUnit */

/**
 * How long something has been waiting, rounded to a readable unit.
 * @param {string} fromIso
 * @param {Date} [now=new Date()]
 * @returns {{ unit: DurationUnit, value: number }}
 */
export function elapsed(fromIso, now = new Date()) {
  const minutes = Math.max(0, Math.floor((now.getTime() - Date.parse(fromIso)) / 60_000))
  if (minutes < 60) return { unit: 'minutes', value: minutes }
  const hours = Math.floor(minutes / 60)
  if (hours < 48) return { unit: 'hours', value: hours }
  return { unit: 'days', value: Math.floor(hours / 24) }
}

/**
 * Browsers ship no Malagasy calendar data, and Madagascar writes dates as
 * dd/mm/yyyy in both languages: the numeric French format serves both.
 */
export const INTL_LOCALE = 'fr-FR'

/**
 * @param {string} iso
 * @returns {string}
 */
export function formatDate(iso) {
  const date = iso.length > 10 ? new Date(iso) : parseIsoDate(iso)
  return new Intl.DateTimeFormat(INTL_LOCALE, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: iso.length > 10 ? undefined : 'UTC',
  }).format(date)
}

/**
 * @param {string} iso
 * @returns {string}
 */
export function formatDateTime(iso) {
  return new Intl.DateTimeFormat(INTL_LOCALE, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
}
