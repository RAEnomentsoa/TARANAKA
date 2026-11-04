import { http } from './http'
import type { ConflictResolution, SyncConflict } from './types'

/** Proposed endpoints (docs/API_ISSUES.md): the sync conflict queue. */
export const conflictsApi = {
  list(): Promise<SyncConflict[]> {
    return http.getAll<SyncConflict>('/api/sync/conflits/', { statut: 'ouvert' }, { proposed: true })
  },
  resolve(id: number, resolution: ConflictResolution): Promise<unknown> {
    return http.post(`/api/sync/conflits/${id}/resoudre/`, resolution, { proposed: true })
  },
}
