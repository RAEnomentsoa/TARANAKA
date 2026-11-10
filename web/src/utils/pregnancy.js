import { addDays, ageInDays } from './dates'

/** @typedef {import('@/api/types').Pregnancy} Pregnancy */

/** Naegele: 280 days between the last period and the due date. */
export const PREGNANCY_DAYS = 280

/**
 * Best available due date: computed, typed, or projected from an ultrasound.
 * @param {Pregnancy} pregnancy
 * @returns {string | null}
 */
export function dueDate(pregnancy) {
  if (pregnancy.dpa) return pregnancy.dpa
  if (pregnancy.dpa_saisie) return pregnancy.dpa_saisie
  if (pregnancy.terme_confirme_date && pregnancy.terme_confirme_jours !== null) {
    return addDays(pregnancy.terme_confirme_date, PREGNANCY_DAYS - pregnancy.terme_confirme_jours)
  }
  return null
}

/**
 * Gestational age in completed weeks on a day, from the most reliable
 * anchor: the ultrasound first, then the last period, then the due date.
 * @param {Pregnancy} pregnancy
 * @param {string} on ISO date.
 * @returns {number | null} null when nothing anchors the term, or out of 0–45.
 */
export function gestationalWeeks(pregnancy, on) {
  let days = null
  if (pregnancy.terme_confirme_date && pregnancy.terme_confirme_jours !== null) {
    days = pregnancy.terme_confirme_jours + ageInDays(pregnancy.terme_confirme_date, on)
  } else if (pregnancy.ddr) {
    days = ageInDays(pregnancy.ddr, on)
  } else {
    const due = dueDate(pregnancy)
    if (due) days = PREGNANCY_DAYS - ageInDays(on, due)
  }
  if (days === null) return null
  const weeks = Math.floor(days / 7)
  return weeks >= 0 && weeks <= 45 ? weeks : null
}

/**
 * The pregnancy a health worker asks about first.
 * @param {Pregnancy[]} pregnancies
 * @returns {Pregnancy | null}
 */
export function currentPregnancy(pregnancies) {
  return pregnancies.find((p) => !p.terminee) ?? null
}
