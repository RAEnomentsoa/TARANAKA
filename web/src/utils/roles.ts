import type { Utilisateur } from '@/api/types'

/**
 * Role-based access on the dashboard. The server stays the authority (RBAC
 * in Backend_serveur/comptes/permissions.py); this only decides which screens
 * a profile sees, so nobody lands on a page that will answer 403.
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

const STAFF: Permission[] = [
  'referrals:read',
  'referrals:update',
  'children:read',
  'care:write',
  'discharge:write',
  'conflicts:resolve',
]
const SUPERVISOR: Permission[] = ['stats:read']

/** Profile code → web roles. "superviseur" is proposed in docs/API_ISSUES.md. */
const ROLES_BY_PROFILE: Record<string, WebRole[]> = {
  agent_csb: ['staff'],
  superviseur: ['supervisor'],
  admin: ['staff', 'supervisor'],
}

const PERMISSIONS_BY_ROLE: Record<WebRole, Permission[]> = {
  staff: STAFF,
  supervisor: SUPERVISOR,
}

export function rolesOf(user: Pick<Utilisateur, 'profile'> | null): WebRole[] {
  if (!user) return []
  return ROLES_BY_PROFILE[user.profile.code] ?? []
}

export function permissionsOf(user: Pick<Utilisateur, 'profile'> | null): Set<Permission> {
  return new Set(rolesOf(user).flatMap((role) => PERMISSIONS_BY_ROLE[role]))
}

export function can(user: Pick<Utilisateur, 'profile'> | null, permission: Permission): boolean {
  return permissionsOf(user).has(permission)
}

/** First screen after login, by role. */
export function homeRouteName(user: Pick<Utilisateur, 'profile'> | null): string {
  const roles = rolesOf(user)
  if (roles.includes('staff')) return 'referrals'
  if (roles.includes('supervisor')) return 'stats'
  return 'no-access'
}
