<script setup>
import { useI18n } from 'vue-i18n'

/** @typedef {import('@/api/types').ReferralStatus} ReferralStatus */

defineProps({
  /** @type {import('vue').PropType<ReferralStatus>} */
  status: { type: String, required: true },
})
const { t } = useI18n()
</script>

<template>
  <span class="status" :class="`status--${status}`">
    <span class="visually-hidden">{{ t('status.label') }} : </span>{{ t(`status.${status}`) }}
  </span>
</template>

<style scoped>
.status {
  display: inline-block;
  padding: 0.125rem var(--space-2);
  border: 2px solid var(--sky-200);
  border-radius: var(--radius-sm);
  font-size: var(--text-sm);
  font-weight: 700;
  color: var(--primary);
  background: var(--white);
  white-space: nowrap;
}

.status--envoye {
  border-style: dashed;
  border-color: var(--field-border);
  color: var(--ink-muted);
}

.status--clos {
  background: var(--sky-100);
  border-color: var(--sky-100);
  color: var(--ink-muted);
}
</style>
