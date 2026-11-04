<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { DischargeOutcome } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import type { DischargeDetails } from '@/stores/referrals'
import { OUTCOMES } from '@/utils/privacy'
import { todayIso } from '@/utils/dates'

const props = defineProps<{ busy: boolean }>()
const emit = defineEmits<{ submit: [details: DischargeDetails]; cancel: [] }>()

const { t } = useI18n()
const today = todayIso()
const form = reactive<{ outcome: DischargeOutcome | ''; date: string; notes: string }>({ outcome: '', date: today, notes: '' })
const errors = reactive<{ outcome: string | null; date: string | null }>({ outcome: null, date: null })
const legendId = ref('discharge-outcome')

function submit(): void {
  errors.outcome = form.outcome ? null : t('validation.required')
  errors.date = !form.date ? t('validation.required') : form.date > today ? t('care.dateInFuture') : null
  if (errors.outcome || errors.date || props.busy || !form.outcome) return
  emit('submit', { issue_sortie: form.outcome, date_sortie: form.date, notes: form.notes.trim() })
}
</script>

<template>
  <form class="stack" novalidate @submit.prevent="submit">
    <p class="muted">{{ t('discharge.intro') }}</p>
    <fieldset class="outcomes" :aria-describedby="errors.outcome ? `${legendId}-error` : undefined">
      <legend :id="legendId">{{ t('discharge.outcome') }}</legend>
      <label v-for="outcome in OUTCOMES" :key="outcome" class="outcomes__option">
        <input v-model="form.outcome" type="radio" name="outcome" :value="outcome" />
        {{ t(`discharge.outcomes.${outcome}`) }}
      </label>
      <p v-if="errors.outcome" :id="`${legendId}-error`" class="outcomes__error">{{ errors.outcome }}</p>
    </fieldset>
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('discharge.date')" :error="errors.date" required>
      <input :id="id" v-model="form.date" type="date" :max="today" required :aria-describedby="describedBy" :aria-invalid="invalid" />
    </AppField>
    <AppField v-slot="{ id, describedBy }" :label="t('discharge.notes')" optional>
      <textarea :id="id" v-model="form.notes" maxlength="2000" :aria-describedby="describedBy" />
    </AppField>
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
  gap: var(--space-1);
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
  border: 2px solid var(--sky-200);
  border-radius: var(--radius-sm);
  cursor: pointer;
}

.outcomes__option:has(input:checked) {
  border-color: var(--primary);
  background: var(--sky-50);
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
