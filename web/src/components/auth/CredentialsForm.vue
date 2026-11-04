<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'

const props = defineProps<{ busy: boolean }>()
const emit = defineEmits<{ submit: [identifiant: string, pin: string] }>()

const { t } = useI18n()
const form = reactive({ identifiant: '', pin: '' })
const errors = reactive<{ identifiant: string | null; pin: string | null }>({ identifiant: null, pin: null })
const identifiantInput = ref<HTMLInputElement | null>(null)

function submit(): void {
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
