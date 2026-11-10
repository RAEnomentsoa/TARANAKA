<script setup>
import { computed } from 'vue'
import ProtectedValue from './ProtectedValue.vue'

/** @typedef {import('@/utils/privacy').Protected} Protected */

/**
 * Horizontal bars, labelled directly with their value. A hidden value gets
 * an empty dashed stub, so its absence is visible but its size is not.
 */
const props = defineProps({
  caption: { type: String, required: true },
  labelHeader: { type: String, required: true },
  valueHeader: { type: String, required: true },
  /** @type {import('vue').PropType<{ key: string, label: string, value: Protected }[]>} */
  items: { type: Array, required: true },
})

const max = computed(() => Math.max(1, ...props.items.map((i) => (i.value.hidden ? 0 : i.value.value))))
/**
 * @param {Protected} value
 * @returns {string}
 */
function width(value) {
  if (value.hidden) return '2.5rem'
  // Zero draws nothing: a stub would read as "a few cases".
  return value.value === 0 ? '0' : `${Math.max(1.5, (value.value / max.value) * 100)}%`
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
  transform-origin: left center;
  animation: grow-x 520ms var(--easing) backwards;
}

.bars__bar--hidden {
  background: repeating-linear-gradient(45deg, var(--sky-100) 0 3px, var(--white) 3px 6px);
  border: 1.5px dashed var(--field-border);
}

.bars__value {
  min-width: 3rem;
  text-align: right;
  font-weight: 700;
}
</style>
