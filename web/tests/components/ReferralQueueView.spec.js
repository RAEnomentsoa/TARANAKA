import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { referralsApi } from '@/api/referrals'
import { useAuthStore } from '@/stores/auth'
import ReferralQueueView from '@/views/staff/ReferralQueueView.vue'
import { makeReferral, makeUser, mountWithApp } from '../helpers'

describe('ReferralQueueView', () => {
  it('lists incoming referrals red first, then the oldest', async () => {
    const yellow = makeReferral({ priorite: 'normale', date_referencement: '2026-11-01T08:00:00Z' })
    const orange = makeReferral({ priorite: 'haute', date_referencement: '2026-11-04T08:00:00Z' })
    const red = makeReferral({ priorite: 'urgente', date_referencement: '2026-11-04T10:00:00Z' })
    vi.spyOn(referralsApi, 'incoming').mockResolvedValue([yellow, orange, red])
    vi.spyOn(referralsApi, 'list').mockResolvedValue([])

    const wrapper = mountWithApp(ReferralQueueView, { attachTo: document.body })
    useAuthStore().user = makeUser('agent_csb')
    await flushPromises()

    const codes = wrapper.findAll('.row').map((row) => row.find('.code').attributes('aria-label'))
    expect(codes).toEqual([red.code_unique, orange.code_unique, yellow.code_unique])
    expect(wrapper.text()).toContain('3 référencements')
    wrapper.unmount()
  })

  it('records an arrival after confirmation', async () => {
    const referral = makeReferral({ priorite: 'urgente' })
    vi.spyOn(referralsApi, 'incoming').mockResolvedValue([referral])
    vi.spyOn(referralsApi, 'list').mockResolvedValue([])
    const change = vi.spyOn(referralsApi, 'changeStatus').mockResolvedValue({ ...referral, status: 'recu', version: 2 })

    const wrapper = mountWithApp(ReferralQueueView, { attachTo: document.body })
    useAuthStore().user = makeUser('agent_csb')
    await flushPromises()

    await wrapper.find('.row button').trigger('click')
    await flushPromises()
    const dialog = wrapper.find('dialog')
    expect(dialog.text()).toContain(`Confirmer l'arrivée du patient ${referral.code_unique}`)
    const confirm = dialog.findAll('button').find((b) => b.text() === 'Patient arrivé')
    await confirm.trigger('click')
    await flushPromises()

    expect(change).toHaveBeenCalledWith(referral.id, { status: 'recu', version: 1 })
    // Still in the queue (envoye and recu), now without the arrival button.
    expect(wrapper.find('.row button').exists()).toBe(false)
    expect(wrapper.find('.row').text()).toContain('Patient arrivé')
    wrapper.unmount()
  })

  it('explains an empty queue', async () => {
    vi.spyOn(referralsApi, 'incoming').mockResolvedValue([])
    vi.spyOn(referralsApi, 'list').mockResolvedValue([])
    const wrapper = mountWithApp(ReferralQueueView)
    await flushPromises()
    expect(wrapper.text()).toContain('Aucun référencement dans cette liste.')
  })
})
