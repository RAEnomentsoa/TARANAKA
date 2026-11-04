import { http } from './http'
import type { StatsQuery, StatsResponse } from './types'

/** Aggregated, anonymous statistics: counts of 1 to 4 come back as null. */
export const statsApi = {
  get(query: StatsQuery): Promise<StatsResponse> {
    return http.get<StatsResponse>('/api/stats/', { ...query })
  },
  /** Same figures as CSV ("<5" for hidden ones). Each export is audited. */
  exportCsv(query: StatsQuery): Promise<Blob> {
    return http.blob('/api/stats/export/', { ...query })
  },
}
