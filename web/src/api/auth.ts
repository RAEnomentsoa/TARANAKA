import { http } from './http'
import type { LoginRequest, LoginResponse, TokenRenewal, TotpSetup, TotpState, Utilisateur } from './types'

export const authApi = {
  /** 401 "totp_requis": send again with code_totp. */
  login(request: LoginRequest): Promise<LoginResponse> {
    return http.post<LoginResponse>('/api/auth/login/', request, { auth: false })
  },

  me(): Promise<Utilisateur> {
    return http.get<Utilisateur>('/api/auth/me/')
  },

  logout(refresh: string): Promise<unknown> {
    return http.post('/api/auth/logout/', { refresh }, { auth: false })
  },

  totpState(): Promise<TotpState> {
    return http.get<TotpState>('/api/auth/2fa/')
  },

  /** A new secret: show its URI as a QR code. 400 "totp_deja_actif" if already on. */
  totpSetup(): Promise<TotpSetup> {
    return http.post<TotpSetup>('/api/auth/2fa/setup/')
  },

  /** Turns 2FA on, closes the other sessions and returns new tokens. */
  totpActivate(code: string): Promise<TokenRenewal> {
    return http.post<TokenRenewal>('/api/auth/2fa/activate/', { code })
  },
}
