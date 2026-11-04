<script setup>
import { ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import { OUTCOMES } from '@/utils/triage'

/** @typedef {import('@/api/types').DischargeOutcome} DischargeOutcome */

const props = defineProps({ busy: { type: Boolean, required: true } })
/** submit(outcome: DischargeOutcome), cancel() */
const emit = defineEmits(['submit', 'cancel'])

const { t } = useI18n()
/** @type {import('vue').Ref<DischargeOutcome | ''>} */
const outcome = ref('')
/** @type {import('vue').Ref<string | null>} */
const error = ref(null)
const id = useId()

function submit() {
  error.value = outcome.value ? null : t('validation.required')
  if (!outcome.value || props.busy) return
  emit('submit', outcome.value)
}
</script>

<template>
  <form class="stack" novalidate @submit.prevent="submit">
    <p class="muted">{{ t('discharge.intro') }}</p>
    <fieldset class="outcomes" :aria-describedby="error ? `${id}-error` : undefined" :aria-invalid="Boolean(error)">
      <legend>{{ t('discharge.outcome') }}</legend>
      <label v-for="value in OUTCOMES" :key="value" class="outcomes__option">
        <input v-model="outcome" type="radio" :name="`${id}-outcome`" :value="value" />
        {{ t(`discharge.outcomes.${value}`) }}
      </label>
      <p v-if="error" :id="`${id}-error`" class="outcomes__error">{{ error }}</p>
    </fieldset>
    <div class="actions">
      <AppButton variant="ghost" :disabled="busy" @click="emit('cancel')">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" variant="danger" :loading="busy">{{ t('discharge.submit') }}</AppButton>
    </div>
  </form>
</template>

<style scoped>
.outcomes {
  border: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: var(--space-2);
}

.outcomes legend {
  font-weight: 700;
  margin-bottom: var(--space-2);
  padding: 0;
}

.outcomes__option {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--target);
  padding: 0 var(--space-3);
  border: 1px solid var(--field-border);
  border-radius: var(--radius-sm);
  cursor: pointer;
}

.outcomes__option:has(input:checked) {
  border: 2px solid var(--primary);
  background: var(--sky-50);
  font-weight: 700;
}

.outcomes__option input {
  width: 1.25rem;
  height: 1.25rem;
  accent-color: var(--primary);
}

.outcomes__error {
  color: var(--rouge-ink);
  font-weight: 700;
  margin: 0;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: var(--space-3);
}
</style>
