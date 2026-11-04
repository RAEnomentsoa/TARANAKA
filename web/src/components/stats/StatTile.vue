<script setup lang="ts">
import type { Protected } from '@/utils/privacy'
import ProtectedValue from './ProtectedValue.vue'

defineProps<{ label: string; value: Protected; format?: (n: number) => string; emphasis?: boolean }>()
</script>

<template>
  <div class="tile" :class="{ 'tile--emphasis': emphasis }">
    <dt class="tile__label">{{ label }}</dt>
    <dd class="tile__value"><ProtectedValue :value="value" :format="format" /></dd>
  </div>
</template>

<style scoped>
.tile {
  padding: var(--space-4);
  background: var(--white);
  border: 1px solid var(--sky-200);
  border-radius: var(--radius-sm);
}

.tile--emphasis {
  background: var(--sky-100);
  border-color: var(--sky-100);
}

.tile__label {
  font-size: var(--text-sm);
  color: var(--ink-muted);
  font-weight: 700;
}

.tile__value {
  margin: var(--space-1) 0 0;
  font-size: var(--text-xl);
  font-weight: 700;
  line-height: 1.1;
}
</style>
