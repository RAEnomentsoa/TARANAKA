<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { conflictsApi } from '@/api/conflicts'
import type { ConflictResolution, SyncConflict } from '@/api/types'
import ConflictCard from '@/components/referrals/ConflictCard.vue'
import AppButton from '@/components/ui/AppButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useAsync } from '@/composables/useAsync'
import { errorMessage } from '@/i18n/errors'
import { useNotificationsStore } from '@/stores/notifications'

const { t } = useI18n()
const notifications = useNotificationsStore()
const { data, error, loading, run } = useAsync(() => conflictsApi.list())
const busyId = ref<string | null>(null)

async function resolve(conflict: SyncConflict, resolution: ConflictResolution): Promise<void> {
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
