import { http } from './http'

/** @typedef {import('./types').ConflictResolution} ConflictResolution */
/** @typedef {import('./types').SyncConflict} SyncConflict */
/** @typedef {import('./types').Uuid} Uuid */

/** Clinical sync conflicts waiting for a person (spec §9, §10). */
export const conflictsApi = {
  /** @returns {Promise<SyncConflict[]>} */
  list() {
    return http.getAll('/api/conflicts/', { statut: 'a_verifier' })
  },
  /**
   * @param {Uuid} id
   * @param {ConflictResolution} resolution
   * @returns {Promise<SyncConflict>}
   */
  resolve(id, resolution) {
    return http.post(`/api/conflicts/${id}/resolve/`, resolution)
  },
}
