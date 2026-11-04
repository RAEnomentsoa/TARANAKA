import type { Composer } from 'vue-i18n'
import { isApiError } from '@/api/errors'

/** A translated message for any error thrown by the API layer. */
export function errorMessage(t: Composer['t'], error: unknown): string {
  if (!isApiError(error)) return t('errors.unknown')
  return t(`errors.${error.kind}`)
}

/** Messages specific to the login steps (endpoint.md, section login). */
export function loginErrorMessage(t: Composer['t'], error: unknown, step: 'credentials' | 'totp'): string {
  if (error instanceof Error && error.name === 'TotpNotOfferedError') return t('login.errors.totpNotOffered')
  if (!isApiError(error)) return t('errors.unknown')
  if (step === 'totp') {
    if (error.kind === 'not_implemented') return t('login.errors.totpUnavailable')
    if (error.kind === 'validation' || error.kind === 'unauthorized') return t('login.errors.totpInvalid')
  }
  switch (error.kind) {
    case 'unauthorized':
      return t('login.errors.credentials')
    case 'locked': {
      const seconds = (error.body as { secondes_restantes?: number | null } | null)?.secondes_restantes
      return typeof seconds === 'number'
        ? t('login.errors.locked', { minutes: Math.max(1, Math.ceil(seconds / 60)) })
        : t('login.errors.lockedAdmin')
    }
    case 'forbidden':
      return t('login.errors.profile')
    case 'throttled':
      return t('login.errors.throttled')
    default:
      return errorMessage(t, error)
  }
}
