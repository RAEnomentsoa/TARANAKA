import type { Utilisateur } from '@/api/types'

/**
 * Role-based access on the dashboard, following the permission table of
 * Backend_serveur/docs/endpoint.md ("Qui peut faire quoi"). The server stays
 * the authority; this only decides which screens and buttons a profile sees,
 * so nobody lands on a page or an action that will answer 403.
 */
export type Permission =
  | 'referrals:read'
  | 'referrals:update'
  | 'children:read'
  | 'care:write'
  | 'discharge:write'
  | 'conflicts:resolve'
  | 'stats:read'

export type WebRole = 'staff' | 'supervisor'

const STAFF_READ: Permission[] = ['referrals:read', 'children:read']
const STAFF_WRITE: Permission[] = ['referrals:update', 'care:write', 'conflicts:resolve']

const PERMISSIONS_BY_PROFILE: Record<string, Permission[]> = {
  // Nurse or doctor of a CSB, CRENAS or CRENI: the only one who may discharge.
  agent_csb: [...STAFF_READ, ...STAFF_WRITE, 'discharge:write'],
  // Aggregated statistics only: never an individual record (D1).
  superviseur: ['stats:read'],
  // Everything except the discharge, reserved to the destination centre (D7).
  admin: [...STAFF_READ, ...STAFF_WRITE, 'stats:read'],
}

export function permissionsOf(user: Pick<Utilisateur, 'profile'> | null): Set<Permission> {
  return new Set(user ? (PERMISSIONS_BY_PROFILE[user.profile.code] ?? []) : [])
}

export function can(user: Pick<Utilisateur, 'profile'> | null, permission: Permission): boolean {
  return permissionsOf(user).has(permission)
}

export function rolesOf(user: Pick<Utilisateur, 'profile'> | null): WebRole[] {
  const permissions = permissionsOf(user)
  const roles: WebRole[] = []
  if (permissions.has('referrals:read')) roles.push('staff')
  if (permissions.has('stats:read')) roles.push('supervisor')
  return roles
}

/** First screen after login, by role. */
export function homeRouteName(user: Pick<Utilisateur, 'profile'> | null): string {
  const roles = rolesOf(user)
  if (roles.includes('staff')) return 'referrals'
  if (roles.includes('supervisor')) return 'stats'
  return 'no-access'
}
