<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { careApi } from '@/api/care'
import { newUuid } from '@/api/deviceId'
import { isApiError } from '@/api/errors'
import type { Consultation, FollowUp, Uuid } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { useNotificationsStore } from '@/stores/notifications'
import ConsultationForm, { type ConsultationDraft } from './ConsultationForm.vue'
import FollowUpForm, { type FollowUpDraft } from './FollowUpForm.vue'

/** Care records and follow-up visits of one child (proposed endpoints). */
const props = defineProps<{ childId: Uuid; referralId: Uuid | null; csbId: number | null; canWrite: boolean }>()

const { t } = useI18n()
const fmt = useFormatters()
const notifications = useNotificationsStore()

const consultations = useAsync(() => careApi.consultations(props.childId))
const followUps = useAsync(() => careApi.followUps(props.childId))

const dialog = ref<'consultation' | 'followUp' | null>(null)
const busy = ref(false)
const saveError = ref<unknown>(null)
const serverErrors = ref<Record<string, string[]>>({})

function open(kind: 'consultation' | 'followUp'): void {
  saveError.value = null
  serverErrors.value = {}
  dialog.value = kind
}

async function save<T>(action: () => Promise<T>, onDone: (result: T) => void): Promise<void> {
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

function addConsultation(draft: ConsultationDraft): Promise<void> {
  if (props.csbId === null) return Promise.resolve()
  return save(
    () => careApi.addConsultation({ id: newUuid(), enfant_id: props.childId, referencement_id: props.referralId, csb_id: props.csbId!, ...draft }),
    (created: Consultation) => {
      consultations.data.value = [created, ...(consultations.data.value ?? [])]
      notifications.push(t('care.consultationSaved'))
    },
  )
}

function addFollowUp(draft: FollowUpDraft): Promise<void> {
  return save(
    () => careApi.addFollowUp({ id: newUuid(), enfant_id: props.childId, referencement_id: props.referralId, ...draft }),
    (created: FollowUp) => {
      followUps.data.value = [...(followUps.data.value ?? []), created]
      notifications.push(t('care.followUpSaved', { date: fmt.date(created.date_prevue) }))
    },
  )
}

onMounted(() => {
  void consultations.run()
  void followUps.run()
})
</script>

<template>
  <SectionPanel :title="t('care.title')">
    <template v-if="canWrite" #actions>
      <AppButton variant="secondary" :disabled="csbId === null" @click="open('consultation')">{{ t('care.add') }}</AppButton>
      <AppButton variant="secondary" @click="open('followUp')">{{ t('care.addFollowUp') }}</AppButton>
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
        <LoadingState v-if="followUps.loading.value" />
        <ErrorState v-else-if="followUps.error.value" :error="followUps.error.value" retryable @retry="followUps.run" />
        <p v-else-if="!followUps.data.value?.length" class="muted">{{ t('care.noFollowUps') }}</p>
        <ul v-else class="visits">
          <li v-for="f in followUps.data.value" :key="f.id" :class="`visits__item visits__item--${f.statut}`">
            <time :datetime="f.date_prevue" class="visits__date">{{ fmt.date(f.date_prevue) }}</time>
            <span>{{ f.motif }}</span>
            <span class="visits__status">{{ t(`care.followUpStatus.${f.statut}`) }}</span>
          </li>
        </ul>
      </section>
    </div>

    <AppDialog :open="dialog === 'consultation'" :title="t('care.add')" @close="dialog = null">
      <ErrorState v-if="saveError" :error="saveError" />
      <ConsultationForm :busy="busy" :server-errors="serverErrors" @submit="addConsultation" @cancel="dialog = null" />
    </AppDialog>
    <AppDialog :open="dialog === 'followUp'" :title="t('care.addFollowUp')" @close="dialog = null">
      <ErrorState v-if="saveError" :error="saveError" />
      <FollowUpForm :busy="busy" :server-errors="serverErrors" @submit="addFollowUp" @cancel="dialog = null" />
    </AppDialog>
  </SectionPanel>
</template>

<style scoped>
.care {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
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
  gap: var(--space-3);
  align-items: baseline;
  padding: var(--space-2) 0;
  border-bottom: 1px solid var(--sky-200);
}

.visits__date {
  font-weight: 700;
}

.visits__status {
  font-size: var(--text-sm);
  font-weight: 700;
  color: var(--primary);
}

.visits__item--manque .visits__status {
  color: var(--rouge-ink);
}

.visits__item--honore .visits__status {
  color: var(--success-ink);
}
</style>
