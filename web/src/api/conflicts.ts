import { http } from './http'
import type { ConflictResolution, SyncConflict, Uuid } from './types'

/** Clinical sync conflicts waiting for a person (spec §9, §10). */
export const conflictsApi = {
  list(): Promise<SyncConflict[]> {
    return http.getAll<SyncConflict>('/api/conflicts/', { statut: 'a_verifier' })
  },
  resolve(id: Uuid, resolution: ConflictResolution): Promise<SyncConflict> {
    return http.post<SyncConflict>(`/api/conflicts/${id}/resolve/`, resolution)
  },
}
