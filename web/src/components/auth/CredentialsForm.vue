<script setup>
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'

const props = defineProps({ busy: { type: Boolean, required: true } })
/** submit(identifiant: string, pin: string) */
const emit = defineEmits(['submit'])

const { t } = useI18n()
const form = reactive({ identifiant: '', pin: '' })
/** @type {{ identifiant: string | null, pin: string | null }} */
const errors = reactive({ identifiant: null, pin: null })
/** @type {import('vue').Ref<HTMLInputElement | null>} */
const identifiantInput = ref(null)

function submit() {
  errors.identifiant = form.identifiant.trim() ? null : t('login.errors.required')
  errors.pin = form.pin ? null : t('login.errors.required')
  if (errors.identifiant || errors.pin || props.busy) return
  emit('submit', form.identifiant.trim(), form.pin)
}

defineExpose({ focus: () => identifiantInput.value?.focus() })
</script>

<template>
  <form class="stack" novalidate @submit.prevent="submit">
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.identifier')" :hint="t('login.identifierHelp')" :error="errors.identifiant" required>
      <input
        :id="id"
        ref="identifiantInput"
        v-model="form.identifiant"
        type="text"
        name="identifiant"
        autocomplete="username"
        required
        :aria-describedby="describedBy"
        :aria-invalid="invalid"
      />
    </AppField>
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.pin')" :hint="t('login.pinHelp')" :error="errors.pin" required>
      <input
        :id="id"
        v-model="form.pin"
        type="password"
        name="pin"
        inputmode="numeric"
        autocomplete="current-password"
        required
        :aria-describedby="describedBy"
        :aria-invalid="invalid"
      />
    </AppField>
    <AppButton type="submit" block :loading="busy">
      {{ busy ? t('login.submitting') : t('login.submit') }}
    </AppButton>
  </form>
</template>
