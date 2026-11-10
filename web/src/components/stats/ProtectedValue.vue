<script setup>
import { useI18n } from 'vue-i18n'

/** @typedef {import('@/utils/privacy').Protected} Protected */

/** A figure, or "< 5" when the group is too small to show. */
defineProps({
  /** @type {import('vue').PropType<Protected>} */
  value: { type: Object, required: true },
  format: { type: Function, default: (n) => String(n) },
})
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
