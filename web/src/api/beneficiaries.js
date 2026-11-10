import { http } from './http'

/** @typedef {import('./types').BeneficiaryDossier} BeneficiaryDossier */
/** @typedef {import('./types').BeneficiaryRow} BeneficiaryRow */
/** @typedef {import('./types').Uuid} Uuid */

/**
 * Connected beneficiaries (D16). Opening a file (get or lookup) is audited
 * on the server and makes the signed-in worker follow the woman.
 */
export const beneficiariesApi = {
  /**
   * The zone's list, filtered by name, phone, identifier or code.
   * @param {string} [q]
   * @returns {Promise<BeneficiaryRow[]>}
   */
  list(q) {
    return http.getAll('/api/beneficiaries/', { q })
  },

  /**
   * Her whole file: identity, pregnancies, danger signs, children, referrals…
   * @param {Uuid} id
   * @returns {Promise<BeneficiaryDossier>}
   */
  get(id) {
    return http.get(`/api/beneficiaries/${id}/`)
  },

  /**
   * The code she shows (typed or scanned), from any region. 404 if unknown.
   * @param {string} code
   * @returns {Promise<BeneficiaryDossier>}
   */
  lookup(code) {
    return http.post('/api/beneficiaries/lookup/', { code })
  },
}

/**
 * "k7q-m4z" → "K7QM4Z": letters and digits only, uppercase. A beneficiary
 * code has 6 of them; anything else is a name or a phone number.
 * @param {string} text
 * @returns {string | null}
 */
export function beneficiaryCode(text) {
  const code = text.replace(/[^0-9a-z]/gi, '').toUpperCase()
  return /^[0-9A-Z]{6}$/.test(code) ? code : null
}
