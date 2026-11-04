import type { Count, DischargeOutcome, StatsMetrics, StatsPeriodRow, StatsResponse, StatsZoneRow } from '@/api/types'

/**
 * Small-group protection (spec section 10): no figure about fewer than
 * 5 cases is ever displayed or exported. The server is expected to do it
 * too; the dashboard applies it again so a server mistake cannot leak.
 */
export const SMALL_GROUP_THRESHOLD = 5

/** A figure on screen: a value, or hidden because the group is too small. */
export type Protected = { hidden: false; value: number } | { hidden: true }

export const HIDDEN: Protected = { hidden: true }

export function protectCount(value: Count | undefined): Protected {
  if (value === null || value === undefined) return HIDDEN
  // Zero describes nobody; 1 to 4 could point at a person.
  if (value > 0 && value < SMALL_GROUP_THRESHOLD) return HIDDEN
  return { hidden: false, value }
}

/** A rate is shown only when its denominator is large enough. */
export function protectRate(numerator: Count | undefined, denominator: Count | undefined): Protected {
  if (numerator == null || denominator == null) return HIDDEN
  if (denominator < SMALL_GROUP_THRESHOLD) return HIDDEN
  if (numerator > 0 && numerator < SMALL_GROUP_THRESHOLD) return HIDDEN
  if (denominator - numerator > 0 && denominator - numerator < SMALL_GROUP_THRESHOLD) return HIDDEN
  return { hidden: false, value: numerator / denominator }
}

/** A mean is shown only when it is computed over enough cases. */
export function protectMean(mean: number | null | undefined, cases: Count | undefined): Protected {
  if (mean == null || cases == null || cases < SMALL_GROUP_THRESHOLD) return HIDDEN
  return { hidden: false, value: mean }
}

export const COUNT_METRICS = [
  'depistages',
  'mas',
  'mam',
  'referencements',
  'referencements_arrives',
  'rdv_manques',
] as const
export type CountMetric = (typeof COUNT_METRICS)[number]

export interface ProtectedMetrics {
  counts: Record<CountMetric, Protected>
  arrivalRate: Protected
  meanDelayHours: Protected
}

export function protectMetrics(metrics: StatsMetrics): ProtectedMetrics {
  const counts = Object.fromEntries(
    COUNT_METRICS.map((key) => [key, protectCount(metrics[key])]),
  ) as Record<CountMetric, Protected>
  return {
    counts,
    arrivalRate: protectRate(metrics.referencements_arrives, metrics.referencements),
    meanDelayHours: protectMean(metrics.delai_moyen_arrivee_heures, metrics.referencements_arrives),
  }
}

/**
 * Secondary suppression: when a total is visible and only one cell of a
 * column is hidden, that cell can be found by subtraction. Hide the next
 * smallest visible cell as well.
 */
export function suppressComplementary(cells: Protected[], totalVisible: boolean): Protected[] {
  const result = [...cells]
  const hiddenCount = result.filter((c) => c.hidden).length
  if (!totalVisible || hiddenCount !== 1) return result
  let smallest = -1
  result.forEach((cell, index) => {
    if (cell.hidden || cell.value === 0) return
    const current = result[smallest]
    if (smallest === -1 || (current && !current.hidden && cell.value < current.value)) smallest = index
  })
  if (smallest !== -1) result[smallest] = HIDDEN
  return result
}

export interface ProtectedZoneRow {
  zoneId: number
  zoneName: string
  metrics: ProtectedMetrics
}

export interface ProtectedPeriodRow {
  period: string
  counts: Record<'depistages' | 'mas' | 'mam', Protected>
}

export interface ProtectedStats {
  period: { start: string; end: string }
  totals: ProtectedMetrics
  outcomes: Record<DischargeOutcome, Protected>
  zones: ProtectedZoneRow[]
  periods: ProtectedPeriodRow[]
}

export const OUTCOMES: DischargeOutcome[] = ['gueri', 'transfere', 'non_repondant', 'abandon', 'deces']

function protectZones(rows: StatsZoneRow[], totals: ProtectedMetrics): ProtectedZoneRow[] {
  const zones = rows.map((row) => ({
    zoneId: row.zone_id,
    zoneName: row.zone_nom,
    metrics: protectMetrics(row),
  }))
  for (const key of COUNT_METRICS) {
    const column = suppressComplementary(
      zones.map((z) => z.metrics.counts[key]),
      !totals.counts[key].hidden,
    )
    column.forEach((cell, i) => {
      const zone = zones[i]
      if (zone) zone.metrics.counts[key] = cell
    })
  }
  return zones
}

function protectPeriods(rows: StatsPeriodRow[]): ProtectedPeriodRow[] {
  return rows.map((row) => ({
    period: row.periode,
    counts: {
      depistages: protectCount(row.depistages),
      mas: protectCount(row.mas),
      mam: protectCount(row.mam),
    },
  }))
}

/** The only entry point the screens use: raw server data never reaches them. */
export function protectStats(stats: StatsResponse): ProtectedStats {
  const totals = protectMetrics(stats.totaux)
  return {
    period: { start: stats.periode.debut, end: stats.periode.fin },
    totals,
    outcomes: Object.fromEntries(OUTCOMES.map((o) => [o, protectCount(stats.issues_sortie?.[o])])) as Record<
      DischargeOutcome,
      Protected
    >,
    zones: protectZones(stats.par_zone ?? [], totals),
    periods: protectPeriods(stats.par_periode ?? []),
  }
}
