import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { authApi } from '@/api/auth'
import { ApiError, isApiError } from '@/api/errors'
import { http } from '@/api/http'
import { tokenStorage } from '@/api/tokenStorage'
import type { LoginResponse, Utilisateur } from '@/api/types'
import { can as userCan, homeRouteName, rolesOf, type Permission } from '@/utils/roles'

/**
 * Two-factor login (D12, endpoint.md "Double authentification"):
 * - credentials: identifier and PIN;
 * - verification: the account has 2FA, the login is sent again with code_totp;
 * - enrolement: the account has no 2FA yet. The dashboard requires it for
 *   every web profile, even when the server does not (TOTP_OBLIGATOIRE off).
 */
export type LoginStep = 'credentials' | 'verification' | 'enrolement'

/** The profile has no web screen (community agent, beneficiary). */
export class NoWebAccessError extends Error {
  constructor() {
    super('no_web_access')
    this.name = 'NoWebAccessError'
  }
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<Utilisateur | null>(null)
  const step = ref<LoginStep>('credentials')
  const otpauthUri = ref<string | null>(null)
  const restored = ref(false)

  // Kept in memory only, between the two login steps.
  let pendingCredentials: { identifiant: string; pin: string } | null = null
  // Signed in, but 2FA still to set up: not a usable session yet.
  let pendingUser: Utilisateur | null = null

  const isAuthenticated = computed(() => user.value !== null)
  const roles = computed(() => rolesOf(user.value))
  const homeRoute = computed(() => homeRouteName(user.value))
  const displayName = computed(() => (user.value ? `${user.value.prenom} ${user.value.nom}`.trim() : ''))

  function can(permission: Permission): boolean {
    return userCan(user.value, permission)
  }

  function resetChallenge(): void {
    step.value = 'credentials'
    otpauthUri.value = null
    pendingCredentials = null
    pendingUser = null
  }

  async function discardSession(): Promise<void> {
    const refresh = tokenStorage.getRefresh()
    tokenStorage.clear()
    if (refresh) await authApi.logout(refresh).catch(() => undefined)
  }

  /** Does this signed-in account still have to turn 2FA on? */
  async function needsEnrolment(result: Pick<LoginResponse, 'totp_a_configurer'>): Promise<boolean> {
    if (result.totp_a_configurer) return true
    const state = await authApi.totpState()
    return state.requise_pour_ce_profil && !state.active
  }

  async function startEnrolment(): Promise<void> {
    const setup = await authApi.totpSetup()
    otpauthUri.value = setup.uri
    step.value = 'enrolement'
  }

  async function afterLogin(result: LoginResponse): Promise<LoginStep | 'done'> {
    tokenStorage.save(result)
    if (rolesOf(result.utilisateur).length === 0) {
      await discardSession()
      resetChallenge()
      throw new NoWebAccessError()
    }
    pendingCredentials = null
    if (await needsEnrolment(result)) {
      pendingUser = result.utilisateur
      await startEnrolment()
      return 'enrolement'
    }
    user.value = result.utilisateur
    resetChallenge()
    return 'done'
  }

  /** Step 1. Returns the next step of the login. */
  async function submitCredentials(identifiant: string, pin: string): Promise<LoginStep | 'done'> {
    try {
      return await afterLogin(await authApi.login({ identifiant, pin }))
    } catch (error) {
      if (isApiError(error) && error.code === 'totp_requis') {
        pendingCredentials = { identifiant, pin }
        step.value = 'verification'
        return 'verification'
      }
      throw error
    }
  }

  /** Step 2: the 6-digit code, to log in or to confirm the authenticator app. */
  async function submitTotp(code: string): Promise<void> {
    if (step.value === 'verification' && pendingCredentials) {
      await afterLogin(await authApi.login({ ...pendingCredentials, code_totp: code }))
      return
    }
    if (step.value === 'enrolement' && pendingUser) {
      // Activation closes the other sessions and returns new tokens.
      tokenStorage.save(await authApi.totpActivate(code))
      user.value = pendingUser
      resetChallenge()
      return
    }
    throw new ApiError({ kind: 'session_expired', status: 401 })
  }

  /** On page load: a stored refresh token gives back a complete session only. */
  async function restore(): Promise<void> {
    if (restored.value) return
    restored.value = true
    if (user.value || !tokenStorage.getRefresh()) return
    try {
      if (!(await http.refreshTokens())) throw new Error('refresh failed')
      const me = await authApi.me()
      if (rolesOf(me).length === 0 || (await needsEnrolment({ totp_a_configurer: false }))) {
        throw new Error('incomplete session')
      }
      user.value = me
    } catch {
      await discardSession()
      user.value = null
    }
  }

  async function logout(): Promise<void> {
    user.value = null
    resetChallenge()
    await discardSession()
  }

  /** Called when the server refused every token: forget the user locally. */
  function expire(): void {
    tokenStorage.clear()
    user.value = null
    resetChallenge()
  }

  return {
    user,
    step,
    otpauthUri,
    isAuthenticated,
    roles,
    homeRoute,
    displayName,
    can,
    submitCredentials,
    submitTotp,
    resetChallenge,
    restore,
    logout,
    expire,
  }
})
