/** @typedef {import('@/api/types').DischargeOutcome} DischargeOutcome */
/** @typedef {import('@/api/types').Indicator} Indicator */
/** @typedef {import('@/api/types').StatsBlock} StatsBlock */
/** @typedef {import('@/api/types').StatsResponse} StatsResponse */

/**
 * Small-group protection (spec §10): no figure about fewer than 5 cases is
 * displayed. The server already hides counts of 1 to 4 (null + "masques");
 * the dashboard checks again, and adds what the server does not do yet
 * (D11): rates whose complement is small, and complementary suppression.
 */
export const SMALL_GROUP_THRESHOLD = 5

/**
 * A figure on screen: a value, or hidden because the group is too small.
 * @typedef {{ hidden: false; value: number } | { hidden: true }} Protected
 */

/** @type {Protected} */
export const HIDDEN = { hidden: true }

export const OUTCOME_INDICATORS = [
  'sorties_gueri',
  'sorties_transfere',
  'sorties_non_repondant',
  'sorties_abandon',
  'sorties_decede',
]

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

/** @typedef {(typeof COUNT_INDICATORS)[number]} CountIndicator */

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
  const counts = Object.fromEntries(COUNT_INDICATORS.map((key) => [key, protectCount(raw(key))]))

  const sent = raw('referencements')
  const arrived = raw('referencements_arrives')
  const rate = raw('taux_arrivee_pct')
  // A rate also reveals its complement: 2 children who never arrived.
  const rateSafe =
    rate !== null &&
    sent !== null &&
    arrived !== null &&
    sent >= SMALL_GROUP_THRESHOLD &&
    !protectCount(arrived).hidden &&
    !protectCount(sent - arrived).hidden

  const delay = raw('delai_moyen_arrivee_heures')
  const delaySafe = delay !== null && arrived !== null && arrived >= SMALL_GROUP_THRESHOLD

  return {
    counts,
    arrivalRate: rateSafe ? { hidden: false, value: rate } : HIDDEN,
    meanDelayHours: delaySafe ? { hidden: false, value: delay } : HIDDEN,
  }
}

/**
 * Complementary suppression: when a total is visible and only one cell of a
 * column is hidden, that cell can be found by subtraction. Hide the smallest
 * other non-zero cell as well.
 * @param {Protected[]} cells
 * @param {boolean} totalVisible
 * @returns {Protected[]}
 */
export function suppressComplementary(cells, totalVisible) {
  const result = [...cells]
  if (!totalVisible || result.filter((c) => c.hidden).length !== 1) return result
  let smallest = -1
  let smallestValue = Infinity
  result.forEach((cell, index) => {
    if (!cell.hidden && cell.value > 0 && cell.value < smallestValue) {
      smallest = index
      smallestValue = cell.value
    }
  })
  if (smallest !== -1) result[smallest] = HIDDEN
  return result
}

/**
 * @typedef {Object} ProtectedGroup
 * @property {string} key
 * @property {string} label
 * @property {ProtectedBlock} block
 */

/**
 * @param {StatsResponse['groupes']} groups
 * @param {ProtectedBlock} total
 * @returns {ProtectedGroup[]}
 */
function protectGroups(groups, total) {
  const rows = groups.map((g) => ({ key: g.cle, label: g.libelle, block: protectBlock(g) }))
  for (const key of COUNT_INDICATORS) {
    const column = suppressComplementary(
      rows.map((r) => r.block.counts[key]),
      !total.counts[key].hidden,
    )
    column.forEach((cell, i) => {
      const row = rows[i]
      if (row) row.block.counts[key] = cell
    })
  }
  return rows
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
  const total = protectBlock(byRegion.total)
  return {
    period: { start: byRegion.periode.date_debut, end: byRegion.periode.date_fin },
    total,
    byRegion: protectGroups(byRegion.groupes ?? [], total),
    byMonth: byMonth ? protectGroups(byMonth.groupes ?? [], total) : [],
  }
}
