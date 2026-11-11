import { http } from './http'

/** @typedef {import('./types').Facility} Facility */
/** @typedef {import('./types').Region} Region */
/** @typedef {import('./types').WhoReference} WhoReference */
/** @typedef {import('./types').WhoReferenceQuery} WhoReferenceQuery */

/** @typedef {'provinces' | 'regions' | 'facilities'} TerritoryKind */

export const referentielApi = {
  /** @returns {Promise<import('./types').Province[]>} */
  provinces() {
    return http.getAll('/api/provinces/')
  },
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

/**
 * The admin edits the territory: provinces, regions and centres. A row still
 * in use can't be deleted: the server answers 400 and says why.
 */
export const territoryApi = {
  /**
   * @template T
   * @param {TerritoryKind} kind
   * @param {Partial<T>} row
   * @returns {Promise<T>}
   */
  create(kind, row) {
    return http.post(`/api/${kind}/`, row)
  },
  /**
   * @template T
   * @param {TerritoryKind} kind
   * @param {number} id
   * @param {Partial<T>} changes
   * @returns {Promise<T>}
   */
  update(kind, id, changes) {
    return http.patch(`/api/${kind}/${id}/`, changes)
  },
  /**
   * @param {TerritoryKind} kind
   * @param {number} id
   * @returns {Promise<null>}
   */
  remove(kind, id) {
    return http.request(`/api/${kind}/${id}/`, { method: 'DELETE' })
  },
}
