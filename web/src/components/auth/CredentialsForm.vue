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
const showPin = ref(false)

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
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        required
        :aria-describedby="describedBy"
        :aria-invalid="invalid"
      />
    </AppField>
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.pin')" :hint="t('login.pinHelp')" :error="errors.pin" required>
      <div class="pin">
        <input
          :id="id"
          v-model="form.pin"
          :type="showPin ? 'text' : 'password'"
          name="pin"
          inputmode="numeric"
          autocomplete="current-password"
          class="pin__input"
          required
          :aria-describedby="describedBy"
          :aria-invalid="invalid"
        />
        <button
          type="button"
          class="pin__toggle"
          :aria-pressed="showPin"
          :aria-label="showPin ? t('login.hidePin') : t('login.showPin')"
          :title="showPin ? t('login.hidePin') : t('login.showPin')"
          @click="showPin = !showPin"
        >
          <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
            <path
              d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linejoin="round"
            />
            <circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" stroke-width="1.8" />
            <path v-if="showPin" d="M4 20 20 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />
          </svg>
        </button>
      </div>
    </AppField>
    <AppButton type="submit" block :loading="busy" class="submit">
      {{ busy ? t('login.submitting') : t('login.submit') }}
    </AppButton>
  </form>
</template>

<style scoped>
.pin {
  position: relative;
}

/* Room for the button, so the dots never run under it. */
.pin .pin__input {
  padding-right: calc(var(--target) + var(--space-1));
  letter-spacing: 0.2em;
}

.pin__toggle {
  position: absolute;
  top: 0;
  right: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: var(--target);
  height: 100%;
  border: none;
  border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
  background: none;
  color: var(--ink-muted);
  cursor: pointer;
  transition: color var(--duration) var(--easing);
}

.pin__toggle:hover {
  color: var(--primary);
}

.submit {
  margin-top: var(--space-5);
}
</style>
