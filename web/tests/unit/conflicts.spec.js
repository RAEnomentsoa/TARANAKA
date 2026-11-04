import { describe, expect, it } from 'vitest'
import { buildResolution, differingFields, displayValue } from '@/utils/conflicts'

/** @typedef {import('@/api/types').SyncConflict} SyncConflict */

/** @type {SyncConflict} */
const measureConflict = {
  id: '7b1c0000-0000-4000-8000-000000000007',
  table_nom: 'mesure',
  ligne_id: '22222222-2222-4222-8222-222222222222',
  operation: 'update',
  version_base: 2,
  version_serveur: 3,
  donnees_serveur: { poids_kg: '8.40', taille_cm: '72.0', pb_mm: 112, version: 3, updated_at: 'x' },
  donnees_telephone: { poids_kg: '8.10', taille_cm: '72.0', pb_mm: 118, version: 2, updated_at: 'y' },
  user_id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
  device_id: 'tel-7',
  statut: 'a_verifier',
  created_at: '2026-11-04T09:00:00Z',
}

describe('conflict arbitration', () => {
  it('lists only clinical fields that differ', () => {
    expect(differingFields(measureConflict)).toEqual(['pb_mm', 'poids_kg'])
  })

  it('sends a plain choice when every field takes the same side', () => {
    expect(buildResolution(measureConflict, { pb_mm: 'telephone', poids_kg: 'telephone' })).toEqual({
      choix: 'telephone',
    })
  })

  it('sends a full field-by-field merge otherwise, with the comment', () => {
    expect(buildResolution(measureConflict, { pb_mm: 'telephone', poids_kg: 'serveur' }, ' Mesure refaite ')).toEqual({
      choix: 'fusion',
      donnees: { pb_mm: 118, poids_kg: '8.40' },
      commentaire: 'Mesure refaite',
    })
  })

  it('copes with a deletion, whose phone data is an empty object', () => {
    expect(differingFields({ ...measureConflict, operation: 'delete', donnees_telephone: {} })).toEqual([
      'pb_mm',
      'poids_kg',
      'taille_cm',
    ])
  })

  it('shows missing values as a dash', () => {
    expect(displayValue(null)).toBe('—')
    expect(displayValue('')).toBe('—')
    expect(displayValue(0)).toBe('0')
  })
})
