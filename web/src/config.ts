/** Runtime settings, read once from the Vite environment. */
export const config = {
  /**
   * The current backend has no TOTP yet (docs/API_ISSUES.md). By default the
   * dashboard refuses a login that skipped the second factor. Set
   * VITE_ALLOW_LOGIN_WITHOUT_TOTP=true only for local development.
   */
  allowLoginWithoutTotp: import.meta.env.VITE_ALLOW_LOGIN_WITHOUT_TOTP === 'true',
  idleTimeoutMinutes: Number(import.meta.env.VITE_IDLE_TIMEOUT_MINUTES ?? 15) || 15,
}
