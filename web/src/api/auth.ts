import { http } from './http'
import type { LoginResponse, LoginSuccess, Utilisateur } from './types'

export const authApi = {
  /** Existing. With TOTP (proposed), the answer is a challenge instead of tokens. */
  login(identifiant: string, pin: string): Promise<LoginResponse> {
    return http.post<LoginResponse>('/api/auth/login/', { identifiant, pin }, { auth: false })
  },

  /** Proposed: second step, a 6-digit code from the authenticator app. */
  verifyTotp(jeton: string, code: string): Promise<LoginSuccess> {
    return http.post<LoginSuccess>(
      '/api/auth/totp/verifier/',
      { jeton, code },
      { auth: false, proposed: true },
    )
  },

  /** Proposed: first use, confirms the authenticator app was set up. */
  enrollTotp(jeton: string, code: string): Promise<LoginSuccess> {
    return http.post<LoginSuccess>(
      '/api/auth/totp/activer/',
      { jeton, code },
      { auth: false, proposed: true },
    )
  },

  me(): Promise<Utilisateur> {
    return http.get<Utilisateur>('/api/auth/me/')
  },

  logout(refresh: string): Promise<unknown> {
    return http.post('/api/auth/logout/', { refresh }, { auth: false })
  },
}
