<script setup lang="ts">
import { computed } from 'vue'
import type { Protected } from '@/utils/privacy'
import ProtectedValue from './ProtectedValue.vue'

/**
 * Horizontal bars, labelled directly with their value. A hidden value gets
 * a hatched stub, so its absence is visible but its size is not.
 */
const props = defineProps<{ caption: string; labelHeader: string; valueHeader: string; items: { key: string; label: string; value: Protected }[] }>()

const max = computed(() => Math.max(1, ...props.items.map((i) => (i.value.hidden ? 0 : i.value.value))))
function width(value: Protected): string {
  return value.hidden ? '2.5rem' : `${Math.max(0.5, (value.value / max.value) * 100)}%`
}
</script>

<template>
  <table class="bars">
    <caption class="visually-hidden">{{ caption }}</caption>
    <thead class="visually-hidden">
      <tr>
        <th scope="col">{{ labelHeader }}</th>
        <th scope="col">{{ valueHeader }}</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="item in items" :key="item.key">
        <th scope="row" class="bars__label">{{ item.label }}</th>
        <td class="bars__cell">
          <span class="bars__track" aria-hidden="true">
            <span class="bars__bar" :class="{ 'bars__bar--hidden': item.value.hidden }" :style="{ width: width(item.value) }" />
          </span>
          <span class="bars__value"><ProtectedValue :value="item.value" /></span>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.bars th,
.bars td {
  border: none;
  padding: var(--space-1) var(--space-2);
  vertical-align: middle;
}

.bars__label {
  width: 40%;
  font-weight: 400;
}

.bars__cell {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.bars__track {
  flex: 1;
  min-width: 0;
}

.bars__bar {
  display: block;
  height: 1rem;
  border-radius: 0 4px 4px 0;
  background: var(--primary);
}

.bars__bar--hidden {
  background: repeating-linear-gradient(135deg, var(--sky-200) 0 4px, var(--white) 4px 8px);
  border: 1px solid var(--sky-300);
}

.bars__value {
  min-width: 3rem;
  text-align: right;
  font-weight: 700;
}
</style>
