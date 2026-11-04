import { http } from './http'
import type { Referral, ReferralStatus, StatusChange, Uuid } from './types'

export const referralsApi = {
  list(status?: ReferralStatus): Promise<Referral[]> {
    return http.getAll<Referral>('/api/referrals/', { status })
  },

  get(id: Uuid): Promise<Referral> {
    return http.get<Referral>(`/api/referrals/${id}/`)
  },

  /**
   * The backend has no filter on the code yet (docs/API_ISSUES.md): the
   * proposed "code_unique" parameter is sent, and the answer is checked here.
   */
  async findByCode(code: string): Promise<Referral | null> {
    const wanted = normaliseCode(code)
    const list = await http.getAll<Referral>('/api/referrals/', { code_unique: code.trim() })
    return list.find((r) => normaliseCode(r.code_unique) === wanted) ?? null
  },

  /** No "enfant" filter on the backend yet: filtered here. */
  async forChild(childId: Uuid): Promise<Referral[]> {
    const list = await http.getAll<Referral>('/api/referrals/', { enfant: childId })
    return list.filter((r) => r.enfant_id === childId)
  },

  changeStatus(id: Uuid, change: StatusChange): Promise<Referral> {
    return http.post<Referral>(`/api/referrals/${id}/status/`, change)
  },
}

export function normaliseCode(code: string): string {
  return code.trim().toUpperCase().replace(/\s+/g, '')
}
