<script setup lang="ts">
defineProps<{ title: string; hint?: string }>()
</script>

<template>
  <div class="empty">
    <svg viewBox="0 0 48 48" width="48" height="48" aria-hidden="true">
      <circle cx="24" cy="24" r="22" fill="var(--sky-100)" />
      <path d="M15 25h18" stroke="var(--primary)" stroke-width="3" stroke-linecap="round" />
    </svg>
    <p class="empty__title">{{ title }}</p>
    <p v-if="hint" class="muted">{{ hint }}</p>
    <slot />
  </div>
</template>

<style scoped>
.empty {
  padding: var(--space-6) var(--space-4);
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.empty__title {
  font-weight: 700;
  margin-top: var(--space-3);
}
</style>
