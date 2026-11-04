import type { Composer } from 'vue-i18n'
import { isApiError } from '@/api/errors'

/** A translated message for any error thrown by the API layer. */
export function errorMessage(t: Composer['t'], error: unknown): string {
  if (!isApiError(error)) return t('errors.unknown')
  return t(`errors.${error.kind}`)
}

/** Messages of the login steps (endpoint.md, POST /api/auth/login/ and 2FA). */
export function loginErrorMessage(t: Composer['t'], error: unknown): string {
  if (error instanceof Error && error.name === 'NoWebAccessError') return t('login.errors.noWebAccess')
  if (!isApiError(error)) return t('errors.unknown')
  switch (error.code) {
    case 'totp_invalide':
      return t('login.errors.totpInvalid')
    case 'identifiants_incorrects':
      return t('login.errors.credentials')
    case 'profil_inconnu':
      return t('login.errors.noWebAccess')
    case 'compte_bloque': {
      const seconds = (error.body as { secondes_restantes?: number | null } | null)?.secondes_restantes
      return typeof seconds === 'number'
        ? t('login.errors.locked', { minutes: Math.max(1, Math.ceil(seconds / 60)) })
        : t('login.errors.lockedAdmin')
    }
  }
  if (error.kind === 'unauthorized') return t('login.errors.credentials')
  if (error.kind === 'throttled') return t('login.errors.throttled')
  return errorMessage(t, error)
}
