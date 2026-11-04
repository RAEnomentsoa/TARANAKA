<script setup lang="ts" generic="T extends string">
import { ref } from 'vue'

/** WAI-ARIA tabs: arrow keys move between tabs, only the active one is tabbable. */
const props = defineProps<{
  label: string
  tabs: { value: T; label: string; count?: number }[]
  idPrefix: string
}>()
const model = defineModel<T>({ required: true })
const buttons = ref<HTMLButtonElement[]>([])

function select(index: number): void {
  const count = props.tabs.length
  const next = props.tabs[(index + count) % count]
  if (!next) return
  model.value = next.value
  buttons.value[(index + count) % count]?.focus()
}

function onKey(event: KeyboardEvent, index: number): void {
  const moves: Record<string, number> = {
    ArrowRight: index + 1,
    ArrowLeft: index - 1,
    Home: 0,
    End: props.tabs.length - 1,
  }
  const target = moves[event.key]
  if (target === undefined) return
  event.preventDefault()
  select(target)
}
</script>

<template>
  <div class="tabs" role="tablist" :aria-label="label">
    <button
      v-for="(tab, index) in tabs"
      :id="`${idPrefix}-tab-${tab.value}`"
      :key="tab.value"
      ref="buttons"
      type="button"
      role="tab"
      class="tabs__tab"
      :aria-selected="model === tab.value"
      :aria-controls="`${idPrefix}-panel`"
      :tabindex="model === tab.value ? 0 : -1"
      @click="model = tab.value"
      @keydown="onKey($event, index)"
    >
      {{ tab.label }}
      <span v-if="tab.count !== undefined" class="tabs__count">{{ tab.count }}</span>
    </button>
  </div>
</template>

<style scoped>
.tabs {
  display: flex;
  gap: var(--space-1);
  border-bottom: 2px solid var(--sky-200);
  overflow-x: auto;
}

.tabs__tab {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: var(--target);
  padding: var(--space-2) var(--space-4);
  border: none;
  border-bottom: 4px solid transparent;
  margin-bottom: -2px;
  background: none;
  color: var(--ink-muted);
  font-weight: 700;
  cursor: pointer;
  white-space: nowrap;
}

.tabs__tab:hover {
  color: var(--primary);
}

.tabs__tab[aria-selected='true'] {
  color: var(--primary);
  border-bottom-color: var(--primary);
}

.tabs__count {
  min-width: 1.75rem;
  padding: 0 var(--space-2);
  border-radius: 999px;
  background: var(--sky-100);
  color: var(--primary);
  font-size: var(--text-sm);
}
</style>
