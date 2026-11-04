import { describe, expect, it } from 'vitest'
import ConflictCard from '@/components/referrals/ConflictCard.vue'
import type { SyncConflict } from '@/api/types'
import { mountWithApp } from '../helpers'

const conflict: SyncConflict = {
  id: 3,
  table_nom: 'enfant',
  ligne_id: '33333333-3333-4333-8333-333333333333',
  date_creation: '2026-11-04T09:00:00Z',
  version_serveur: { version: 2, device_id: 'phone-a', date: '2026-11-04T08:00:00Z', donnees: { nom: 'Fara', sexe: 'F' } },
  version_appareil: { version: 2, device_id: 'phone-b', date: '2026-11-04T08:10:00Z', donnees: { nom: 'Faramalala', sexe: 'F' } },
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
})
