import { http } from './http'

/** @typedef {import('./types').Referral} Referral */
/** @typedef {import('./types').ReferralStatus} ReferralStatus */
/** @typedef {import('./types').StatusChange} StatusChange */
/** @typedef {import('./types').Uuid} Uuid */

export const referralsApi = {
  /**
   * The centre's queue (envoye and recu), red first then oldest.
   * @returns {Promise<Referral[]>}
   */
  incoming() {
    return http.getAll('/api/referrals/incoming/')
  },

  /**
   * @param {ReferralStatus} status
   * @returns {Promise<Referral[]>}
   */
  list(status) {
    return http.getAll('/api/referrals/', { status })
  },

  /**
   * @param {Uuid} id
   * @returns {Promise<Referral>}
   */
  get(id) {
    return http.get(`/api/referrals/${id}/`)
  },

  /**
   * @param {string} code
   * @returns {Promise<Referral | null>}
   */
  async findByCode(code) {
    const wanted = normaliseCode(code)
    const list = await http.getAll('/api/referrals/', { code: code.trim().replace(/\s+/g, '') })
    // The filter is exact on the server; checked again here in case of spaces or case.
    return list.find((r) => normaliseCode(r.code_unique) === wanted) ?? null
  },

  /**
   * @param {Uuid} childId
   * @returns {Promise<Referral[]>}
   */
  forChild(childId) {
    return http.getAll('/api/referrals/', { enfant: childId })
  },

  /**
   * @param {Uuid} id
   * @param {StatusChange} change
   * @returns {Promise<Referral>}
   */
  changeStatus(id, change) {
    return http.post(`/api/referrals/${id}/status/`, change)
  },
}

/**
 * @param {string} code
 * @returns {string}
 */
export function normaliseCode(code) {
  return code.trim().toUpperCase().replace(/\s+/g, '')
}
