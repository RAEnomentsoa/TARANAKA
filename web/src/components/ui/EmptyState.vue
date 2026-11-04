<script setup lang="ts">
defineProps<{ title: string; hint?: string }>()
</script>

<template>
  <div class="empty">
    <p class="empty__title">{{ title }}</p>
    <p v-if="hint" class="muted">{{ hint }}</p>
    <slot />
  </div>
</template>

<style scoped>
.empty {
  padding: var(--space-6) var(--space-4);
  border: 1px dashed var(--sky-300);
  border-radius: var(--radius-md);
  background: var(--white);
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.empty__title {
  font-weight: 700;
}
</style>
