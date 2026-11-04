import { describe, expect, it } from 'vitest'
import StatusStepper from '@/components/referrals/StatusStepper.vue'
import AgentContact from '@/components/ui/AgentContact.vue'
import { makeReferral, mountWithApp } from '../helpers'

describe('AgentContact', () => {
  it('shows the agent’s name and a tap-to-call link', () => {
    const wrapper = mountWithApp(AgentContact, {
      props: { contact: { nom: 'Rasoanirina', prenom: 'Rasoa', phone: '034 11 222 33' } },
    })
    expect(wrapper.text()).toContain('Rasoa Rasoanirina')
    const link = wrapper.find('a')
    expect(link.attributes('href')).toBe('tel:0341122233')
    expect(link.attributes('aria-label')).toBe('Appeler Rasoa Rasoanirina au 034 11 222 33')
  })

  it('says when no phone is recorded, or when the contact is unknown', () => {
    expect(mountWithApp(AgentContact, { props: { contact: { nom: 'A', prenom: 'B', phone: '' } } }).text()).toContain(
      'Pas de téléphone enregistré',
    )
    expect(mountWithApp(AgentContact, { props: { contact: null } }).text()).toContain('Inconnu')
  })
})

describe('StatusStepper', () => {
  const states = (wrapper) =>
    wrapper.findAll('.stepper__step').map((li) => li.classes().find((c) => c.startsWith('stepper__step--')).split('--')[1])

  it('dates each step reached and marks the current one', () => {
    const referral = makeReferral({
      status: 'en_suivi',
      date_reception: '2026-11-04T09:00:00Z',
      date_prise_en_charge: '2026-11-04T10:00:00Z',
      date_suivi: '2026-11-05T08:00:00Z',
    })
    const wrapper = mountWithApp(StatusStepper, { props: { referral } })
    expect(states(wrapper)).toEqual(['done', 'done', 'done', 'current', 'todo'])
    expect(wrapper.findAll('time')).toHaveLength(4)
    expect(wrapper.find('[aria-current="step"]').text()).toContain('En suivi')
  })

  it('shows "En suivi" as skipped after a discharge straight from the care step', () => {
    const referral = makeReferral({
      status: 'sortie',
      date_reception: '2026-11-04T09:00:00Z',
      date_prise_en_charge: '2026-11-04T10:00:00Z',
      date_suivi: null,
      date_sortie: '2026-11-06T10:00:00Z',
    })
    const wrapper = mountWithApp(StatusStepper, { props: { referral } })
    expect(states(wrapper)).toEqual(['done', 'done', 'done', 'skipped', 'done'])
    expect(wrapper.findAll('.stepper__step')[3].text()).toContain('non franchie')
  })

  it('shows "En suivi" as done when the case went through it', () => {
    const referral = makeReferral({ status: 'sortie', date_suivi: '2026-11-05T08:00:00Z', date_sortie: '2026-11-06T10:00:00Z' })
    expect(states(mountWithApp(StatusStepper, { props: { referral } }))[3]).toBe('done')
  })
})
