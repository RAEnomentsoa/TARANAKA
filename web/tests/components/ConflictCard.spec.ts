import { describe, expect, it } from 'vitest'
import ConflictCard from '@/components/referrals/ConflictCard.vue'
import type { SyncConflict } from '@/api/types'
import { mountWithApp } from '../helpers'

const conflict: SyncConflict = {
  id: '33330000-0000-4000-8000-000000000003',
  table_nom: 'enfant',
  ligne_id: '33333333-3333-4333-8333-333333333333',
  operation: 'update',
  version_base: 1,
  version_serveur: 2,
  donnees_serveur: { nom: 'Fara', sexe: 'F' },
  donnees_telephone: { nom: 'Faramalala', sexe: 'F' },
  user_id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
  device_id: 'tel-b',
  statut: 'a_verifier',
  created_at: '2026-11-04T09:00:00Z',
}

describe('ConflictCard', () => {
  it('shows both versions of each differing field only', () => {
    const wrapper = mountWithApp(ConflictCard, { props: { conflict, busy: false } })
    expect(wrapper.text()).toContain('Fiche enfant')
    expect(wrapper.findAll('tbody tr')).toHaveLength(1)
    expect(wrapper.text()).toContain('Fara')
    expect(wrapper.text()).toContain('Faramalala')
  })

  it('cannot be validated before a value is chosen for every field', async () => {
    const wrapper = mountWithApp(ConflictCard, { props: { conflict, busy: false } })
    const validate = () => wrapper.findAll('button').find((b) => b.text() === 'Valider l’arbitrage' || b.text() === "Valider l'arbitrage")!

    expect(validate().attributes('disabled')).toBeDefined()
    await wrapper.findAll('input[type="radio"]')[1]!.setValue(true)
    expect(validate().attributes('disabled')).toBeUndefined()
  })

  it('sends the chosen side and the comment after confirmation', async () => {
    const wrapper = mountWithApp(ConflictCard, { props: { conflict, busy: false }, attachTo: document.body })
    await wrapper.findAll('input[type="radio"]')[1]!.setValue(true) // phone value
    await wrapper.find('textarea').setValue('Vérifié avec la mère')
    await wrapper.findAll('button').find((b) => b.text().startsWith('Valider'))!.trigger('click')
    const confirm = wrapper.find('dialog').findAll('button').find((b) => b.text() === 'Confirmer')!
    await confirm.trigger('click')

    expect(wrapper.emitted('resolve')?.[0]).toEqual([{ choix: 'telephone', commentaire: 'Vérifié avec la mère' }])
    wrapper.unmount()
  })
})
