import { http } from './http'
import type { Consultation, ConsultationInput, FollowUp, FollowUpInput, Uuid } from './types'

/** Proposed endpoints (docs/API_ISSUES.md): care records and follow-up visits. */
export const careApi = {
  consultations(childId: Uuid): Promise<Consultation[]> {
    return http.getAll<Consultation>('/api/consultations/', { enfant: childId }, { proposed: true })
  },
  addConsultation(input: ConsultationInput): Promise<Consultation> {
    return http.post<Consultation>('/api/consultations/', input, { proposed: true })
  },
  followUps(childId: Uuid): Promise<FollowUp[]> {
    return http.getAll<FollowUp>('/api/rendez-vous/', { enfant: childId }, { proposed: true })
  },
  addFollowUp(input: FollowUpInput): Promise<FollowUp> {
    return http.post<FollowUp>('/api/rendez-vous/', input, { proposed: true })
  },
}
