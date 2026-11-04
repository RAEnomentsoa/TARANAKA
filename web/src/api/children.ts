import { http } from './http'
import type { Child, Measurement, Uuid } from './types'

export const childrenApi = {
  get(id: Uuid): Promise<Child> {
    return http.get<Child>(`/api/children/${id}/`)
  },

  measurements(childId: Uuid): Promise<Measurement[]> {
    return http.getAll<Measurement>(`/api/children/${childId}/measurements/`)
  },

  measurement(id: Uuid): Promise<Measurement> {
    return http.get<Measurement>(`/api/measurements/${id}/`)
  },
}
