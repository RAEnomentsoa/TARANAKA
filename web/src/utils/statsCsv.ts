import type { CsvCell } from './csv'
import { COUNT_METRICS, OUTCOMES, type Protected, type ProtectedMetrics, type ProtectedStats } from './privacy'

/**
 * CSV rows built from already-protected statistics: the export can never
 * contain a figure the screen hides.
 */
export interface StatsCsvLabels {
  translate: (key: string, values?: Record<string, unknown>) => string
  hidden: string
  zoneName: string
}

function cell(value: Protected, format: (n: number) => CsvCell = (n) => n): CsvCell {
  return value.hidden ? '' : format(value.value)
}

function note(value: Protected, hidden: string): CsvCell {
  return value.hidden ? hidden : ''
}

function metricRows(section: string, label: string, metrics: ProtectedMetrics, labels: StatsCsvLabels): CsvCell[][] {
  const t = labels.translate
  const rows: CsvCell[][] = COUNT_METRICS.map((key) => [
    section,
    label,
    t(`stats.metrics.${key}`),
    cell(metrics.counts[key]),
    note(metrics.counts[key], labels.hidden),
  ])
  rows.push([section, label, t('stats.metrics.arrivalRate'), cell(metrics.arrivalRate, (n) => Number((n * 100).toFixed(1))), note(metrics.arrivalRate, labels.hidden)])
  rows.push([section, label, t('stats.metrics.meanDelay'), cell(metrics.meanDelayHours, (n) => Number(n.toFixed(1))), note(metrics.meanDelayHours, labels.hidden)])
  return rows
}

export function buildStatsCsv(stats: ProtectedStats, labels: StatsCsvLabels): CsvCell[][] {
  const t = labels.translate
  const rows: CsvCell[][] = [
    [t('stats.period'), stats.period.start, stats.period.end],
    [t('stats.zone'), labels.zoneName],
    [],
    [t('stats.csv.section'), t('stats.zoneColumn'), t('stats.csv.metric'), t('stats.csv.value'), ''],
  ]
  rows.push(...metricRows(t('stats.csv.total'), labels.zoneName, stats.totals, labels))
  for (const zone of stats.zones) rows.push(...metricRows(t('stats.byZone'), zone.zoneName, zone.metrics, labels))
  for (const period of stats.periods) {
    for (const key of ['depistages', 'mas', 'mam'] as const) {
      rows.push([t('stats.byPeriod'), period.period, t(`stats.metrics.${key}`), cell(period.counts[key]), note(period.counts[key], labels.hidden)])
    }
  }
  for (const outcome of OUTCOMES) {
    const value = stats.outcomes[outcome]
    rows.push([t('stats.outcomes'), labels.zoneName, t(`discharge.outcomes.${outcome}`), cell(value), note(value, labels.hidden)])
  }
  return rows
}
