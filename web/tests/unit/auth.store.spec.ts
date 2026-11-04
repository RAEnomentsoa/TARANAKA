import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { authApi } from '@/api/auth'
import { tokenStorage } from '@/api/tokenStorage'
import { config } from '@/config'
import { TotpNotOfferedError, useAuthStore } from '@/stores/auth'
import { makeUser } from '../helpers'

const success = { access: 'A', refresh: 'R', utilisateur: makeUser('agent_csb') }

describe('auth store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    tokenStorage.clear()
    config.allowLoginWithoutTotp = false
  })

  it('asks for the TOTP code, then signs in with it', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue({ double_auth: { etape: 'verification', jeton: 'J1' } })
    const verify = vi.spyOn(authApi, 'verifyTotp').mockResolvedValue(success)
    const auth = useAuthStore()

    await expect(auth.submitCredentials('0341112233', '1234')).resolves.toBe('verification')
    expect(auth.isAuthenticated).toBe(false)

    await auth.submitTotp('123456')

    expect(verify).toHaveBeenCalledWith('J1', '123456')
    expect(auth.isAuthenticated).toBe(true)
    expect(auth.step).toBe('credentials')
    expect(tokenStorage.getAccess()).toBe('A')
    expect(auth.homeRoute).toBe('referrals')
  })

  it('confirms the authenticator app on first use', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue({
      double_auth: { etape: 'enrolement', jeton: 'J2', otpauth_uri: 'otpauth://totp/TARANAKA:x?secret=ABCD' },
    })
    const enroll = vi.spyOn(authApi, 'enrollTotp').mockResolvedValue(success)
    const auth = useAuthStore()

    await auth.submitCredentials('x', '1234')
    expect(auth.otpauthUri).toContain('secret=ABCD')
    await auth.submitTotp('654321')

    expect(enroll).toHaveBeenCalledWith('J2', '654321')
  })

  it('refuses a login that skipped the second factor and closes that session', async () => {
    vi.spyOn(authApi, 'login').mockResolvedValue(success)
    const logout = vi.spyOn(authApi, 'logout').mockResolvedValue({})
    const auth = useAuthStore()

    await expect(auth.submitCredentials('x', '1234')).rejects.toBeInstanceOf(TotpNotOfferedError)

    expect(logout).toHaveBeenCalledWith('R')
    expect(auth.isAuthenticated).toBe(false)
    expect(tokenStorage.getRefresh()).toBeNull()
  })

  it('accepts it only when the development flag allows it', async () => {
    config.allowLoginWithoutTotp = true
    vi.spyOn(authApi, 'login').mockResolvedValue(success)
    const auth = useAuthStore()

    await expect(auth.submitCredentials('x', '1234')).resolves.toBe('done')
    expect(auth.isAuthenticated).toBe(true)
  })

  it('blacklists the refresh token on logout', async () => {
    const logout = vi.spyOn(authApi, 'logout').mockResolvedValue({})
    tokenStorage.save({ access: 'A', refresh: 'R9' })
    const auth = useAuthStore()

    await auth.logout()

    expect(logout).toHaveBeenCalledWith('R9')
    expect(tokenStorage.getAccess()).toBeNull()
  })

  it('derives permissions from the profile', () => {
    const auth = useAuthStore()
    auth.user = makeUser('superviseur')
    expect(auth.can('stats:read')).toBe(true)
    expect(auth.can('referrals:read')).toBe(false)
    expect(auth.homeRoute).toBe('stats')

    auth.user = makeUser('asc')
    expect(auth.homeRoute).toBe('no-access')
  })
})
