<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { isApiError } from '@/api/errors'
import { errorMessage } from '@/i18n/errors'
import AppButton from './AppButton.vue'
import InlineAlert from './InlineAlert.vue'

const props = defineProps<{ error: unknown; retryable?: boolean }>()
defineEmits<{ retry: [] }>()

const { t } = useI18n()
const message = computed(() => errorMessage(t, props.error))
const detail = computed(() => (isApiError(props.error) && props.error.kind !== 'not_implemented' ? props.error.detail : null))
const tone = computed(() => (isApiError(props.error) && props.error.kind === 'not_implemented' ? 'warning' : 'error'))
</script>

<template>
  <InlineAlert :tone="tone">
    <p>{{ message }}</p>
    <p v-if="detail" class="muted">{{ t('errors.serverSays', { detail }) }}</p>
    <AppButton v-if="retryable" variant="secondary" @click="$emit('retry')">{{ t('errors.retry') }}</AppButton>
  </InlineAlert>
</template>
