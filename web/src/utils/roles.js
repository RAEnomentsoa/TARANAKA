/** @typedef {import('@/api/types').Utilisateur} Utilisateur */

/**
 * Role-based access on the dashboard, following the permission table of
 * Backend_serveur/docs/endpoint.md ("Qui peut faire quoi"). The server stays
 * the authority; this only decides which screens and buttons a profile sees,
 * so nobody lands on a page or an action that will answer 403.
 * @typedef {(
 *   | 'referrals:read'
 *   | 'referrals:update'
 *   | 'children:read'
 *   | 'care:write'
 *   | 'discharge:write'
 *   | 'conflicts:resolve'
 *   | 'stats:read'
 * )} Permission
 */

/** @typedef {'staff' | 'supervisor'} WebRole */

/** @type {Permission[]} */
const STAFF_READ = ['referrals:read', 'children:read']
/** @type {Permission[]} */
const STAFF_WRITE = ['referrals:update', 'care:write', 'conflicts:resolve']

/** @type {Record<string, Permission[]>} */
const PERMISSIONS_BY_PROFILE = {
  // Nurse or doctor of a CSB, CRENAS or CRENI: the only one who may discharge.
  agent_csb: [...STAFF_READ, ...STAFF_WRITE, 'discharge:write'],
  // Aggregated statistics only: never an individual record (D1).
  superviseur: ['stats:read'],
  // Everything except the discharge, reserved to the destination centre (D7).
  admin: [...STAFF_READ, ...STAFF_WRITE, 'stats:read'],
}

/**
 * @param {Pick<Utilisateur, 'profile'> | null} user
 * @returns {Set<Permission>}
 */
export function permissionsOf(user) {
  return new Set(user ? (PERMISSIONS_BY_PROFILE[user.profile.code] ?? []) : [])
}

/**
 * @param {Pick<Utilisateur, 'profile'> | null} user
 * @param {Permission} permission
 * @returns {boolean}
 */
export function can(user, permission) {
  return permissionsOf(user).has(permission)
}

/**
 * @param {Pick<Utilisateur, 'profile'> | null} user
 * @returns {WebRole[]}
 */
export function rolesOf(user) {
  const permissions = permissionsOf(user)
  /** @type {WebRole[]} */
  const roles = []
  if (permissions.has('referrals:read')) roles.push('staff')
  if (permissions.has('stats:read')) roles.push('supervisor')
  return roles
}

/**
 * First screen after login, by role.
 * @param {Pick<Utilisateur, 'profile'> | null} user
 * @returns {string}
 */
export function homeRouteName(user) {
  const roles = rolesOf(user)
  if (roles.includes('staff')) return 'referrals'
  if (roles.includes('supervisor')) return 'stats'
  return 'no-access'
}
