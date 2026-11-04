<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import ReferralRow from '@/components/referrals/ReferralRow.vue'
import AppButton from '@/components/ui/AppButton.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import TabBar from '@/components/ui/TabBar.vue'
import { useAsync } from '@/composables/useAsync'
import { useNow } from '@/composables/useNow'
import { errorMessage } from '@/i18n/errors'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferralsStore } from '@/stores/referrals'

/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/utils/triage').QueueTab} QueueTab */

const { t } = useI18n()
const auth = useAuthStore()
const store = useReferralsStore()
const notifications = useNotificationsStore()
const now = useNow()

const route = useRoute()
const router = useRouter()
/** @type {QueueTab[]} */
const TABS = ['incoming', 'in_care', 'closed']
// The tab lives in the address, so "Back" from a referral returns to it.
const fromQuery = TABS.find((tab) => tab === route.query.onglet)
/** @type {import('vue').Ref<QueueTab>} */
const active = ref(fromQuery ?? 'incoming')
const tabs = computed(() =>
  TABS.map((value) => ({
    value,
    label: t(`queue.tabs.${value}`),
    count: value === 'closed' ? undefined : store.counts[value],
  })),
)
const list = computed(() => store.tab(active.value))
const { loading, error, run } = useAsync(() => store.loadAll())

/** @type {import('vue').Ref<Referral | null>} */
const pending = ref(null)
const saving = ref(false)

/** @returns {Promise<void>} */
async function confirmArrival() {
  const referral = pending.value
  if (!referral) return
  saving.value = true
  try {
    await store.changeStatus(referral, 'recu')
    notifications.push(t('queue.arrivedDone', { code: referral.code_unique }))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    saving.value = false
    pending.value = null
  }
}

onMounted(run)
watch(active, (tab) => {
  void router.replace({ query: { ...route.query, onglet: tab } })
  void store.loadTab(tab).catch(() => undefined)
})
</script>

<template>
  <PageHeader :title="t('queue.title')" :intro="t('queue.intro')">
    <template #actions>
      <AppButton variant="secondary" :loading="loading" @click="run">{{ t('common.refresh') }}</AppButton>
    </template>
  </PageHeader>

  <TabBar v-model="active" :label="t('queue.tabs.label')" :tabs="tabs" id-prefix="queue" />

  <div id="queue-panel" role="tabpanel" :aria-labelledby="`queue-tab-${active}`" class="queue" :aria-busy="loading">
    <ErrorState v-if="error" :error="error" retryable @retry="run" />
    <LoadingState v-else-if="loading && !list.length" />
    <EmptyState v-else-if="!list.length" :title="t('queue.empty')" :hint="t('queue.emptyHint')" />
    <template v-else>
      <p class="queue__count muted" aria-live="polite">{{ t('queue.count', list.length) }}</p>
      <ol class="queue__list">
        <ReferralRow
          v-for="referral in list"
          :key="referral.id"
          :referral="referral"
          :now="now"
          :can-update="auth.can('referrals:update')"
          :busy="saving && pending?.id === referral.id"
          @arrived="pending = $event"
        />
      </ol>
    </template>
  </div>

  <ConfirmDialog
    :open="pending !== null"
    :title="t('referral.actions.recu')"
    :message="pending ? t('referral.confirm.recu', { code: pending.code_unique }) : ''"
    :confirm-label="t('referral.actions.recu')"
    :busy="saving"
    @confirm="confirmArrival"
    @cancel="pending = null"
  />
</template>

<style scoped>
.queue {
  margin-top: var(--space-4);
}

.queue__count {
  font-size: var(--text-sm);
  margin-bottom: var(--space-2);
}

.queue__list {
  list-style: none;
  margin: 0;
  padding: 0;
  border: 1px solid var(--sky-200);
  border-radius: var(--radius-md);
  overflow: hidden;
}
</style>
