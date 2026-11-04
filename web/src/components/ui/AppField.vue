<script setup lang="ts">
import { computed, useId } from 'vue'
import { useI18n } from 'vue-i18n'

/**
 * Label, hint and error around one form control. The control comes from the
 * slot and receives the ids it must use, so every error is announced.
 */
const props = defineProps<{
  label: string
  hint?: string
  error?: string | null
  required?: boolean
  optional?: boolean
}>()

const { t } = useI18n()
const id = useId()
const hintId = `${id}-hint`
const errorId = `${id}-error`
const describedBy = computed(
  () => [props.hint ? hintId : '', props.error ? errorId : ''].filter(Boolean).join(' ') || undefined,
)
</script>

<template>
  <div class="field" :class="{ 'field--invalid': error }">
    <label :for="id" class="field__label">
      {{ label }}
      <span v-if="optional" class="field__optional">({{ t('common.optional') }})</span>
    </label>
    <p v-if="hint" :id="hintId" class="field__hint">{{ hint }}</p>
    <slot :id="id" :described-by="describedBy" :invalid="Boolean(error)" :required="required" />
    <p v-if="error" :id="errorId" class="field__error">
      <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
        <path d="M8 1 15 14H1Z" fill="currentColor" />
        <path d="M8 6v4M8 11.5v.5" stroke="#fff" stroke-width="1.6" stroke-linecap="round" />
      </svg>
      {{ error }}
    </p>
  </div>
</template>

<style scoped>
.field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.field__label {
  font-weight: 700;
}

.field__optional {
  font-weight: 400;
  color: var(--ink-muted);
}

.field__hint {
  margin: 0;
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.field__error {
  display: flex;
  gap: var(--space-2);
  align-items: center;
  margin: 0;
  color: var(--rouge-ink);
  font-weight: 700;
  font-size: var(--text-sm);
}

.field :slotted(input),
.field :slotted(select),
.field :slotted(textarea) {
  min-height: var(--target);
  width: 100%;
  padding: var(--space-2) var(--space-3);
  border: 2px solid var(--field-border);
  border-radius: var(--radius-sm);
  background: var(--white);
}

.field :slotted(textarea) {
  min-height: 6rem;
  resize: vertical;
}

.field--invalid :slotted(input),
.field--invalid :slotted(select),
.field--invalid :slotted(textarea) {
  border-color: var(--rouge-ink);
}
</style>
