import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { authApi } from '@/api/auth'
import { ApiError } from '@/api/errors'
import { http } from '@/api/http'
import { tokenStorage } from '@/api/tokenStorage'
import type { LoginSuccess, LoginTotpChallenge, Utilisateur } from '@/api/types'
import { config } from '@/config'
import { can as userCan, homeRouteName, rolesOf, type Permission } from '@/utils/roles'

export type LoginStep = 'credentials' | 'verification' | 'enrolement'

/** Raised when the server gave tokens without asking for a TOTP code. */
export class TotpNotOfferedError extends Error {
  constructor() {
    super('totp_not_offered')
    this.name = 'TotpNotOfferedError'
  }
}

function isChallenge(value: unknown): value is LoginTotpChallenge {
  return typeof value === 'object' && value !== null && 'double_auth' in value
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<Utilisateur | null>(null)
  const step = ref<LoginStep>('credentials')
  const challengeToken = ref<string | null>(null)
  const otpauthUri = ref<string | null>(null)
  const restored = ref(false)

  const isAuthenticated = computed(() => user.value !== null)
  const roles = computed(() => rolesOf(user.value))
  const homeRoute = computed(() => homeRouteName(user.value))
  const displayName = computed(() => (user.value ? `${user.value.prenom} ${user.value.nom}`.trim() : ''))

  function can(permission: Permission): boolean {
    return userCan(user.value, permission)
  }

  function completeLogin(result: LoginSuccess): void {
    tokenStorage.save(result)
    user.value = result.utilisateur
    resetChallenge()
  }

  function resetChallenge(): void {
    step.value = 'credentials'
    challengeToken.value = null
    otpauthUri.value = null
  }

  /** Step 1. Returns the next step of the login. */
  async function submitCredentials(identifiant: string, pin: string): Promise<LoginStep | 'done'> {
    const result = await authApi.login(identifiant, pin)
    if (isChallenge(result)) {
      step.value = result.double_auth.etape
      challengeToken.value = result.double_auth.jeton
      otpauthUri.value = result.double_auth.otpauth_uri ?? null
      return step.value
    }
    if (!config.allowLoginWithoutTotp) {
      // The second factor is mandatory for health staff: close the session at once.
      await authApi.logout(result.refresh).catch(() => undefined)
      throw new TotpNotOfferedError()
    }
    completeLogin(result)
    return 'done'
  }

  /** Step 2. Checks the 6-digit code, or confirms the app on first use. */
  async function submitTotp(code: string): Promise<void> {
    if (!challengeToken.value || step.value === 'credentials') {
      throw new ApiError({ kind: 'session_expired', status: 401 })
    }
    const send = step.value === 'enrolement' ? authApi.enrollTotp : authApi.verifyTotp
    completeLogin(await send(challengeToken.value, code))
  }

  /** On page load: a stored refresh token gives back the session. */
  async function restore(): Promise<void> {
    if (restored.value) return
    restored.value = true
    if (user.value || !tokenStorage.getRefresh()) return
    try {
      if (!(await http.refreshTokens())) throw new Error('refresh failed')
      user.value = await authApi.me()
    } catch {
      tokenStorage.clear()
      user.value = null
    }
  }

  async function logout(): Promise<void> {
    const refresh = tokenStorage.getRefresh()
    tokenStorage.clear()
    user.value = null
    resetChallenge()
    if (refresh) await authApi.logout(refresh).catch(() => undefined)
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
