<script setup lang="ts">
/** Page title (focused after navigation) with an optional intro and actions. */
defineProps<{ title: string; intro?: string }>()
</script>

<template>
  <header class="page-header">
    <div class="page-header__text">
      <slot name="before" />
      <h1 tabindex="-1" data-page-title>{{ title }}</h1>
      <p v-if="intro" class="muted">{{ intro }}</p>
    </div>
    <div v-if="$slots.actions" class="page-header__actions"><slot name="actions" /></div>
  </header>
</template>

<style scoped>
.page-header {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--space-4);
  margin-bottom: var(--space-5);
}

.page-header h1:focus {
  outline: none;
}

.page-header__text p {
  margin-bottom: 0;
}

.page-header__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
}
</style>
