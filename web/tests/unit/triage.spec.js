import { describe, expect, it } from 'vitest'
import { canDischargeFrom, compareTriage, nextStatus, sortForTriage, urgencyOf } from '@/utils/triage'
import { makeReferral } from '../helpers'

describe('triage', () => {
  it('uses the server urgency, or maps the priority to the spec colours', () => {
    expect(urgencyOf({ priorite: 'urgente' })).toBe('rouge')
    expect(urgencyOf({ priorite: 'haute' })).toBe('orange')
    expect(urgencyOf({ priorite: 'normale' })).toBe('jaune')
    expect(urgencyOf({ priorite: 'normale', urgence: 'rouge' })).toBe('rouge')
  })

  it('sorts by urgency first, then the oldest referral first', () => {
    const yellowOld = makeReferral({ priorite: 'normale', date_referencement: '2026-11-01T08:00:00Z' })
    const orangeNew = makeReferral({ priorite: 'haute', date_referencement: '2026-11-04T10:00:00Z' })
    const orangeOld = makeReferral({ priorite: 'haute', date_referencement: '2026-11-02T10:00:00Z' })
    const red = makeReferral({ priorite: 'urgente', date_referencement: '2026-11-04T11:00:00Z' })

    const sorted = sortForTriage([yellowOld, orangeNew, red, orangeOld])

    expect(sorted.map((r) => r.id)).toEqual([red.id, orangeOld.id, orangeNew.id, yellowOld.id])
  })

  it('ages a referral by when it was made on the phone, not when it was synced', () => {
    const madeEarlySyncedLate = makeReferral({
      date_referencement: '2026-11-01T08:00:00Z',
      created_at: '2026-11-04T09:00:00Z',
    })
    const madeLate = makeReferral({ date_referencement: '2026-11-03T08:00:00Z', created_at: '2026-11-03T08:05:00Z' })
    expect(sortForTriage([madeLate, madeEarlySyncedLate])[0].id).toBe(madeEarlySyncedLate.id)
  })

  it('does not change the list it sorts, and is a consistent comparator', () => {
    const list = [makeReferral({ priorite: 'normale' }), makeReferral({ priorite: 'urgente' })]
    const copy = [...list]
    sortForTriage(list)
    expect(list).toEqual(copy)
    expect(compareTriage(list[0], list[0])).toBe(0)
  })

  it('follows the spec life cycle one step at a time', () => {
    expect(nextStatus('envoye')).toBe('recu')
    expect(nextStatus('recu')).toBe('pris_en_charge')
    expect(nextStatus('pris_en_charge')).toBe('en_suivi')
    expect(nextStatus('en_suivi')).toBeNull()
    expect(nextStatus('sortie')).toBeNull()
  })

  it('allows a discharge only once the patient has arrived', () => {
    expect(canDischargeFrom('envoye')).toBe(false)
    expect(canDischargeFrom('recu')).toBe(true)
    expect(canDischargeFrom('pris_en_charge')).toBe(true)
    expect(canDischargeFrom('en_suivi')).toBe(true)
    expect(canDischargeFrom('sortie')).toBe(false)
  })
})
