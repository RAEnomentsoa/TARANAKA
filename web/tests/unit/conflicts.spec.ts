import { describe, expect, it } from 'vitest'
import type { SyncConflict } from '@/api/types'
import { buildResolution, differingFields, displayValue } from '@/utils/conflicts'

const conflict: SyncConflict = {
  id: 7,
  table_nom: 'mesure',
  ligne_id: '22222222-2222-4222-8222-222222222222',
  date_creation: '2026-11-04T09:00:00Z',
  version_serveur: {
    version: 3,
    device_id: 'phone-a',
    date: '2026-11-04T08:00:00Z',
    donnees: { poids_kg: '8.40', taille_cm: '72.0', pb_mm: 112, version: 3, updated_at: 'x' },
  },
  version_appareil: {
    version: 3,
    device_id: 'phone-b',
    date: '2026-11-04T08:30:00Z',
    donnees: { poids_kg: '8.10', taille_cm: '72.0', pb_mm: 118, version: 3, updated_at: 'y' },
  },
}

describe('conflict arbitration', () => {
  it('lists only clinical fields that differ', () => {
    expect(differingFields(conflict)).toEqual(['pb_mm', 'poids_kg'])
  })

  it('sends a plain choice when every field takes the same side', () => {
    expect(buildResolution(conflict, { pb_mm: 'appareil', poids_kg: 'appareil' })).toEqual({ choix: 'appareil' })
  })

  it('sends a full field-by-field merge otherwise', () => {
    expect(buildResolution(conflict, { pb_mm: 'appareil', poids_kg: 'serveur' })).toEqual({
      choix: 'fusion',
      donnees: { pb_mm: 118, poids_kg: '8.40' },
    })
  })

  it('shows missing values as a dash', () => {
    expect(displayValue(null)).toBe('—')
    expect(displayValue('')).toBe('—')
    expect(displayValue(0)).toBe('0')
  })
})
