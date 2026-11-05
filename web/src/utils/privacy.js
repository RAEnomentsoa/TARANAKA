/** @typedef {import('@/api/types').Indicator} Indicator */
/** @typedef {import('@/api/types').StatsBlock} StatsBlock */
/** @typedef {import('@/api/types').StatsResponse} StatsResponse */

/**
 * Small-group protection (spec §10): no figure about fewer than 5 cases is
 * displayed. The server does the masking (D11): counts of 1 to 4, rates and
 * means over fewer than 5 cases, and complementary suppression across groups
 * all come back as null and are listed in "masques". The screen shows exactly
 * what the server masked, so it matches the audited CSV export. As a safety
 * net, a count of 1 to 4 that would arrive unmasked is still hidden.
 */
export const SMALL_GROUP_THRESHOLD = 5

/**
 * A figure on screen: a value, or hidden because the group is too small.
 * @typedef {{ hidden: false, value: number } | { hidden: true }} Protected
 */

/** @type {Protected} */
export const HIDDEN = { hidden: true }

/**
 * @typedef {'sorties_gueri' | 'sorties_transfere' | 'sorties_non_repondant' | 'sorties_abandon' | 'sorties_decede'} OutcomeIndicator
 */

/**
 * @typedef {(
 *   | 'depistages'
 *   | 'enfants_depistes'
 *   | 'cas_mas'
 *   | 'cas_mam'
 *   | 'nourrissons_a_risque'
 *   | 'referencements'
 *   | 'referencements_arrives'
 *   | 'rendez_vous_manques'
 *   | OutcomeIndicator
 * )} CountIndicator
 */

/** @type {OutcomeIndicator[]} */
export const OUTCOME_INDICATORS = [
  'sorties_gueri',
  'sorties_transfere',
  'sorties_non_repondant',
  'sorties_abandon',
  'sorties_decede',
]

/** @type {CountIndicator[]} */
export const COUNT_INDICATORS = [
  'depistages',
  'enfants_depistes',
  'cas_mas',
  'cas_mam',
  'nourrissons_a_risque',
  'referencements',
  'referencements_arrives',
  'rendez_vous_manques',
  ...OUTCOME_INDICATORS,
]

/**
 * @param {number | null | undefined} value
 * @returns {Protected}
 */
export function protectCount(value) {
  if (value === null || value === undefined) return HIDDEN
  // Zero describes nobody; 1 to 4 could point at a person.
  if (value > 0 && value < SMALL_GROUP_THRESHOLD) return HIDDEN
  return { hidden: false, value }
}

/**
 * A rate or a mean: shown as sent, unless the server masked it.
 * @param {number | null | undefined} value
 * @returns {Protected}
 */
function protectMeasure(value) {
  return value === null || value === undefined ? HIDDEN : { hidden: false, value }
}

/**
 * @typedef {Object} ProtectedBlock
 * @property {Record<CountIndicator, Protected>} counts
 * @property {Protected} arrivalRate Percentage, 0 to 100.
 * @property {Protected} meanDelayHours
 */

/**
 * @param {StatsBlock} block
 * @returns {ProtectedBlock}
 */
export function protectBlock(block) {
  /** @param {Indicator} key */
  const raw = (key) => (block.masques.includes(key) ? null : (block.indicateurs[key] ?? null))
  return {
    counts: /** @type {Record<CountIndicator, Protected>} */ (
      Object.fromEntries(COUNT_INDICATORS.map((key) => [key, protectCount(raw(key))]))
    ),
    arrivalRate: protectMeasure(raw('taux_arrivee_pct')),
    meanDelayHours: protectMeasure(raw('delai_moyen_arrivee_heures')),
  }
}

/**
 * @typedef {Object} ProtectedGroup
 * @property {string} key
 * @property {string} label
 * @property {ProtectedBlock} block
 */

/**
 * @param {StatsResponse['groupes']} groups
 * @returns {ProtectedGroup[]}
 */
function protectGroups(groups) {
  return groups.map((g) => ({ key: g.cle, label: g.libelle, block: protectBlock(g) }))
}

/**
 * @typedef {Object} ProtectedStats
 * @property {{ start: string, end: string }} period
 * @property {ProtectedBlock} total
 * @property {ProtectedGroup[]} byRegion
 * @property {ProtectedGroup[]} byMonth
 */

/**
 * The only entry point the screens use: raw server numbers never reach them.
 * @param {StatsResponse} byRegion
 * @param {StatsResponse | null} byMonth
 * @returns {ProtectedStats}
 */
export function protectStats(byRegion, byMonth) {
  return {
    period: { start: byRegion.periode.date_debut, end: byRegion.periode.date_fin },
    total: protectBlock(byRegion.total),
    byRegion: protectGroups(byRegion.groupes ?? []),
    byMonth: byMonth ? protectGroups(byMonth.groupes ?? []) : [],
  }
}
