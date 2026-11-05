import { http } from './http'

/** @typedef {import('./types').LoginRequest} LoginRequest */
/** @typedef {import('./types').LoginResponse} LoginResponse */
/** @typedef {import('./types').TokenRenewal} TokenRenewal */
/** @typedef {import('./types').TotpSetup} TotpSetup */
/** @typedef {import('./types').TotpState} TotpState */
/** @typedef {import('./types').Utilisateur} Utilisateur */

export const authApi = {
  /**
   * 401 "totp_requis": send again with code_totp.
   * @param {LoginRequest} request
   * @returns {Promise<LoginResponse>}
   */
  login(request) {
    return http.post('/api/auth/login/', request, { auth: false })
  },

  /** @returns {Promise<Utilisateur>} */
  me() {
    return http.get('/api/auth/me/')
  },

  /**
   * @param {string} refresh
   * @returns {Promise<unknown>}
   */
  logout(refresh) {
    return http.post('/api/auth/logout/', { refresh }, { auth: false })
  },

  /** @returns {Promise<TotpState>} */
  totpState() {
    return http.get('/api/auth/2fa/')
  },

  /**
   * A new secret: show its URI as a QR code. 400 "totp_deja_actif" if already on.
   * @returns {Promise<TotpSetup>}
   */
  totpSetup() {
    return http.post('/api/auth/2fa/setup/')
  },

  /**
   * Turns 2FA on, closes the other sessions and returns new tokens.
   * @param {string} code
   * @returns {Promise<TokenRenewal>}
   */
  totpActivate(code) {
    return http.post('/api/auth/2fa/activate/', { code })
  },
}
