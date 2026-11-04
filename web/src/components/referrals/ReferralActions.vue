<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { DischargeOutcome, Referral, ReferralStatus } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferralsStore } from '@/stores/referrals'
import { canDischargeFrom, nextStatus } from '@/utils/triage'
import DischargeForm from './DischargeForm.vue'

/**
 * One main action (the next step) and, once the patient has arrived, the
 * discharge. Every change is confirmed before it is sent.
 */
const props = defineProps<{ referral: Referral; canUpdate: boolean; canDischarge: boolean }>()

const { t } = useI18n()
const store = useReferralsStore()
const notifications = useNotificationsStore()

const next = computed(() => nextStatus(props.referral.status))
const dischargeAllowed = computed(() => canDischargeFrom(props.referral.status))
const pending = ref<ReferralStatus | null>(null)
const outcome = ref<DischargeOutcome | null>(null)
const dischargeOpen = ref(false)
const busy = ref(false)
const error = ref<unknown>(null)

const confirmMessage = computed(() => {
  if (pending.value === 'sortie' && outcome.value) {
    return t('discharge.confirm', {
      code: props.referral.code_unique,
      outcome: t(`discharge.outcomes.${outcome.value}`),
    })
  }
  return pending.value ? t(`referral.confirm.${pending.value}`, { code: props.referral.code_unique }) : ''
})

function ask(status: ReferralStatus): void {
  error.value = null
  pending.value = status
}

function onOutcome(value: DischargeOutcome): void {
  outcome.value = value
  dischargeOpen.value = false
  ask('sortie')
}

function cancel(): void {
  pending.value = null
  outcome.value = null
}

async function confirm(): Promise<void> {
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
