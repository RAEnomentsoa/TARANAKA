<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Referral, ReferralStatus } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferralsStore, type DischargeDetails } from '@/stores/referrals'
import { nextStatus } from '@/utils/triage'
import DischargeForm from './DischargeForm.vue'

/** The one next step of the referral, confirmed before it is sent. */
const props = defineProps<{ referral: Referral; canUpdate: boolean; canDischarge: boolean }>()

const { t } = useI18n()
const store = useReferralsStore()
const notifications = useNotificationsStore()

const next = computed<ReferralStatus | null>(() => nextStatus(props.referral.status))
const allowed = computed(() => (next.value === 'clos' ? props.canDischarge : props.canUpdate))
const confirming = ref(false)
const dischargeOpen = ref(false)
const discharge = ref<DischargeDetails | null>(null)
const busy = ref(false)
const error = ref<unknown>(null)

const confirmMessage = computed(() => {
  if (next.value === 'clos' && discharge.value) {
    return t('discharge.confirm', {
      code: props.referral.code_unique,
      outcome: t(`discharge.outcomes.${discharge.value.issue_sortie}`),
    })
  }
  return next.value && next.value !== 'clos' ? t(`referral.confirm.${next.value}`, { code: props.referral.code_unique }) : ''
})

function start(): void {
  error.value = null
  if (next.value === 'clos') dischargeOpen.value = true
  else confirming.value = true
}

function onDischarge(details: DischargeDetails): void {
  discharge.value = details
  dischargeOpen.value = false
  confirming.value = true
}

async function confirm(): Promise<void> {
  const target = next.value
  if (!target) return
  busy.value = true
  try {
    await store.advance(props.referral, discharge.value ?? undefined)
    notifications.push(t(`referral.done.${target}`))
  } catch (caught) {
    error.value = caught
  } finally {
    busy.value = false
    confirming.value = false
    discharge.value = null
  }
}
</script>

<template>
  <div class="actions">
    <p v-if="!next" class="muted">{{ t('referral.closed') }}</p>
    <template v-else-if="allowed">
      <AppButton block :variant="next === 'clos' ? 'secondary' : 'primary'" @click="start">
        {{ t(`referral.actions.${next}`) }}
      </AppButton>
    </template>
    <ErrorState v-if="error" :error="error" />

    <ConfirmDialog
      :open="confirming"
      :title="next ? t(`referral.actions.${next}`) : ''"
      :message="confirmMessage"
      :confirm-label="next ? t(`referral.actions.${next}`) : undefined"
      :danger="next === 'clos'"
      :busy="busy"
      @confirm="confirm"
      @cancel="confirming = false"
    />

    <AppDialog :open="dischargeOpen" :title="t('discharge.title')" @close="dischargeOpen = false">
      <DischargeForm :busy="busy" @submit="onDischarge" @cancel="dischargeOpen = false" />
    </AppDialog>
  </div>
</template>

<style scoped>
.actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}
</style>
