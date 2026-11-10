/** @typedef {import('@/api/types').ConflictResolution} ConflictResolution */
/** @typedef {import('@/api/types').SyncConflict} SyncConflict */

/** @typedef {'serveur' | 'telephone'} Side */

/** Sync bookkeeping fields: not clinical, never arbitrated by a person. */
const TECHNICAL_FIELDS = new Set(['id', 'version', 'created_at', 'updated_at', 'device_id', 'deleted_at'])

/**
 * @param {unknown} a
 * @param {unknown} b
 * @returns {boolean}
 */
function same(a, b) {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
}

/**
 * @param {SyncConflict} conflict
 * @param {Side} side
 * @returns {Record<string, unknown>}
 */
export function sideData(conflict, side) {
  return (side === 'serveur' ? conflict.donnees_serveur : conflict.donnees_telephone) ?? {}
}

/**
 * Fields whose values differ between the two versions, in a stable order.
 * @param {SyncConflict} conflict
 * @returns {string[]}
 */
export function differingFields(conflict) {
  const server = sideData(conflict, 'serveur')
  const phone = sideData(conflict, 'telephone')
  const keys = new Set([...Object.keys(server), ...Object.keys(phone)])
  return [...keys].filter((key) => !TECHNICAL_FIELDS.has(key) && !same(server[key], phone[key])).sort()
}

/**
 * A deletion can only be kept or refused as a whole; otherwise one side
 * everywhere gives a plain choice and a mix gives a field-by-field merge.
 * @param {SyncConflict} conflict
 * @param {Record<string, Side>} choices
 * @param {*} [commentaire='']
 * @returns {ConflictResolution}
 */
export function buildResolution(conflict, choices, commentaire = '') {
  const comment = commentaire.trim() ? { commentaire: commentaire.trim() } : {}
  const fields = differingFields(conflict)
  const sides = new Set(fields.map((field) => choices[field]))
  if (sides.size === 1) {
    const [side] = [...sides]
    if (side) return { choix: side, ...comment }
  }
  /** @type {Record<string, unknown>} */
  const donnees = {}
  for (const field of fields) donnees[field] = sideData(conflict, choices[field] ?? 'serveur')[field]
  return { choix: 'fusion', donnees, ...comment }
}

/**
 * @param {unknown} value
 * @returns {string}
 */
export function displayValue(value) {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'object') return JSON.stringify(value)
  return String(value)
}
