import { describe, expect, it } from 'vitest'
import { compareTriage, nextStatus, sortForTriage, urgencyOf } from '@/utils/triage'
import { makeReferral } from '../helpers'

describe('triage', () => {
  it('maps backend priorities to the spec colours', () => {
    expect(urgencyOf('urgente')).toBe('rouge')
    expect(urgencyOf('haute')).toBe('orange')
    expect(urgencyOf('normale')).toBe('jaune')
  })

  it('sorts by urgency first, then oldest first', () => {
    const yellowOld = makeReferral({ priorite: 'normale', created_at: '2026-11-01T08:00:00Z' })
    const orangeNew = makeReferral({ priorite: 'haute', created_at: '2026-11-04T10:00:00Z' })
    const orangeOld = makeReferral({ priorite: 'haute', created_at: '2026-11-02T10:00:00Z' })
    const red = makeReferral({ priorite: 'urgente', created_at: '2026-11-04T11:00:00Z' })

    const sorted = sortForTriage([yellowOld, orangeNew, red, orangeOld])

    expect(sorted.map((r) => r.id)).toEqual([red.id, orangeOld.id, orangeNew.id, yellowOld.id])
  })

  it('does not change the list it sorts', () => {
    const list = [makeReferral({ priorite: 'normale' }), makeReferral({ priorite: 'urgente' })]
    const copy = [...list]
    sortForTriage(list)
    expect(list).toEqual(copy)
  })

  it('is a consistent comparator', () => {
    const a = makeReferral({ priorite: 'urgente' })
    expect(compareTriage(a, a)).toBe(0)
  })

  it('follows the backend status machine one step at a time', () => {
    expect(nextStatus('envoye')).toBe('recu')
    expect(nextStatus('recu')).toBe('vu')
    expect(nextStatus('vu')).toBe('pris_en_charge')
    expect(nextStatus('pris_en_charge')).toBe('clos')
    expect(nextStatus('clos')).toBeNull()
  })
})
