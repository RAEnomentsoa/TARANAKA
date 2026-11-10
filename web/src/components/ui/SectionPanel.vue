<script setup>
import { useId } from 'vue'

/** A titled region of a page; the heading names the landmark. */
defineProps({
  title: { type: String, required: true },
  /** Heading level, 2 or 3. */
  level: { type: Number, default: 2 },
})
const id = useId()
</script>

<template>
  <section class="panel" :aria-labelledby="id">
    <header class="panel__header">
      <component :is="`h${level}`" :id="id" class="panel__title">{{ title }}</component>
      <div v-if="$slots.actions" class="panel__actions"><slot name="actions" /></div>
    </header>
    <slot />
  </section>
</template>

<style scoped>
.panel {
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  padding: var(--space-5);
}

.panel__header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  margin-bottom: var(--space-4);
}

.panel__title {
  margin: 0;
}

.panel__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
}

@media (max-width: 40rem) {
  .panel {
    padding: var(--space-4);
    border-radius: var(--radius-sm);
  }
}
</style>
