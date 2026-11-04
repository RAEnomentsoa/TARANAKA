import type { ConflictResolution, SyncConflict } from '@/api/types'

export type Side = 'serveur' | 'appareil'

/** Sync bookkeeping fields: not clinical, never arbitrated by a person. */
const TECHNICAL_FIELDS = new Set(['id', 'version', 'created_at', 'updated_at', 'device_id', 'deleted_at'])

function same(a: unknown, b: unknown): boolean {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
}

/** Fields whose values differ between the two versions, in a stable order. */
export function differingFields(conflict: SyncConflict): string[] {
  const server = conflict.version_serveur.donnees
  const device = conflict.version_appareil.donnees
  const keys = new Set([...Object.keys(server), ...Object.keys(device)])
  return [...keys].filter((key) => !TECHNICAL_FIELDS.has(key) && !same(server[key], device[key])).sort()
}

/**
 * One side everywhere gives a plain choice; a mix gives a field-by-field
 * merge, sent in full so the server never has to guess.
 */
export function buildResolution(conflict: SyncConflict, choices: Record<string, Side>): ConflictResolution {
  const fields = differingFields(conflict)
  const sides = new Set(fields.map((field) => choices[field]))
  if (sides.size === 1) {
    const [side] = [...sides]
    if (side) return { choix: side }
  }
  const donnees: Record<string, unknown> = {}
  for (const field of fields) {
    const source = choices[field] === 'appareil' ? conflict.version_appareil : conflict.version_serveur
    donnees[field] = source.donnees[field]
  }
  return { choix: 'fusion', donnees }
}

export function displayValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'object') return JSON.stringify(value)
  return String(value)
}
