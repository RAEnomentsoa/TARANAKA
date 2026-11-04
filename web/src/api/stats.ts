import { http } from './http'
import type { StatsQuery, StatsResponse } from './types'

/** Proposed endpoint (docs/API_ISSUES.md): aggregated, anonymous statistics. */
export const statsApi = {
  get(query: StatsQuery): Promise<StatsResponse> {
    return http.get<StatsResponse>('/api/stats/', { ...query }, { proposed: true })
  },
}
