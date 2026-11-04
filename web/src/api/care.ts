import { http } from './http'
import type { Appointment, AppointmentInput, Consultation, ConsultationInput, Uuid } from './types'

/** Care recorded by the centre: consultations and follow-up appointments. */
export const careApi = {
  consultations(childId: Uuid): Promise<Consultation[]> {
    return http.getAll<Consultation>('/api/consultations/', { enfant: childId })
  },
  addConsultation(input: ConsultationInput): Promise<Consultation> {
    return http.post<Consultation>('/api/consultations/', input)
  },
  appointments(childId: Uuid): Promise<Appointment[]> {
    return http.getAll<Appointment>('/api/appointments/', { enfant: childId })
  },
  addAppointment(input: AppointmentInput): Promise<Appointment> {
    return http.post<Appointment>('/api/appointments/', input)
  },
  /** The child came: PATCH with the current version. */
  markAttended(appointment: Appointment): Promise<Appointment> {
    return http.patch<Appointment>(`/api/appointments/${appointment.id}/`, {
      statut: 'honore',
      version: appointment.version,
    })
  },
}
