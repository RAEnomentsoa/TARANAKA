<script setup lang="ts">
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
const error = ref<string | null>(null)
const credentials = ref<InstanceType<typeof CredentialsForm> | null>(null)
const totp = ref<InstanceType<typeof TotpForm> | null>(null)

const onTotpStep = computed(() => auth.step !== 'credentials')
const heading = computed(() => {
  if (auth.step === 'enrolement') return t('login.enrollTitle')
  if (auth.step === 'verification') return t('login.totpTitle')
  return t('login.title')
})

async function finish(): Promise<void> {
  // A profile with no web screen (ASC, beneficiaire) is turned away here.
  if (auth.homeRoute === 'no-access') {
    await auth.logout()
    error.value = t('login.errors.profile')
    return
  }
  const redirect = typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/') ? route.query.redirect : null
  await router.replace(redirect ?? { name: auth.homeRoute })
}

async function onCredentials(identifiant: string, pin: string): Promise<void> {
  busy.value = true
  error.value = null
  try {
    const next = await auth.submitCredentials(identifiant, pin)
    if (next === 'done') await finish()
  } catch (caught) {
    error.value = loginErrorMessage(t, caught, 'credentials')
  } finally {
    busy.value = false
  }
}

async function onTotp(code: string): Promise<void> {
  busy.value = true
  error.value = null
  try {
    await auth.submitTotp(code)
    await finish()
  } catch (caught) {
    error.value = loginErrorMessage(t, caught, 'totp')
    totp.value?.clear()
  } finally {
    busy.value = false
  }
}

async function back(): Promise<void> {
  auth.resetChallenge()
  error.value = null
  await nextTick()
  credentials.value?.focus()
}
</script>

<template>
  <div class="login">
    <aside class="login__aside">
      <div class="login__brand">
        <BrandMark />
        <span class="login__name">{{ t('app.name') }}</span>
      </div>
      <p class="login__tagline">{{ t('app.tagline') }}</p>
      <svg class="login__curve" viewBox="0 0 320 160" aria-hidden="true" preserveAspectRatio="none">
        <path d="M0 140C70 136 110 110 150 78S240 18 320 14" fill="none" stroke="var(--white)" stroke-width="5" stroke-linecap="round" />
        <path d="M0 150C80 148 120 128 165 100S250 48 320 44" fill="none" stroke="var(--sky-400)" stroke-width="3" stroke-dasharray="2 10" stroke-linecap="round" />
      </svg>
    </aside>

    <main class="login__main">
      <div class="login__lang"><LanguageSwitch /></div>
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
  display: grid;
  grid-template-columns: minmax(16rem, 2fr) 3fr;
  background: var(--white);
}

.login__aside {
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: var(--space-4);
  padding: var(--space-7) var(--space-6);
  background: linear-gradient(170deg, var(--sky-100), var(--sky-300));
}

.login__brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.login__name {
  font-size: var(--text-2xl);
  font-weight: 700;
  letter-spacing: 0.08em;
  color: var(--ink);
}

.login__tagline {
  font-size: var(--text-lg);
  color: var(--ink);
  max-width: 22ch;
}

.login__curve {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 40%;
}

.login__main {
  display: flex;
  flex-direction: column;
  padding: var(--space-5);
}

.login__lang {
  align-self: flex-end;
}

.login__card {
  width: 100%;
  max-width: 26rem;
  margin: auto;
  padding: var(--space-6) 0;
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

@media (max-width: 48rem) {
  .login {
    grid-template-columns: 1fr;
  }

  .login__aside {
    padding: var(--space-5) var(--space-4) var(--space-6);
  }

  .login__tagline {
    font-size: var(--text-md);
    margin: 0;
  }

  .login__curve {
    height: 50%;
    opacity: 0.6;
  }

  .login__main {
    padding: var(--space-4);
  }

  .login__card {
    padding-top: var(--space-4);
  }
}
</style>
