<script setup>
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { careApi } from '@/api/care'
import { newUuid } from '@/api/deviceId'
import { isApiError } from '@/api/errors'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { errorMessage } from '@/i18n/errors'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { todayIso } from '@/utils/dates'
import AppointmentForm from './AppointmentForm.vue'
import ConsultationForm from './ConsultationForm.vue'

/** @typedef {import('@/api/types').Appointment} Appointment */
/** @typedef {import('@/api/types').Consultation} Consultation */
/** @typedef {import('@/api/types').Uuid} Uuid */

/** @typedef {{ date: string, diagnostic: string, decision: import('@/api/types').Decision, observations: string }} ConsultationDraft */
/** @typedef {{ date_prevue: string, motif: string }} AppointmentDraft */

/** Consultations and follow-up appointments of one child (spec §10). */
const props = defineProps({
  childId: { type: String, required: true },
  referralId: { type: String, default: null },
  csbId: { type: Number, default: null },
  canWrite: { type: Boolean, required: true },
})

const { t } = useI18n()
const fmt = useFormatters()
// A visit is marked as attended on or after its day, never before.
const today = todayIso()
const auth = useAuthStore()
const notifications = useNotificationsStore()

const consultations = useAsync(() => careApi.consultations(props.childId))
const appointments = useAsync(async () =>
  (await careApi.appointments(props.childId)).sort((a, b) => a.date_prevue.localeCompare(b.date_prevue)),
)

/** @type {import('vue').Ref<'consultation' | 'appointment' | null>} */
const dialog = ref(null)
const busy = ref(false)
/** @type {import('vue').Ref<Uuid | null>} */
const attending = ref(null)
/** @type {import('vue').Ref<unknown>} */
const saveError = ref(null)
/** @type {import('vue').Ref<Record<string, string[]>>} */
const serverErrors = ref({})

/** @param {'consultation' | 'appointment'} kind */
function open(kind) {
  saveError.value = null
  serverErrors.value = {}
  dialog.value = kind
}

/**
 * @template T
 * @param {() => Promise<T>} action
 * @param {(result: T) => void} onDone
 * @returns {Promise<void>}
 */
async function save(action, onDone) {
  busy.value = true
  saveError.value = null
  serverErrors.value = {}
  try {
    onDone(await action())
    dialog.value = null
  } catch (caught) {
    saveError.value = caught
    if (isApiError(caught)) serverErrors.value = caught.fieldErrors
  } finally {
    busy.value = false
  }
}

/**
 * @param {ConsultationDraft} draft
 * @returns {Promise<void>}
 */
function addConsultation(draft) {
  return save(
    () =>
      careApi.addConsultation({
        id: newUuid(),
        enfant_id: props.childId,
        referencement_id: props.referralId,
        // Forced by the server for a centre agent; an admin must send them.
        ...(props.csbId !== null ? { csb_id: props.csbId } : {}),
        ...(auth.user ? { agent_medical_id: auth.user.id } : {}),
        ...draft,
      }),
    (created) => {
      consultations.data.value = [created, ...(consultations.data.value ?? [])]
      notifications.push(t('care.consultationSaved'))
    },
  )
}

/**
 * @param {AppointmentDraft} draft
 * @returns {Promise<void>}
 */
function addAppointment(draft) {
  return save(
    () =>
      careApi.addAppointment({
        id: newUuid(),
        enfant_id: props.childId,
        referencement_id: props.referralId,
        type_rendez_vous: 'controle',
        ...draft,
      }),
    (created) => {
      appointments.data.value = [...(appointments.data.value ?? []), created].sort((a, b) =>
        a.date_prevue.localeCompare(b.date_prevue),
      )
      notifications.push(t('care.followUpSaved', { date: fmt.date(created.date_prevue) }))
    },
  )
}

/**
 * @param {Appointment} appointment
 * @returns {Promise<void>}
 */
async function markAttended(appointment) {
  attending.value = appointment.id
  try {
    const updated = await careApi.markAttended(appointment)
    appointments.data.value = (appointments.data.value ?? []).map((a) => (a.id === updated.id ? updated : a))
    notifications.push(t('care.attendedSaved'))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
    if (isApiError(caught) && caught.kind === 'conflict') void appointments.run()
  } finally {
    attending.value = null
  }
}

onMounted(() => {
  void consultations.run()
  void appointments.run()
})
</script>

<template>
  <SectionPanel :title="t('care.title')">
    <template v-if="canWrite" #actions>
      <AppButton variant="secondary" @click="open('consultation')">{{ t('care.add') }}</AppButton>
      <AppButton variant="secondary" @click="open('appointment')">{{ t('care.addFollowUp') }}</AppButton>
    </template>

    <div class="care">
      <section>
        <h3>{{ t('care.consultations') }}</h3>
        <LoadingState v-if="consultations.loading.value" />
        <ErrorState v-else-if="consultations.error.value" :error="consultations.error.value" retryable @retry="consultations.run" />
        <p v-else-if="!consultations.data.value?.length" class="muted">{{ t('care.noConsultations') }}</p>
        <ol v-else class="timeline">
          <li v-for="c in consultations.data.value" :key="c.id">
            <p class="timeline__date">
              <time :datetime="c.date">{{ fmt.date(c.date) }}</time> — {{ t(`care.decisions.${c.decision}`) }}
            </p>
            <p>{{ c.diagnostic }}</p>
            <p v-if="c.observations" class="muted">{{ c.observations }}</p>
          </li>
        </ol>
      </section>

      <section>
        <h3>{{ t('care.followUps') }}</h3>
        <LoadingState v-if="appointments.loading.value" />
        <ErrorState v-else-if="appointments.error.value" :error="appointments.error.value" retryable @retry="appointments.run" />
        <p v-else-if="!appointments.data.value?.length" class="muted">{{ t('care.noFollowUps') }}</p>
        <ul v-else class="visits">
          <li v-for="a in appointments.data.value" :key="a.id" class="visits__item" :class="{ 'visits__item--missed': a.manque }">
            <time :datetime="a.date_prevue" class="visits__date">{{ fmt.date(a.date_prevue) }}</time>
            <span class="visits__reason">{{ a.motif }}</span>
            <span class="visits__status">{{ a.manque ? t('care.missed') : t(`care.followUpStatus.${a.statut}`) }}</span>
            <AppButton
              v-if="canWrite && a.statut === 'prevu' && a.date_prevue <= today"
              variant="ghost"
              class="visits__action"
              :loading="attending === a.id"
              :aria-label="t('care.markAttendedLabel', { date: fmt.date(a.date_prevue) })"
              @click="markAttended(a)"
            >
              {{ t('care.markAttended') }}
            </AppButton>
          </li>
        </ul>
      </section>
    </div>

    <AppDialog :open="dialog === 'consultation'" :title="t('care.add')" @close="dialog = null">
      <ErrorState v-if="saveError" :error="saveError" />
      <ConsultationForm :busy="busy" :server-errors="serverErrors" @submit="addConsultation" @cancel="dialog = null" />
    </AppDialog>
    <AppDialog :open="dialog === 'appointment'" :title="t('care.addFollowUp')" @close="dialog = null">
      <ErrorState v-if="saveError" :error="saveError" />
      <AppointmentForm :busy="busy" :server-errors="serverErrors" @submit="addAppointment" @cancel="dialog = null" />
    </AppDialog>
  </SectionPanel>
</template>

<style scoped>
.care {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
  gap: var(--space-5);
}

.timeline {
  list-style: none;
  margin: 0;
  padding: 0 0 0 var(--space-4);
  border-left: 3px solid var(--sky-200);
}

.timeline li + li {
  margin-top: var(--space-4);
}

.timeline__date {
  font-weight: 700;
  margin-bottom: var(--space-1);
}

.timeline p {
  margin-bottom: var(--space-1);
}

.visits {
  list-style: none;
  margin: 0;
  padding: 0;
}

.visits__item {
  display: grid;
  grid-template-columns: auto 1fr auto;
  grid-template-areas:
    'date reason status'
    'action action action';
  gap: 0 var(--space-3);
  align-items: baseline;
  padding: var(--space-2) 0;
  border-bottom: 1px solid var(--sky-200);
}

.visits__date {
  grid-area: date;
  font-weight: 700;
}

.visits__reason {
  grid-area: reason;
}

.visits__status {
  grid-area: status;
  font-size: var(--text-sm);
  font-weight: 700;
  color: var(--primary);
}

.visits__action {
  grid-area: action;
  justify-self: start;
}

.visits__item--missed .visits__status {
  color: var(--rouge-ink);
}
</style>
