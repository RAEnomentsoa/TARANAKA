import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/errors'
import { referralsApi } from '@/api/referrals'
import { useReferralsStore } from '@/stores/referrals'
import { makeReferral } from '../helpers'

describe('referrals store', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('loads each status of a tab and keeps them in triage order', async () => {
    const yellow = makeReferral({ priorite: 'normale', status: 'recu' })
    const red = makeReferral({ priorite: 'urgente', status: 'vu' })
    const list = vi.spyOn(referralsApi, 'list').mockImplementation(async (status) =>
      status === 'recu' ? [yellow] : status === 'vu' ? [red] : [],
    )
    const store = useReferralsStore()

    await store.loadTab('in_care')

    expect(list.mock.calls.map((c) => c[0])).toEqual(['recu', 'vu', 'pris_en_charge'])
    expect(store.tab('in_care').map((r) => r.id)).toEqual([red.id, yellow.id])
    expect(store.counts.in_care).toBe(2)
  })

  it('"Patient arrivé" sends the next status with the current version', async () => {
    const referral = makeReferral({ status: 'envoye', version: 4 })
    const change = vi.spyOn(referralsApi, 'changeStatus').mockResolvedValue({ ...referral, status: 'recu', version: 5 })
    const store = useReferralsStore()
    store.remember([referral])

    await store.advance(referral)

    expect(change).toHaveBeenCalledWith(referral.id, { status: 'recu', version: 4 })
    expect(store.byId[referral.id]!.status).toBe('recu')
    expect(store.tab('incoming')).toHaveLength(0)
  })

  it('sends the discharge outcome with the "clos" status', async () => {
    const referral = makeReferral({ status: 'pris_en_charge', version: 2 })
    const change = vi.spyOn(referralsApi, 'changeStatus').mockResolvedValue({ ...referral, status: 'clos', version: 3 })
    const store = useReferralsStore()

    await store.advance(referral, { issue_sortie: 'gueri', date_sortie: '2026-11-04', notes: '' })

    expect(change).toHaveBeenCalledWith(referral.id, {
      status: 'clos',
      version: 2,
      issue_sortie: 'gueri',
      date_sortie: '2026-11-04',
      notes: '',
    })
  })

  it('on a version conflict, shows the server copy and lets the user decide again', async () => {
    const stale = makeReferral({ status: 'envoye', version: 1 })
    const current = { ...stale, status: 'recu' as const, version: 2 }
    vi.spyOn(referralsApi, 'changeStatus').mockRejectedValue(
      new ApiError({ kind: 'conflict', status: 409, body: { detail: 'x', code: 'conflit_version', current } }),
    )
    const store = useReferralsStore()
    store.remember([stale])

    await expect(store.advance(stale)).rejects.toMatchObject({ kind: 'conflict' })
    expect(store.byId[stale.id]).toEqual(current)
  })
})
