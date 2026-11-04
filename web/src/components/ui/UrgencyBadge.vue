<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Urgency } from '@/api/types'

/** Urgency is never colour alone: a shape and a word go with it. */
withDefaults(defineProps<{ urgency: Urgency; withHint?: boolean }>(), { withHint: false })
const { t } = useI18n()
</script>

<template>
  <span class="urgency" :class="`urgency--${urgency}`">
    <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path v-if="urgency === 'rouge'" d="M5 1h6l4 4v6l-4 4H5l-4-4V5Z" fill="currentColor" />
      <path v-else-if="urgency === 'orange'" d="M8 1 15 8 8 15 1 8Z" fill="currentColor" />
      <circle v-else cx="8" cy="8" r="6.5" fill="currentColor" />
    </svg>
    <span>
      <span class="visually-hidden">{{ t('urgency.label') }} : </span>{{ t(`urgency.${urgency}`) }}
      <span v-if="withHint" class="urgency__hint">({{ t(`urgency.${urgency}Hint`) }})</span>
    </span>
  </span>
</template>

<style scoped>
.urgency {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-1) var(--space-3);
  border-radius: 999px;
  font-weight: 700;
  font-size: var(--text-sm);
  white-space: nowrap;
}

.urgency svg {
  flex: none;
}

.urgency__hint {
  font-weight: 400;
}

.urgency--rouge {
  background: var(--rouge-bg);
  color: var(--rouge-ink);
}

.urgency--orange {
  background: var(--orange-bg);
  color: var(--orange-ink);
}

.urgency--jaune {
  background: var(--jaune-bg);
  color: var(--jaune-ink);
}

@media (forced-colors: active) {
  .urgency {
    border: 1px solid CanvasText;
  }
}
</style>
