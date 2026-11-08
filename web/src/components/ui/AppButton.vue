<script setup>
defineProps({
  /** 'primary' | 'secondary' | 'ghost' | 'danger' */
  variant: { type: String, default: 'primary' },
  /** 'button' | 'submit' | 'reset' */
  type: { type: String, default: 'button' },
  loading: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  block: { type: Boolean, default: false },
})
</script>

<template>
  <button
    :type="type"
    class="btn"
    :class="[`btn--${variant}`, { 'btn--block': block }]"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
  >
    <span v-if="loading" class="btn__spinner" aria-hidden="true" />
    <slot />
  </button>
</template>

<style scoped>
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  min-height: var(--target);
  min-width: var(--target);
  padding: var(--space-2) var(--space-5);
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  font-weight: 700;
  cursor: pointer;
  text-align: center;
  line-height: 1.2;
  transition:
    background-color var(--duration) var(--easing),
    border-color var(--duration) var(--easing);
}

.btn:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.btn--primary {
  background: var(--primary);
  color: var(--white);
}

.btn--primary:hover:not(:disabled) {
  background: var(--primary-strong);
}

.btn--secondary {
  background: var(--white);
  color: var(--primary);
  border-color: var(--primary);
}

.btn--secondary:hover:not(:disabled) {
  background: var(--sky-100);
}

.btn--ghost {
  background: transparent;
  color: var(--primary);
  padding-inline: var(--space-3);
}

.btn--ghost:hover:not(:disabled) {
  background: var(--sky-100);
}

.btn--danger {
  background: var(--rouge-ink);
  color: var(--white);
}

.btn--block {
  width: 100%;
}

.btn__spinner {
  width: 1em;
  height: 1em;
  border: 2px solid currentColor;
  border-right-color: transparent;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (forced-colors: active) {
  .btn {
    border-color: ButtonText;
  }
}
</style>
