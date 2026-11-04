import { describe, expect, it } from 'vitest'
import { escapeCsvCell, toCsv } from '@/utils/csv'
import { HIDDEN, type ProtectedStats } from '@/utils/privacy'
import { buildStatsCsv } from '@/utils/statsCsv'

describe('CSV', () => {
  it('quotes commas, quotes and line breaks', () => {
    expect(escapeCsvCell('a,b')).toBe('"a,b"')
    expect(escapeCsvCell('dit "oui"')).toBe('"dit ""oui"""')
    expect(escapeCsvCell('ligne\n2')).toBe('"ligne\n2"')
    expect(escapeCsvCell(null)).toBe('')
    expect(escapeCsvCell(12.5)).toBe('12.5')
  })

  it('neutralises spreadsheet formulas but keeps negative numbers', () => {
    expect(escapeCsvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`)
    expect(escapeCsvCell('@SUM(A1)')).toBe("'@SUM(A1)")
    expect(escapeCsvCell('-2.5')).toBe('-2.5')
  })

  it('joins rows with CRLF', () => {
    expect(toCsv([['a', 1], ['b', 2]])).toBe('a,1\r\nb,2')
  })

  it('exports hidden figures as empty cells with a note, never as numbers', () => {
    const counts = { depistages: { hidden: false as const, value: 50 }, mas: HIDDEN, mam: { hidden: false as const, value: 9 }, referencements: HIDDEN, referencements_arrives: HIDDEN, rdv_manques: HIDDEN }
    const stats: ProtectedStats = {
      period: { start: '2026-08-01', end: '2026-10-31' },
      totals: { counts, arrivalRate: HIDDEN, meanDelayHours: { hidden: false, value: 12.345 } },
      outcomes: { gueri: { hidden: false, value: 6 }, transfere: HIDDEN, non_repondant: { hidden: false, value: 0 }, abandon: HIDDEN, deces: HIDDEN },
      zones: [],
      periods: [{ period: '2026-10', counts: { depistages: { hidden: false, value: 20 }, mas: HIDDEN, mam: HIDDEN } }],
    }
    const rows = buildStatsCsv(stats, { translate: (key) => key, hidden: 'HIDDEN', zoneName: 'Analamanga' })

    const masRow = rows.find((r) => r[0] === 'stats.csv.total' && r[2] === 'stats.metrics.mas')
    expect(masRow).toEqual(['stats.csv.total', 'Analamanga', 'stats.metrics.mas', '', 'HIDDEN'])
    const delayRow = rows.find((r) => r[2] === 'stats.metrics.meanDelay')
    expect(delayRow?.[3]).toBe(12.3)
    const numbers = rows.flatMap((r) => r.filter((c): c is number => typeof c === 'number'))
    expect(numbers.every((n) => n === 0 || n >= 5)).toBe(true)
  })
})
