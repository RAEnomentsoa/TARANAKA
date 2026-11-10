<script setup>
import { computed, nextTick, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import CredentialsForm from '@/components/auth/CredentialsForm.vue'
import TotpForm from '@/components/auth/TotpForm.vue'
import logo from '@/assets/logo_v1.png'
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
    <aside class="login__aside">
      <img class="login__logo" :src="logo" width="500" height="500" :alt="t('app.logoAlt')" />
      <div class="login__pitch">
        <p class="login__tagline">{{ t('app.tagline') }}</p>
        <p class="login__audience">{{ t('login.intro') }}</p>
      </div>
    </aside>

    <main class="login__main">
      <div class="login__lang"><LanguageSwitch /></div>

      <div class="login__panel">
        <div class="login__mobile-brand">
          <img class="login__mobile-logo" :src="logo" width="500" height="500" :alt="t('app.logoAlt')" />
        </div>

        <div class="login__steps" aria-hidden="true">
          <span class="login__step-dot login__step-dot--done" />
          <span class="login__step-dot" :class="{ 'login__step-dot--done': onTotpStep }" />
        </div>
        <p class="login__step">{{ onTotpStep ? t('login.stepTotp') : t('login.stepCredentials') }}</p>
        <h1 tabindex="-1" data-page-title>{{ heading }}</h1>
        <p v-if="onTotpStep" class="login__intro muted">
          {{ auth.step === 'enrolement' ? t('login.enrollIntro') : t('login.totpIntro') }}
        </p>
        <p v-else class="login__intro login__intro--mobile muted">{{ t('login.intro') }}</p>

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

        <p v-if="!onTotpStep" class="login__request">
          {{ t('login.noAccount') }}
          <RouterLink :to="{ name: 'access-request' }">{{ t('login.requestAccess') }}</RouterLink>
        </p>
      </div>
    </main>
  </div>
</template>

<style scoped>
/*
 * Two columns on wide screens: a flat brand panel and the form. One column
 * on phones, with the brand above the form. No card around the form: the
 * page itself is the surface.
 */
.login {
  min-height: 100vh;
  display: grid;
  grid-template-columns: minmax(20rem, 5fr) 7fr;
  background: var(--white);
}

.login__aside {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--space-5);
  padding: var(--space-6);
  /* A soft light behind the logo, then the page's sky blue. */
  background: radial-gradient(circle at 50% 40%, var(--white) 0, var(--white) 28%, var(--sky-100) 70%);
  text-align: center;
}

.login__logo {
  width: min(100%, 26rem);
  height: auto;
  animation: logo-in 600ms var(--easing) backwards;
}

.login__mobile-logo {
  width: 9rem;
  height: auto;
  animation: logo-in 600ms var(--easing) backwards;
}

.login__pitch {
  max-width: 26rem;
  animation: rise-in 500ms 150ms var(--easing) backwards;
}

.login__tagline {
  font-size: var(--text-xl);
  font-weight: 700;
  line-height: 1.2;
  margin-bottom: var(--space-3);
}

.login__audience {
  color: var(--ink-muted);
  margin: 0;
}

.login__main {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--space-7) var(--space-5);
}

.login__lang {
  position: absolute;
  top: var(--space-4);
  right: var(--space-5);
}

.login__panel {
  width: 100%;
  max-width: 24rem;
}

.login__panel h1 {
  font-size: var(--text-xl);
  margin-bottom: var(--space-5);
}

.login__panel h1:focus {
  outline: none;
}

.login__mobile-brand {
  display: none;
  justify-content: center;
  margin-bottom: var(--space-4);
}

.login__steps {
  display: flex;
  gap: var(--space-1);
  margin-bottom: var(--space-3);
}

.login__step-dot {
  width: 2rem;
  height: 0.25rem;
  border-radius: var(--radius-pill);
  background: var(--line);
  transition: background-color var(--duration) var(--easing);
}

.login__step-dot--done {
  background: var(--primary);
}

.login__step {
  margin: 0 0 var(--space-2);
  font-size: var(--text-sm);
  font-weight: 700;
  color: var(--ink-muted);
}

/* Pulled up under the title it explains. */
.login__intro {
  margin: calc(-1 * var(--space-3)) 0 var(--space-5);
}

.login__intro--mobile {
  display: none;
}

.login__error {
  margin-bottom: var(--space-4);
}

.login__request {
  margin: var(--space-5) 0 0;
  padding-top: var(--space-4);
  border-top: 1px solid var(--line);
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.login__request a {
  font-weight: 700;
}

@media (max-width: 56rem) {
  .login {
    grid-template-columns: minmax(0, 1fr);
  }

  .login__aside {
    display: none;
  }

  .login__mobile-brand {
    display: flex;
  }

  .login__intro--mobile {
    display: block;
  }

  /* Three languages do not fit beside the brand on a phone: the switch gets its own row. */
  .login__main {
    flex-direction: column;
    align-items: center;
    justify-content: flex-start;
    gap: var(--space-5);
    padding: var(--space-4) var(--space-4) var(--space-6);
  }

  .login__lang {
    position: static;
    align-self: flex-end;
  }
}
</style>
