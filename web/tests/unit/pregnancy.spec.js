import { describe, expect, it } from 'vitest'
import { currentPregnancy, dueDate, gestationalWeeks } from '@/utils/pregnancy'

/** @param {Partial<import('@/api/types').Pregnancy>} extra */
function pregnancy(extra = {}) {
  return {
    id: '22222222-2222-4222-8222-222222222222',
    user_id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
    ddr: null,
    dpa: null,
    dpa_saisie: null,
    terme_confirme_date: null,
    terme_confirme_jours: null,
    date_accouchement: null,
    mode_allaitement: '',
    terminee: false,
    version: 1,
    created_at: '2026-06-01T00:00:00Z',
    updated_at: '2026-06-01T00:00:00Z',
    device_id: 'phone-1',
    deleted_at: null,
    ...extra,
  }
}

describe('dueDate', () => {
  it('prefers the computed due date, then the typed one', () => {
    expect(dueDate(pregnancy({ dpa: '2026-10-08', dpa_saisie: '2026-10-01' }))).toBe('2026-10-08')
    expect(dueDate(pregnancy({ dpa_saisie: '2026-10-01' }))).toBe('2026-10-01')
  })

  it('projects the due date from an ultrasound', () => {
    // 100 days of term on 2026-06-01: 180 days left.
    expect(dueDate(pregnancy({ terme_confirme_date: '2026-06-01', terme_confirme_jours: 100 }))).toBe('2026-11-28')
  })

  it('is null when nothing anchors the term', () => {
    expect(dueDate(pregnancy())).toBeNull()
  })
})

describe('gestationalWeeks', () => {
  it('counts completed weeks from the last period', () => {
    expect(gestationalWeeks(pregnancy({ ddr: '2026-01-01' }), '2026-04-02')).toBe(13)
  })

  it('prefers the ultrasound over the last period', () => {
    const p = pregnancy({ ddr: '2026-01-01', terme_confirme_date: '2026-03-01', terme_confirme_jours: 70 })
    // 70 days on March 1st + 31 days of March = 101 days = 14 weeks.
    expect(gestationalWeeks(p, '2026-04-01')).toBe(14)
  })

  it('falls back to the due date', () => {
    // 280 - 70 = 210 days = 30 weeks.
    expect(gestationalWeeks(pregnancy({ dpa_saisie: '2026-06-10' }), '2026-04-01')).toBe(30)
  })

  it('hides impossible values', () => {
    expect(gestationalWeeks(pregnancy({ ddr: '2026-06-01' }), '2026-04-01')).toBeNull()
    expect(gestationalWeeks(pregnancy({ ddr: '2024-01-01' }), '2026-04-01')).toBeNull()
    expect(gestationalWeeks(pregnancy(), '2026-04-01')).toBeNull()
  })
})

describe('currentPregnancy', () => {
  it('picks the one that is not finished', () => {
    const done = pregnancy({ terminee: true })
    const open = pregnancy({ id: '33333333-3333-4333-8333-333333333333' })
    expect(currentPregnancy([done, open])).toBe(open)
    expect(currentPregnancy([done])).toBeNull()
    expect(currentPregnancy([])).toBeNull()
  })
})
