import { http } from './http'

/** @typedef {import('./types').Appointment} Appointment */
/** @typedef {import('./types').AppointmentInput} AppointmentInput */
/** @typedef {import('./types').Consultation} Consultation */
/** @typedef {import('./types').ConsultationInput} ConsultationInput */
/** @typedef {import('./types').Uuid} Uuid */

/** Care recorded by the centre: consultations and follow-up appointments. */
export const careApi = {
  /**
   * @param {Uuid} childId
   * @returns {Promise<Consultation[]>}
   */
  consultations(childId) {
    return http.getAll('/api/consultations/', { enfant: childId })
  },
  /**
   * @param {ConsultationInput} input
   * @returns {Promise<Consultation>}
   */
  addConsultation(input) {
    return http.post('/api/consultations/', input)
  },
  /**
   * @param {Uuid} childId
   * @returns {Promise<Appointment[]>}
   */
  appointments(childId) {
    return http.getAll('/api/appointments/', { enfant: childId })
  },
  /**
   * @param {AppointmentInput} input
   * @returns {Promise<Appointment>}
   */
  addAppointment(input) {
    return http.post('/api/appointments/', input)
  },
  /**
   * The child came: PATCH with the current version.
   * @param {Appointment} appointment
   * @returns {Promise<Appointment>}
   */
  markAttended(appointment) {
    return http.patch(`/api/appointments/${appointment.id}/`, {
      statut: 'honore',
      version: appointment.version,
    })
  },
}
