<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Protected } from '@/utils/privacy'

/** A figure, or "< 5" when the group is too small to show. */
withDefaults(defineProps<{ value: Protected; format?: (n: number) => string }>(), { format: (n: number) => String(n) })
const { t } = useI18n()
</script>

<template>
  <span v-if="value.hidden" class="hidden-value">
    <span aria-hidden="true">{{ t('stats.hidden') }}</span>
    <span class="visually-hidden">{{ t('stats.hiddenLabel') }}</span>
  </span>
  <span v-else>{{ format(value.value) }}</span>
</template>

<style scoped>
.hidden-value {
  color: var(--ink-muted);
  font-style: italic;
}
</style>
