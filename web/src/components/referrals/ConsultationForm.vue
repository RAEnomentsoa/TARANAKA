<script setup>
import { reactive } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import { todayIso } from '@/utils/dates'

/** @typedef {import('@/api/types').Decision} Decision */

/**
 * @typedef {Object} ConsultationDraft
 * @property {string} date
 * @property {string} diagnostic
 * @property {Decision} decision
 * @property {string} observations
 */

const props = defineProps({
  busy: { type: Boolean, required: true },
  /** Field errors sent back by the server, by field name. */
  serverErrors: { type: Object, default: () => ({}) },
})
/** submit(draft: ConsultationDraft), cancel() */
const emit = defineEmits(['submit', 'cancel'])

/** @type {Decision[]} */
const DECISIONS = ['prise_en_charge', 'conseil', 'reference']
const { t } = useI18n()
const today = todayIso()
/** @type {ConsultationDraft} */
const form = reactive({ date: today, diagnostic: '', decision: 'prise_en_charge', observations: '' })
/** @type {{ date: string | null, diagnostic: string | null }} */
const errors = reactive({ date: null, diagnostic: null })

/**
 * @param {string} name
 * @param {string | null} local
 * @returns {string | null}
 */
function fieldError(name, local) {
  return local ?? props.serverErrors?.[name]?.join(' ') ?? null
}

function submit() {
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
