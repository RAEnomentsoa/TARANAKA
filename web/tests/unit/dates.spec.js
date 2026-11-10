import { describe, expect, it } from 'vitest'
import { addDays, ageInDays, ageInMonths, elapsed, formatDate } from '@/utils/dates'

describe('dates', () => {
  it('computes the age from the birth date like the backend (30.4375 days a month)', () => {
    expect(ageInDays('2025-05-04', '2026-11-04')).toBe(549)
    expect(ageInMonths('2025-05-04', '2026-11-04')).toBe(18)
    expect(ageInMonths('2026-10-06', '2026-11-04')).toBe(0)
  })

  it('adds days across month ends', () => {
    expect(addDays('2026-10-28', 7)).toBe('2026-11-04')
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
  })

  it('rounds waiting time to a readable unit', () => {
    const now = new Date('2026-11-04T12:00:00Z')
    expect(elapsed('2026-11-04T11:35:00Z', now)).toEqual({ unit: 'minutes', value: 25 })
    expect(elapsed('2026-11-04T02:00:00Z', now)).toEqual({ unit: 'hours', value: 10 })
    expect(elapsed('2026-11-01T12:00:00Z', now)).toEqual({ unit: 'days', value: 3 })
    expect(elapsed('2026-11-05T12:00:00Z', now)).toEqual({ unit: 'minutes', value: 0 })
  })

  it('formats dates as dd/mm/yyyy without shifting the day', () => {
    expect(formatDate('2026-01-31')).toBe('31/01/2026')
  })
})
