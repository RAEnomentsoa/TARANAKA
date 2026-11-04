import { http } from './http'

/** @typedef {import('./types').StatsQuery} StatsQuery */
/** @typedef {import('./types').StatsResponse} StatsResponse */

/** Aggregated, anonymous statistics: counts of 1 to 4 come back as null. */
export const statsApi = {
  /**
   * @param {StatsQuery} query
   * @returns {Promise<StatsResponse>}
   */
  get(query) {
    return http.get('/api/stats/', { ...query })
  },
  /**
   * Same figures as CSV ("<5" for hidden ones). Each export is audited.
   * @param {StatsQuery} query
   * @returns {Promise<Blob>}
   */
  exportCsv(query) {
    return http.blob('/api/stats/export/', { ...query })
  },
}
