<script setup>
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { conflictsApi } from '@/api/conflicts'
import ConflictCard from '@/components/referrals/ConflictCard.vue'
import AppButton from '@/components/ui/AppButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useAsync } from '@/composables/useAsync'
import { errorMessage } from '@/i18n/errors'
import { useNotificationsStore } from '@/stores/notifications'

/** @typedef {import('@/api/types').ConflictResolution} ConflictResolution */
/** @typedef {import('@/api/types').SyncConflict} SyncConflict */

const { t } = useI18n()
const notifications = useNotificationsStore()
const { data, error, loading, run } = useAsync(() => conflictsApi.list())
/** @type {import('vue').Ref<string | null>} */
const busyId = ref(null)

/**
 * @param {SyncConflict} conflict
 * @param {ConflictResolution} resolution
 * @returns {Promise<void>}
 */
async function resolve(conflict, resolution) {
  busyId.value = conflict.id
  try {
    await conflictsApi.resolve(conflict.id, resolution)
    data.value = (data.value ?? []).filter((c) => c.id !== conflict.id)
    notifications.push(t('conflicts.resolved'))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    busyId.value = null
  }
}

onMounted(run)
</script>

<template>
  <PageHeader :title="t('conflicts.title')" :intro="t('conflicts.intro')">
    <template #actions>
      <AppButton variant="secondary" :loading="loading" @click="run">{{ t('common.refresh') }}</AppButton>
    </template>
  </PageHeader>

  <ErrorState v-if="error" :error="error" retryable @retry="run" />
  <LoadingState v-else-if="loading && !data" />
  <EmptyState v-else-if="!data?.length" :title="t('conflicts.empty')" />
  <template v-else>
    <p class="muted" aria-live="polite">{{ t('conflicts.count', data.length) }}</p>
    <div class="stack">
      <ConflictCard
        v-for="conflict in data"
        :key="conflict.id"
        :conflict="conflict"
        :busy="busyId === conflict.id"
        @resolve="resolve(conflict, $event)"
      />
    </div>
  </template>
</template>
