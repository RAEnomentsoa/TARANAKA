import { http } from './http'
import type { Referral, ReferralStatus, StatusChange, Uuid } from './types'

export const referralsApi = {
  /** The centre's queue (envoye and recu), red first then oldest. */
  incoming(): Promise<Referral[]> {
    return http.getAll<Referral>('/api/referrals/incoming/')
  },

  list(status: ReferralStatus): Promise<Referral[]> {
    return http.getAll<Referral>('/api/referrals/', { status })
  },

  get(id: Uuid): Promise<Referral> {
    return http.get<Referral>(`/api/referrals/${id}/`)
  },

  async findByCode(code: string): Promise<Referral | null> {
    const wanted = normaliseCode(code)
    const list = await http.getAll<Referral>('/api/referrals/', { code: code.trim().replace(/\s+/g, '') })
    // The filter is exact on the server; checked again here in case of spaces or case.
    return list.find((r) => normaliseCode(r.code_unique) === wanted) ?? null
  },

  forChild(childId: Uuid): Promise<Referral[]> {
    return http.getAll<Referral>('/api/referrals/', { enfant: childId })
  },

  changeStatus(id: Uuid, change: StatusChange): Promise<Referral> {
    return http.post<Referral>(`/api/referrals/${id}/status/`, change)
  },
}

export function normaliseCode(code: string): string {
  return code.trim().toUpperCase().replace(/\s+/g, '')
}
