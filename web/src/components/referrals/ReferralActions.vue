<script setup>
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferralsStore } from '@/stores/referrals'
import { canDischargeFrom, nextStatus } from '@/utils/triage'
import DischargeForm from './DischargeForm.vue'

/** @typedef {import('@/api/types').DischargeOutcome} DischargeOutcome */
/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/api/types').ReferralStatus} ReferralStatus */

/**
 * One main action (the next step) and, once the patient has arrived, the
 * discharge. Every change is confirmed before it is sent.
 */
const props = defineProps({
  /** @type {import('vue').PropType<Referral>} */
  referral: { type: Object, required: true },
  canUpdate: { type: Boolean, required: true },
  canDischarge: { type: Boolean, required: true },
})

const { t } = useI18n()
const store = useReferralsStore()
const notifications = useNotificationsStore()

const next = computed(() => nextStatus(props.referral.status))
const dischargeAllowed = computed(() => canDischargeFrom(props.referral.status))
/** @type {import('vue').Ref<ReferralStatus | null>} */
const pending = ref(null)
/** @type {import('vue').Ref<DischargeOutcome | null>} */
const outcome = ref(null)
const dischargeOpen = ref(false)
const busy = ref(false)
/** @type {import('vue').Ref<unknown>} */
const error = ref(null)

const confirmMessage = computed(() => {
  if (pending.value === 'sortie' && outcome.value) {
    return t('discharge.confirm', {
      code: props.referral.code_unique,
      outcome: t(`discharge.outcomes.${outcome.value}`),
    })
  }
  return pending.value ? t(`referral.confirm.${pending.value}`, { code: props.referral.code_unique }) : ''
})

/** @param {ReferralStatus} status */
function ask(status) {
  error.value = null
  pending.value = status
}

/** @param {DischargeOutcome} value */
function onOutcome(value) {
  outcome.value = value
  dischargeOpen.value = false
  ask('sortie')
}

function cancel() {
  pending.value = null
  outcome.value = null
}

/** @returns {Promise<void>} */
async function confirm() {
  const target = pending.value
  if (!target) return
  busy.value = true
  try {
    await store.changeStatus(props.referral, target, outcome.value ?? undefined)
    notifications.push(t(`referral.done.${target}`))
  } catch (caught) {
    error.value = caught
  } finally {
    busy.value = false
    cancel()
  }
}
</script>

<template>
  <div class="actions">
    <p v-if="referral.status === 'sortie'" class="muted">{{ t('referral.closed') }}</p>
    <AppButton v-if="next && canUpdate" block @click="ask(next)">{{ t(`referral.actions.${next}`) }}</AppButton>
    <template v-if="dischargeAllowed">
      <AppButton v-if="canDischarge" block :variant="next ? 'secondary' : 'primary'" @click="dischargeOpen = true">
        {{ t('referral.actions.sortie') }}
      </AppButton>
      <p v-else class="muted actions__note">{{ t('referral.dischargeOnlyAgent') }}</p>
    </template>
    <ErrorState v-if="error" :error="error" />

    <ConfirmDialog
      :open="pending !== null"
      :title="pending ? t(`referral.actions.${pending}`) : ''"
      :message="confirmMessage"
      :confirm-label="pending ? t(`referral.actions.${pending}`) : undefined"
      :danger="pending === 'sortie'"
      :busy="busy"
      @confirm="confirm"
      @cancel="cancel"
    />

    <AppDialog :open="dischargeOpen" :title="t('discharge.title')" @close="dischargeOpen = false">
      <DischargeForm :busy="busy" @submit="onOutcome" @cancel="dischargeOpen = false" />
    </AppDialog>
  </div>
</template>

<style scoped>
.actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.actions__note {
  font-size: var(--text-sm);
  margin: 0;
}
</style>
