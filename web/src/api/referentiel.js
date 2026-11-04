import { http } from './http'

/** @typedef {import('./types').Facility} Facility */
/** @typedef {import('./types').Region} Region */

export const referentielApi = {
  /** @returns {Promise<Region[]>} */
  regions() {
    return http.getAll('/api/regions/')
  },
  /**
   * @param {number} [regionId]
   * @returns {Promise<Facility[]>}
   */
  facilities(regionId) {
    return http.getAll('/api/facilities/', { region: regionId })
  },
}
