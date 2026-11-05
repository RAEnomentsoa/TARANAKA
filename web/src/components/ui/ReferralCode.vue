<script setup>
import { computed } from 'vue'

/**
 * Referral codes are read out over the phone: a legible monospace face,
 * with the groups split apart so each part can be checked.
 */
const props = defineProps({
  code: { type: String, required: true },
  /** 'md' | 'xl' */
  size: { type: String, default: 'md' },
})
const groups = computed(() => props.code.split('-'))
</script>

<template>
  <span class="code" :class="`code--${size}`" :aria-label="code">
    <template v-for="(group, index) in groups" :key="index">
      <span v-if="index > 0" class="code__dash" aria-hidden="true">-</span>
      <span class="code__group" aria-hidden="true">{{ group }}</span>
    </template>
  </span>
</template>

<style scoped>
.code {
  font-family: var(--font-code);
  font-weight: 500;
  letter-spacing: 0.04em;
  white-space: nowrap;
}

.code--md {
  font-size: var(--text-base);
}

.code--xl {
  font-size: clamp(1.5rem, 5vw, var(--text-2xl));
  letter-spacing: 0.08em;
  /* Very narrow screens: break between groups, never inside one. */
  white-space: normal;
}

.code__dash {
  color: var(--sky-400);
  padding-inline: 0.08em;
}

.code--xl .code__group {
  display: inline-block;
  padding: 0 0.15em;
  border-bottom: 3px solid var(--sky-300);
}
</style>
