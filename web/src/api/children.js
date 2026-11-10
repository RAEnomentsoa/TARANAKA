import { http } from './http'

/** @typedef {import('./types').Child} Child */
/** @typedef {import('./types').FoodLog} FoodLog */
/** @typedef {import('./types').Measurement} Measurement */
/** @typedef {import('./types').Uuid} Uuid */
/** @typedef {import('./types').Vaccination} Vaccination */

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

  /**
   * Vaccines recorded in the app (mother or health worker), by dose code.
   * @param {Uuid} childId
   * @returns {Promise<Vaccination[]>}
   */
  vaccinations(childId) {
    return http.getAll('/api/vaccinations/', { enfant: childId })
  },

  /**
   * The mother's daily food logs for this child.
   * @param {Uuid} childId
   * @returns {Promise<FoodLog[]>}
   */
  foodLogs(childId) {
    return http.getAll('/api/food-logs/', { enfant: childId })
  },
}
