import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/errors'
import { referralsApi } from '@/api/referrals'
import { useReferralsStore } from '@/stores/referrals'
import { makeReferral } from '../helpers'

describe('referrals store', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('reads the incoming queue from its own endpoint', async () => {
    const waiting = makeReferral({ status: 'envoye' })
    const arrived = makeReferral({ status: 'recu', priorite: 'urgente' })
    const incoming = vi.spyOn(referralsApi, 'incoming').mockResolvedValue([waiting, arrived])
    const store = useReferralsStore()

    await store.loadTab('incoming')

    expect(incoming).toHaveBeenCalledOnce()
    expect(store.tab('incoming').map((r) => r.id)).toEqual([arrived.id, waiting.id])
  })

  it('loads each status of a tab and keeps them in triage order', async () => {
    const yellow = makeReferral({ priorite: 'normale', status: 'pris_en_charge' })
    const red = makeReferral({ priorite: 'urgente', status: 'en_suivi' })
    const list = vi.spyOn(referralsApi, 'list').mockImplementation(async (status) =>
      status === 'pris_en_charge' ? [yellow] : status === 'en_suivi' ? [red] : [],
    )
    const store = useReferralsStore()

    await store.loadTab('in_care')

    expect(list.mock.calls.map((c) => c[0])).toEqual(['pris_en_charge', 'en_suivi'])
    expect(store.tab('in_care').map((r) => r.id)).toEqual([red.id, yellow.id])
    expect(store.counts.in_care).toBe(2)
  })

  it('"Patient arrivé" sends the next status with the current version', async () => {
    const referral = makeReferral({ status: 'envoye', version: 4 })
    const change = vi.spyOn(referralsApi, 'changeStatus').mockResolvedValue({ ...referral, status: 'recu', version: 5 })
    const store = useReferralsStore()
    store.remember([referral])

    await store.changeStatus(referral, 'recu')

    expect(change).toHaveBeenCalledWith(referral.id, { status: 'recu', version: 4 })
    expect(store.byId[referral.id]!.status).toBe('recu')
  })

  it('sends the exit outcome with the "sortie" status', async () => {
    const referral = makeReferral({ status: 'pris_en_charge', version: 2 })
    const change = vi.spyOn(referralsApi, 'changeStatus').mockResolvedValue({ ...referral, status: 'sortie', version: 3 })
    const store = useReferralsStore()

    await store.changeStatus(referral, 'sortie', 'transfere')

    expect(change).toHaveBeenCalledWith(referral.id, { status: 'sortie', version: 2, issue_sortie: 'transfere' })
    expect(store.tab('closed')).toHaveLength(1)
  })

  it('on a version conflict, shows the server copy and lets the user decide again', async () => {
    const stale = makeReferral({ status: 'envoye', version: 1 })
    const current = { ...stale, status: 'recu' as const, version: 2 }
    vi.spyOn(referralsApi, 'changeStatus').mockRejectedValue(
      new ApiError({ kind: 'conflict', status: 409, body: { detail: 'x', code: 'conflit_version', current } }),
    )
    const store = useReferralsStore()
    store.remember([stale])

    await expect(store.changeStatus(stale, 'recu')).rejects.toMatchObject({ kind: 'conflict' })
    expect(store.byId[stale.id]).toEqual(current)
  })
})
