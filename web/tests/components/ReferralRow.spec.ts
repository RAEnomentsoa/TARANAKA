import { describe, expect, it } from 'vitest'
import ReferralRow from '@/components/referrals/ReferralRow.vue'
import { makeReferral, mountWithApp } from '../helpers'

const now = new Date('2026-11-04T11:00:00Z')

describe('ReferralRow', () => {
  it('shows urgency, code, reason and waiting time', () => {
    const referral = makeReferral({ priorite: 'urgente', motif: 'Œdèmes ++', created_at: '2026-11-04T08:00:00Z' })
    const wrapper = mountWithApp(ReferralRow, { props: { referral, now, canUpdate: true, busy: false } })

    expect(wrapper.classes()).toContain('row--rouge')
    expect(wrapper.text()).toContain('Œdèmes ++')
    expect(wrapper.text()).toContain('3 h')
    expect(wrapper.find('a').text()).toContain(`Ouvrir le dossier ${referral.code_unique}`)
  })

  it('offers "Patient arrivé" for a referral not received yet', async () => {
    const referral = makeReferral({ status: 'envoye' })
    const wrapper = mountWithApp(ReferralRow, { props: { referral, now, canUpdate: true, busy: false } })

    const button = wrapper.find('button')
    expect(button.text()).toBe('Patient arrivé')
    await button.trigger('click')
    expect(wrapper.emitted('arrived')?.[0]).toEqual([referral])
  })

  it('hides the action once received, or without the permission', () => {
    const received = mountWithApp(ReferralRow, { props: { referral: makeReferral({ status: 'recu' }), now, canUpdate: true, busy: false } })
    expect(received.find('button').exists()).toBe(false)
    const readOnly = mountWithApp(ReferralRow, { props: { referral: makeReferral(), now, canUpdate: false, busy: false } })
    expect(readOnly.find('button').exists()).toBe(false)
  })

  it('names the pregnant woman for a pregnancy referral', () => {
    const referral = makeReferral({ origine: 'grossesse', enfant_id: null, femme: { nom: 'Rasoa', prenom: 'Lala' } })
    const wrapper = mountWithApp(ReferralRow, { props: { referral, now, canUpdate: true, busy: false } })
    expect(wrapper.text()).toContain('Lala Rasoa')
  })
})
