<script setup lang="ts">
import { reactive } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Decision } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import { todayIso } from '@/utils/dates'

export interface ConsultationDraft {
  date: string
  diagnostic: string
  decision: Decision
  observations: string
}

const props = defineProps<{ busy: boolean; serverErrors?: Record<string, string[]> }>()
const emit = defineEmits<{ submit: [draft: ConsultationDraft]; cancel: [] }>()

const DECISIONS: Decision[] = ['prise_en_charge', 'conseil', 'reference']
const { t } = useI18n()
const today = todayIso()
const form = reactive<ConsultationDraft>({ date: today, diagnostic: '', decision: 'prise_en_charge', observations: '' })
const errors = reactive<{ date: string | null; diagnostic: string | null }>({ date: null, diagnostic: null })

function fieldError(name: string, local: string | null): string | null {
  return local ?? props.serverErrors?.[name]?.join(' ') ?? null
}

function submit(): void {
  errors.date = !form.date ? t('validation.required') : form.date > today ? t('care.dateInFuture') : null
  errors.diagnostic = form.diagnostic.trim() ? null : t('validation.required')
  if (errors.date || errors.diagnostic || props.busy) return
  emit('submit', { ...form, diagnostic: form.diagnostic.trim(), observations: form.observations.trim() })
}
</script>

<template>
  <form class="stack" novalidate @submit.prevent="submit">
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('care.date')" :error="fieldError('date', errors.date)" required>
      <input :id="id" v-model="form.date" type="date" :max="today" required :aria-describedby="describedBy" :aria-invalid="invalid" />
    </AppField>
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('care.diagnostic')" :error="fieldError('diagnostic', errors.diagnostic)" required>
      <textarea :id="id" v-model="form.diagnostic" maxlength="2000" required :aria-describedby="describedBy" :aria-invalid="invalid" />
    </AppField>
    <AppField v-slot="{ id, describedBy }" :label="t('care.decision')" :error="fieldError('decision', null)" required>
      <select :id="id" v-model="form.decision" :aria-describedby="describedBy">
        <option v-for="decision in DECISIONS" :key="decision" :value="decision">{{ t(`care.decisions.${decision}`) }}</option>
      </select>
    </AppField>
    <AppField v-slot="{ id, describedBy }" :label="t('care.observations')" optional>
      <textarea :id="id" v-model="form.observations" maxlength="2000" :aria-describedby="describedBy" />
    </AppField>
    <div class="form-actions">
      <AppButton variant="ghost" :disabled="busy" @click="emit('cancel')">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" :loading="busy">{{ t('common.save') }}</AppButton>
    </div>
  </form>
</template>

<style scoped>
.form-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: var(--space-3);
}
</style>
