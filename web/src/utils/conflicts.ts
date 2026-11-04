import type { ConflictResolution, SyncConflict } from '@/api/types'

export type Side = 'serveur' | 'telephone'

/** Sync bookkeeping fields: not clinical, never arbitrated by a person. */
const TECHNICAL_FIELDS = new Set(['id', 'version', 'created_at', 'updated_at', 'device_id', 'deleted_at'])

function same(a: unknown, b: unknown): boolean {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
}

export function sideData(conflict: SyncConflict, side: Side): Record<string, unknown> {
  return (side === 'serveur' ? conflict.donnees_serveur : conflict.donnees_telephone) ?? {}
}

/** Fields whose values differ between the two versions, in a stable order. */
export function differingFields(conflict: SyncConflict): string[] {
  const server = sideData(conflict, 'serveur')
  const phone = sideData(conflict, 'telephone')
  const keys = new Set([...Object.keys(server), ...Object.keys(phone)])
  return [...keys].filter((key) => !TECHNICAL_FIELDS.has(key) && !same(server[key], phone[key])).sort()
}

/**
 * A deletion can only be kept or refused as a whole; otherwise one side
 * everywhere gives a plain choice and a mix gives a field-by-field merge.
 */
export function buildResolution(conflict: SyncConflict, choices: Record<string, Side>, commentaire = ''): ConflictResolution {
  const comment = commentaire.trim() ? { commentaire: commentaire.trim() } : {}
  const fields = differingFields(conflict)
  const sides = new Set(fields.map((field) => choices[field]))
  if (sides.size === 1) {
    const [side] = [...sides]
    if (side) return { choix: side, ...comment }
  }
  const donnees: Record<string, unknown> = {}
  for (const field of fields) donnees[field] = sideData(conflict, choices[field] ?? 'serveur')[field]
  return { choix: 'fusion', donnees, ...comment }
}

export function displayValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'object') return JSON.stringify(value)
  return String(value)
}
