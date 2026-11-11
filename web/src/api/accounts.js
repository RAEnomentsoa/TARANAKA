import { http } from './http'

/** @typedef {import('./types').AccessRequestForm} AccessRequestForm */
/** @typedef {import('./types').AccessRequest} AccessRequest */
/** @typedef {import('./types').AccessRequestCorrections} AccessRequestCorrections */
/** @typedef {import('./types').AccessRequestOptions} AccessRequestOptions */
/** @typedef {import('./types').AccessRequestStatus} AccessRequestStatus */
/** @typedef {import('./types').AgentAccount} AgentAccount */
/** @typedef {import('./types').NewAgent} NewAgent */

/**
 * Access requests (D15): the public form on the login page, and the admin's
 * review. Nothing is created in the accounts before the admin approves.
 */
export const accessRequestsApi = {
  /**
   * Public: regions and centres (names and types only) for the form.
   * @returns {Promise<AccessRequestOptions>}
   */
  options() {
    return http.get('/api/auth/access-request/options/', undefined, { auth: false })
  },
  /**
   * Public: send a request. The PIN is chosen here and kept hashed.
   * @param {AccessRequestForm} form
   * @returns {Promise<AccessRequest>}
   */
  submit(form) {
    return http.post('/api/auth/access-request/', form, { auth: false })
  },
  /**
   * Admin only.
   * @param {AccessRequestStatus} [statut]
   * @returns {Promise<AccessRequest[]>}
   */
  list(statut) {
    return http.getAll('/api/access-requests/', { statut })
  },
  /**
   * Admin only. Corrections are optional: by default the account gets what
   * the person asked for.
   * @param {string} id
   * @param {AccessRequestCorrections} [corrections={}]
   * @returns {Promise<AccessRequest>}
   */
  approve(id, corrections = {}) {
    return http.post(`/api/access-requests/${id}/approve/`, corrections)
  },
  /**
   * Admin only.
   * @param {string} id
   * @param {string} motif
   * @returns {Promise<AccessRequest>}
   */
  refuse(id, motif) {
    return http.post(`/api/access-requests/${id}/refuse/`, { motif })
  },
}

/**
 * The admin's view of every account. "Deleting" is deactivating: an account
 * stays linked to its referrals and to the audit log, so it is never erased
 * from here (the legal erasure is a separate procedure).
 */
export const accountsApi = {
  /**
   * @param {import('./types').AccountQuery} [query={}]
   * @returns {Promise<AgentAccount[]>}
   */
  list(query = {}) {
    return http.getAll('/api/profiles/', { ...query })
  },
  /**
   * @param {string} id
   * @param {import('./types').AccountChanges} changes
   * @returns {Promise<AgentAccount>}
   */
  update(id, changes) {
    return http.patch(`/api/profiles/${id}/`, changes)
  },
  /**
   * @param {string} id
   * @param {string} pin
   * @returns {Promise<unknown>}
   */
  resetPin(id, pin) {
    return http.post(`/api/profiles/${id}/reset-pin/`, { nouveau_pin: pin })
  },
  /**
   * Lost phone: two-factor login is turned off, to be set up again.
   * @param {string} id
   * @returns {Promise<unknown>}
   */
  resetTwoFactor(id) {
    return http.post(`/api/profiles/${id}/reset-2fa/`)
  },
}

/**
 * The supervisor's community agents (spec §2, §8, D1): the server only lists
 * the ASC accounts of the supervisor's region and creates ASCs there.
 */
export const agentsApi = {
  /** @returns {Promise<AgentAccount[]>} */
  list() {
    return http.getAll('/api/profiles/')
  },
  /**
   * @param {NewAgent} agent
   * @returns {Promise<AgentAccount>}
   */
  create(agent) {
    return http.post('/api/profiles/', agent)
  },
  /**
   * New PIN for a forgotten or blocked account. Also unblocks it.
   * @param {string} id
   * @param {string} pin
   * @returns {Promise<unknown>}
   */
  resetPin(id, pin) {
    return http.post(`/api/profiles/${id}/reset-pin/`, { nouveau_pin: pin })
  },
}
