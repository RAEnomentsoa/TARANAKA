import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { authApi } from '@/api/auth'
import { ApiError } from '@/api/errors'
import { tokenStorage } from '@/api/tokenStorage'
import type { LoginResponse, TotpState } from '@/api/types'
import { NoWebAccessError, useAuthStore } from '@/stores/auth'
import { makeUser } from '../helpers'

const success = (code = 'agent_csb', extra: Partial<LoginResponse> = {}): LoginResponse => ({
  access: 'A',
  refresh: 'R',
  utilisateur: makeUser(code),
  totp_a_configurer: false,
  ...extra,
})
const totpOn: TotpState = { active: true, requise_pour_ce_profil: true, obligatoire: false, a_configurer: false }
const totpOff: TotpState = { active: false, requise_pour_ce_profil: true, obligatoire: false, a_configurer: false }
const totpRequired = new ApiError({ kind: 'unauthorized', status: 401, code: 'totp_requis' })

describe('auth store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    tokenStorage.clear()
  })

  it('asks for the code when the server answers totp_requis, then logs in with it', async () => {
    const login = vi.spyOn(authApi, 'login').mockRejectedValueOnce(totpRequired).mockResolvedValueOnce(success())
    vi.spyOn(authApi, 'totpState').mockResolvedValue(totpOn)
    const auth = useAuthStore()

    await expect(auth.submitCredentials('0341112233', '1234')).resolves.toBe('verification')
    expect(auth.isAuthenticated).toBe(false)
    expect(tokenStorage.getAccess()).toBeNull()

    await auth.submitTotp('123456')

    expect(login).toHaveBeenLastCalledWith({ identifiant: '0341112233', pin: '1234', code_totp: '123456' })
    expect(auth.isAuthenticated).toBe(true)
    expect(auth.step).toBe('credentials')
    expect(auth.homeRoute).toBe('referrals')
  })

  it('makes a web account without 2FA set it up before entering', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue(success())
    vi.spyOn(authApi, 'totpState').mockResolvedValue(totpOff)
    vi.spyOn(authApi, 'totpSetup').mockResolvedValue({ secret: 'ABCD', uri: 'otpauth://totp/TARANAKA:x?secret=ABCD' })
    const activate = vi.spyOn(authApi, 'totpActivate').mockResolvedValue({ detail: 'ok', access: 'A2', refresh: 'R2' })
    const auth = useAuthStore()

    await expect(auth.submitCredentials('x', '1234')).resolves.toBe('enrolement')
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.otpauthUri).toContain('secret=ABCD')

    await auth.submitTotp('654321')

    expect(activate).toHaveBeenCalledWith('654321')
    expect(auth.isAuthenticated).toBe(true)
    // Activation closes the other sessions: the new tokens replace the old ones.
    expect(tokenStorage.getAccess()).toBe('A2')
    expect(tokenStorage.getRefresh()).toBe('R2')
  })

  it('goes straight to enrolment when the server marks the token totp_a_configurer', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue(success('superviseur', { totp_a_configurer: true }))
    const state = vi.spyOn(authApi, 'totpState')
    vi.spyOn(authApi, 'totpSetup').mockResolvedValue({ secret: 'S', uri: 'otpauth://totp/x?secret=S' })
    const auth = useAuthStore()

    await expect(auth.submitCredentials('x', '1234')).resolves.toBe('enrolement')
    expect(state).not.toHaveBeenCalled()
  })

  it('turns away a community agent and closes the session it got', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue(success('asc'))
    const logout = vi.spyOn(authApi, 'logout').mockResolvedValue({})
    const auth = useAuthStore()

    await expect(auth.submitCredentials('x', '1234')).rejects.toBeInstanceOf(NoWebAccessError)
    expect(logout).toHaveBeenCalledWith('R')
    expect(tokenStorage.getRefresh()).toBeNull()
    expect(auth.isAuthenticated).toBe(false)
  })

  it('passes a wrong code on (it counts as a failed attempt on the server)', async () => {
    vi.spyOn(authApi, 'login')
      .mockRejectedValueOnce(totpRequired)
      .mockRejectedValueOnce(new ApiError({ kind: 'unauthorized', status: 401, code: 'totp_invalide' }))
    const auth = useAuthStore()

    await auth.submitCredentials('x', '1234')
    await expect(auth.submitTotp('000000')).rejects.toMatchObject({ code: 'totp_invalide' })
    expect(auth.step).toBe('verification')
  })

  it('does not restore a session whose 2FA was never set up', async () => {
    tokenStorage.save({ access: 'A', refresh: 'R' })
    const { http } = await import('@/api/http')
    vi.spyOn(http, 'refreshTokens').mockResolvedValue(true)
    vi.spyOn(authApi, 'me').mockResolvedValue(makeUser('agent_csb'))
    vi.spyOn(authApi, 'totpState').mockResolvedValue(totpOff)
    vi.spyOn(authApi, 'logout').mockResolvedValue({})
    const auth = useAuthStore()

    await auth.restore()

    expect(auth.isAuthenticated).toBe(false)
    expect(tokenStorage.getRefresh()).toBeNull()
  })

  it('blacklists the refresh token on logout', async () => {
    const logout = vi.spyOn(authApi, 'logout').mockResolvedValue({})
    tokenStorage.save({ access: 'A', refresh: 'R9' })
    await useAuthStore().logout()
    expect(logout).toHaveBeenCalledWith('R9')
    expect(tokenStorage.getAccess()).toBeNull()
  })

  it('derives permissions from the profile, as in the backend table', () => {
    const auth = useAuthStore()
    auth.user = makeUser('superviseur')
    expect(auth.can('stats:read')).toBe(true)
    expect(auth.can('referrals:read')).toBe(false)
    expect(auth.homeRoute).toBe('stats')

    auth.user = makeUser('admin')
    expect(auth.can('referrals:update')).toBe(true)
    expect(auth.can('discharge:write')).toBe(false) // D7: destination centre only

    auth.user = makeUser('agent_csb')
    expect(auth.can('discharge:write')).toBe(true)
    expect(auth.can('stats:read')).toBe(false)
  })
})
