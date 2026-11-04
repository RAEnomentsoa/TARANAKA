<script setup lang="ts">
withDefaults(defineProps<{ tone?: 'info' | 'success' | 'warning' | 'error' }>(), { tone: 'info' })
</script>

<template>
  <div class="alert" :class="`alert--${tone}`" :role="tone === 'error' ? 'alert' : 'status'">
    <svg class="alert__icon" viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
      <circle v-if="tone === 'info'" cx="10" cy="10" r="9" fill="currentColor" />
      <path v-else-if="tone === 'success'" d="M10 1a9 9 0 1 1 0 18 9 9 0 0 1 0-18Z" fill="currentColor" />
      <path v-else d="M10 1 19 18H1Z" fill="currentColor" />
      <path v-if="tone === 'success'" d="m6 10 3 3 5-6" stroke="#fff" stroke-width="2" fill="none" />
      <path v-else-if="tone === 'info'" d="M10 9v5M10 6v.5" stroke="#fff" stroke-width="2" stroke-linecap="round" />
      <path v-else d="M10 7v5M10 14.5v.5" stroke="#fff" stroke-width="2" stroke-linecap="round" />
    </svg>
    <div class="alert__body"><slot /></div>
  </div>
</template>

<style scoped>
.alert {
  display: flex;
  gap: var(--space-3);
  align-items: flex-start;
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-sm);
  border-left: 6px solid currentColor;
}

.alert__icon {
  flex: none;
  margin-top: 0.15em;
}

.alert__body {
  color: var(--ink);
}

.alert__body :deep(p:last-child) {
  margin-bottom: 0;
}

.alert--info {
  background: var(--sky-100);
  color: var(--primary);
}

.alert--success {
  background: var(--success-bg);
  color: var(--success-ink);
}

.alert--warning {
  background: var(--orange-bg);
  color: var(--orange-ink);
}

.alert--error {
  background: var(--rouge-bg);
  color: var(--rouge-ink);
}
</style>
