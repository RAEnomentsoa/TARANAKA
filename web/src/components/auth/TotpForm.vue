<script setup lang="ts">
import QRCode from 'qrcode'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'

/** Second login step: a 6-digit TOTP code, with the QR code on first use. */
const props = defineProps<{ busy: boolean; enrolment: boolean; otpauthUri: string | null }>()
const emit = defineEmits<{ submit: [code: string]; back: [] }>()

const { t } = useI18n()
const code = ref('')
const error = ref<string | null>(null)
const qrDataUrl = ref<string | null>(null)
const input = ref<HTMLInputElement | null>(null)

/** The secret, for people who cannot scan (otpauth://totp/...?secret=XXX). */
const secret = computed(() => {
  if (!props.otpauthUri) return null
  try {
    return new URL(props.otpauthUri).searchParams.get('secret')
  } catch {
    return null
  }
})
const secretGroups = computed(() => secret.value?.match(/.{1,4}/g)?.join(' ') ?? '')

watch(
  () => props.otpauthUri,
  async (uri) => {
    try {
      qrDataUrl.value = uri ? await QRCode.toDataURL(uri, { margin: 1, width: 224, color: { dark: '#0f2a3dff', light: '#ffffffff' } }) : null
    } catch {
      // No QR code: the key below can still be typed by hand.
      qrDataUrl.value = null
    }
  },
  { immediate: true },
)

function onInput(event: Event): void {
  // Keep digits only: codes are often pasted as "123 456".
  code.value = (event.target as HTMLInputElement).value.replace(/\D/g, '').slice(0, 6)
}

function submit(): void {
  error.value = /^\d{6}$/.test(code.value) ? null : t('login.errors.totpFormat')
  if (error.value || props.busy) return
  emit('submit', code.value)
}

onMounted(() => input.value?.focus())
defineExpose({ clear: () => (code.value = '') })
</script>

<template>
  <div class="stack">
    <div v-if="enrolment && (qrDataUrl || secret)" class="enrol">
      <img v-if="qrDataUrl" :src="qrDataUrl" :alt="t('login.enrollQrAlt')" width="224" height="224" class="enrol__qr" />
      <div v-if="secret">
        <p class="muted">{{ t('login.enrollManual') }}</p>
        <p class="enrol__secret">{{ secretGroups }}</p>
      </div>
    </div>
    <form class="stack" novalidate @submit.prevent="submit">
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.totpCode')" :hint="t('login.totpHelp')" :error="error" required>
        <input
          :id="id"
          ref="input"
          :value="code"
          class="otp"
          type="text"
          name="code"
          inputmode="numeric"
          autocomplete="one-time-code"
          maxlength="6"
          pattern="[0-9]{6}"
          required
          :aria-describedby="describedBy"
          :aria-invalid="invalid"
          @input="onInput"
        />
      </AppField>
      <AppButton type="submit" block :loading="busy">
        {{ enrolment ? t('login.enrollSubmit') : t('login.totpSubmit') }}
      </AppButton>
      <AppButton variant="ghost" block :disabled="busy" @click="emit('back')">{{ t('login.back') }}</AppButton>
    </form>
  </div>
</template>

<style scoped>
.otp {
  font-family: var(--font-code);
  font-size: var(--text-xl);
  letter-spacing: 0.5em;
  text-align: center;
}

.enrol {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-4);
  align-items: center;
}

.enrol__qr {
  border: 6px solid var(--sky-100);
  border-radius: var(--radius-md);
}

.enrol__secret {
  font-family: var(--font-code);
  font-size: var(--text-md);
  word-break: break-all;
  background: var(--sky-50);
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-sm);
}
</style>
