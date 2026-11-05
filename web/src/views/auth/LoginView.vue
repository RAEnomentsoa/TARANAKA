<script setup>
import { computed, nextTick, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import CredentialsForm from '@/components/auth/CredentialsForm.vue'
import TotpForm from '@/components/auth/TotpForm.vue'
import BrandMark from '@/components/layout/BrandMark.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LanguageSwitch from '@/components/ui/LanguageSwitch.vue'
import { loginErrorMessage } from '@/i18n/errors'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const busy = ref(false)
/** @type {import('vue').Ref<string | null>} */
const error = ref(null)
/** @type {import('vue').Ref<InstanceType<typeof CredentialsForm> | null>} */
const credentials = ref(null)
/** @type {import('vue').Ref<InstanceType<typeof TotpForm> | null>} */
const totp = ref(null)

const onTotpStep = computed(() => auth.step !== 'credentials')
const heading = computed(() => {
  if (auth.step === 'enrolement') return t('login.enrollTitle')
  if (auth.step === 'verification') return t('login.totpTitle')
  return t('login.title')
})

/** @returns {Promise<void>} */
async function finish() {
  const redirect =
    typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/') ? route.query.redirect : null
  await router.replace(redirect ?? { name: auth.homeRoute })
}

/**
 * @param {string} identifiant
 * @param {string} pin
 * @returns {Promise<void>}
 */
async function onCredentials(identifiant, pin) {
  busy.value = true
  error.value = null
  try {
    const next = await auth.submitCredentials(identifiant, pin)
    if (next === 'done') await finish()
  } catch (caught) {
    error.value = loginErrorMessage(t, caught)
  } finally {
    busy.value = false
  }
}

/**
 * @param {string} code
 * @returns {Promise<void>}
 */
async function onTotp(code) {
  busy.value = true
  error.value = null
  try {
    await auth.submitTotp(code)
    await finish()
  } catch (caught) {
    error.value = loginErrorMessage(t, caught)
    totp.value?.clear()
  } finally {
    busy.value = false
  }
}

/** @returns {Promise<void>} */
async function back() {
  auth.resetChallenge()
  error.value = null
  await nextTick()
  credentials.value?.focus()
}
</script>

<template>
  <div class="login">
    <header class="login__top">
      <div class="login__brand">
        <BrandMark />
        <span class="login__brand-text">
          <span class="login__name">{{ t('app.name') }}</span>
          <span class="login__tagline">{{ t('app.tagline') }}</span>
        </span>
      </div>
      <LanguageSwitch />
    </header>

    <main class="login__main">
      <div class="login__card">
        <p class="login__step muted">{{ onTotpStep ? t('login.stepTotp') : t('login.stepCredentials') }}</p>
        <h1 tabindex="-1" data-page-title>{{ heading }}</h1>
        <p class="muted">
          {{ auth.step === 'enrolement' ? t('login.enrollIntro') : onTotpStep ? t('login.totpIntro') : t('login.intro') }}
        </p>

        <InlineAlert v-if="error" tone="error" class="login__error">{{ error }}</InlineAlert>

        <TotpForm
          v-if="onTotpStep"
          ref="totp"
          :busy="busy"
          :enrolment="auth.step === 'enrolement'"
          :otpauth-uri="auth.otpauthUri"
          @submit="onTotp"
          @back="back"
        />
        <CredentialsForm v-else ref="credentials" :busy="busy" @submit="onCredentials" />
      </div>
    </main>
  </div>
</template>

<style scoped>
.login {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: var(--sky-50);
}

.login__top {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-5);
  background: var(--white);
  border-bottom: 1px solid var(--sky-200);
}

.login__brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.login__brand-text {
  display: flex;
  flex-direction: column;
  line-height: 1.2;
}

.login__name {
  font-weight: 700;
  font-size: var(--text-md);
  letter-spacing: 0.06em;
}

.login__tagline {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.login__main {
  flex: 1;
  display: flex;
  justify-content: center;
  padding: var(--space-6) var(--space-4);
}

.login__card {
  width: 100%;
  max-width: 28rem;
  align-self: flex-start;
  padding: var(--space-6);
  background: var(--white);
  border: 1px solid var(--sky-200);
  border-top: 4px solid var(--primary);
  border-radius: var(--radius-md);
}

.login__card h1:focus {
  outline: none;
}

.login__step {
  font-size: var(--text-sm);
  font-weight: 700;
  margin-bottom: var(--space-2);
}

.login__error {
  margin-bottom: var(--space-4);
}

@media (max-width: 30rem) {
  .login__top {
    padding: var(--space-3) var(--space-4);
  }

  .login__main {
    padding: var(--space-4) 0 0;
  }

  .login__card {
    padding: var(--space-5) var(--space-4);
    border-radius: 0;
    border-inline: none;
  }
}
</style>
