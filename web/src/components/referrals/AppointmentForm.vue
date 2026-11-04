<script setup>
import { reactive } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import { addDays, todayIso } from '@/utils/dates'

/**
 * @typedef {Object} AppointmentDraft
 * @property {string} date_prevue
 * @property {string} motif
 */

const props = defineProps({
  busy: { type: Boolean, required: true },
  /** Field errors sent back by the server, by field name. */
  serverErrors: { type: Object, default: () => ({}) },
})
/** submit(draft: AppointmentDraft), cancel() */
const emit = defineEmits(['submit', 'cancel'])

const { t } = useI18n()
const today = todayIso()
// One week is the usual CRENAS control interval; the professional can change it.
/** @type {AppointmentDraft} */
const form = reactive({ date_prevue: addDays(today, 7), motif: '' })
/** @type {{ date: string | null, motif: string | null }} */
const errors = reactive({ date: null, motif: null })

function submit() {
  errors.date = !form.date_prevue ? t('validation.required') : form.date_prevue < today ? t('care.dateInPast') : null
  errors.motif = form.motif.trim() ? null : t('validation.required')
  if (errors.date || errors.motif || props.busy) return
  emit('submit', { date_prevue: form.date_prevue, motif: form.motif.trim() })
}
</script>

<template>
  <form class="stack" novalidate @submit.prevent="submit">
    <AppField
      v-slot="{ id, describedBy, invalid }"
      :label="t('care.followUpDate')"
      :error="errors.date ?? serverErrors?.date_prevue?.join(' ') ?? null"
      required
    >
      <input :id="id" v-model="form.date_prevue" type="date" :min="today" required :aria-describedby="describedBy" :aria-invalid="invalid" />
    </AppField>
    <AppField
      v-slot="{ id, describedBy, invalid }"
      :label="t('care.followUpReason')"
      :error="errors.motif ?? serverErrors?.motif?.join(' ') ?? null"
      required
    >
      <input :id="id" v-model="form.motif" type="text" maxlength="255" required :aria-describedby="describedBy" :aria-invalid="invalid" />
    </AppField>
    <div class="form-actions">
      <AppButton variant="ghost" :disabled="busy" @click="emit('cancel')">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" :loading="busy">{{ t('care.addFollowUp') }}</AppButton>
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
