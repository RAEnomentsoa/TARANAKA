import { http } from './http'

/** @typedef {import('./types').Child} Child */
/** @typedef {import('./types').Measurement} Measurement */
/** @typedef {import('./types').Uuid} Uuid */

export const childrenApi = {
  /**
   * @param {Uuid} id
   * @returns {Promise<Child>}
   */
  get(id) {
    return http.get(`/api/children/${id}/`)
  },

  /**
   * @param {Uuid} childId
   * @returns {Promise<Measurement[]>}
   */
  measurements(childId) {
    return http.getAll(`/api/children/${childId}/measurements/`)
  },

  /**
   * @param {Uuid} id
   * @returns {Promise<Measurement>}
   */
  measurement(id) {
    return http.get(`/api/measurements/${id}/`)
  },
}
