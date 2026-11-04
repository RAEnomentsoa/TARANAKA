import { http } from './http'
import type { Facility, Region } from './types'

export const referentielApi = {
  regions(): Promise<Region[]> {
    return http.getAll<Region>('/api/regions/')
  },
  facilities(regionId?: number): Promise<Facility[]> {
    return http.getAll<Facility>('/api/facilities/', { region: regionId })
  },
}
