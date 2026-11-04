/**
 * WHO 2006 growth standards: which part of a table a chart needs, and how
 * to turn /api/who-reference/ points into chart curves.
 */

/** @typedef {import('@/api/types').Measurement} Measurement */
/** @typedef {import('@/api/types').Sexe} Sexe */
/** @typedef {import('@/api/types').WhoIndicator} WhoIndicator */
/** @typedef {import('@/api/types').WhoReference} WhoReference */
/** @typedef {import('@/api/types').WhoReferenceQuery} WhoReferenceQuery */
/** @typedef {import('@/utils/scale').ChartPoint} ChartPoint */

/**
 * One reference curve of a chart.
 * @typedef {Object} ReferenceCurve
 * @property {string} z "-3", "-2", "0", "2" or "3"
 * @property {{ x: number, y: number }[]} points
 */

/** z-scores drawn, from the lowest to the highest. */
export const WHO_Z = ['-3', '-2', '0', '2', '3']

export const DAYS_PER_MONTH = 30.4375 // same constant as nutrition/services.py
/** WHO measures length lying down before 2 years (731 days), height standing after. */
export const LENGTH_AGE_LIMIT_DAYS = 731

/** Bounds of the official tables (keys in days or cm). */
const TABLE_RANGE = {
  wfa: [0, 1856],
  lhfa: [0, 1856],
  wfl: [45, 110],
  wfh: [65, 120],
}
/** Margin around the child's values, so the curves frame the points. */
const MARGIN = { days: 61, cm: 5 }
/** Points per curve, at most: enough for a smooth line, light to load. */
const MAX_POINTS = 60

/**
 * @param {WhoIndicator} indicateur
 * @param {Sexe} sexe
 * @param {number[]} keys The child's keys (ages in days, or lengths in cm).
 * @returns {WhoReferenceQuery | null}
 */
export function referenceQuery(indicateur, sexe, keys) {
  if (!keys.length) return null
  const byAge = indicateur === 'wfa' || indicateur === 'lhfa'
  const margin = byAge ? MARGIN.days : MARGIN.cm
  const [low, high] = TABLE_RANGE[indicateur]
  const cleMin = Math.max(low, Math.floor(Math.min(...keys) - margin))
  const cleMax = Math.min(high, Math.ceil(Math.max(...keys) + margin))
  if (cleMin > cleMax) return null
  const pas = Math.max(1, Math.round((cleMax - cleMin) / MAX_POINTS))
  return { indicateur, sexe, cle_min: cleMin, cle_max: cleMax, pas }
}

/**
 * Weight for length before 2 years, weight for height after: the regime of
 * the child's latest measurement decides, and only measurements of that
 * regime are drawn against it.
 * @param {Measurement[]} measurements
 * @returns {{ indicateur: 'wfl' | 'wfh', measurements: Measurement[] }}
 */
export function weightForSizeRegime(measurements) {
  const latest = [...measurements].sort((a, b) => b.age_jour - a.age_jour)[0]
  const lying = !latest || latest.age_jour < LENGTH_AGE_LIMIT_DAYS
  return {
    indicateur: lying ? 'wfl' : 'wfh',
    measurements: measurements.filter((m) => (m.age_jour < LENGTH_AGE_LIMIT_DAYS) === lying),
  }
}

/**
 * Curves of a reference, with x mapped like the child's points
 * (for example days → months).
 * @param {WhoReference | null} reference
 * @param {(cle: number) => number} [x]
 * @returns {ReferenceCurve[]}
 */
export function referenceCurves(reference, x = (cle) => cle) {
  if (!reference?.points?.length) return []
  return WHO_Z.map((z) => ({
    z,
    points: reference.points
      .filter((p) => typeof p.courbes?.[z] === 'number')
      .map((p) => ({ x: x(Number(p.cle)), y: p.courbes[z] })),
  })).filter((curve) => curve.points.length > 1)
}
