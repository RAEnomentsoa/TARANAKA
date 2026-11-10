import { isApiError } from '@/api/errors'

/** @typedef {import('vue-i18n').Composer} Composer */

/**
 * A translated message for any error thrown by the API layer.
 * @param {Composer['t']} t
 * @param {unknown} error
 * @returns {string}
 */
export function errorMessage(t, error) {
  if (!isApiError(error)) return t('errors.unknown')
  return t(`errors.${error.kind}`)
}

/**
 * Messages of the login steps (endpoint.md, POST /api/auth/login/ and 2FA).
 * @param {Composer['t']} t
 * @param {unknown} error
 * @returns {string}
 */
export function loginErrorMessage(t, error) {
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
      const seconds = error.body?.secondes_restantes
      return typeof seconds === 'number'
        ? t('login.errors.locked', { minutes: Math.max(1, Math.ceil(seconds / 60)) })
        : t('login.errors.lockedAdmin')
    }
  }
  if (error.kind === 'unauthorized') return t('login.errors.credentials')
  if (error.kind === 'throttled') return t('login.errors.throttled')
  return errorMessage(t, error)
}
