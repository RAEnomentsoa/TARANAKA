import { http } from './http'

/** @typedef {import('./types').Facility} Facility */
/** @typedef {import('./types').Region} Region */
/** @typedef {import('./types').WhoReference} WhoReference */
/** @typedef {import('./types').WhoReferenceQuery} WhoReferenceQuery */

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
  /**
   * WHO 2006 growth curves (-3, -2, 0, +2, +3 z), from the official tables
   * loaded on the server. 404 when the table is not loaded.
   * @param {WhoReferenceQuery} query
   * @returns {Promise<WhoReference>}
   */
  whoReference(query) {
    return http.get('/api/who-reference/', { ...query })
  },
}
