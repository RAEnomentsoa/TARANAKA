<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import { accessRequestsApi } from '@/api/accounts'
import { isApiError } from '@/api/errors'
import BrandMark from '@/components/layout/BrandMark.vue'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LanguageSwitch from '@/components/ui/LanguageSwitch.vue'
import { useAsync } from '@/composables/useAsync'
import { errorMessage } from '@/i18n/errors'

/** @typedef {import('@/api/types').AccessRequestForm} AccessRequestForm */
/** @typedef {import('@/api/types').RequestedProfile} RequestedProfile */

/*
 * Public page (D15): a nurse, a doctor or a supervisor asks for a web
 * account. Nothing opens before an administrator approves. Community agents
 * are not offered here: their supervisor creates their account.
 */

const { t } = useI18n()
const options = useAsync(() => accessRequestsApi.options())

/** @type {RequestedProfile[]} */
const PROFILES = ['agent_csb', 'superviseur']
const PIN_FORMAT = /^[0-9]{4,6}$/
const EMAIL_FORMAT = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

const form = reactive({
  /** @type {RequestedProfile | ''} */
  profil_demande: '',
  nom: '',
  prenom: '',
  phone: '',
  email: '',
  fonction: '',
  /** @type {number | ''} */
  region_id: '',
  /** @type {number | ''} */
  csb_id: '',
  identifiant: '',
  pin: '',
  pinConfirm: '',
  message: '',
})

/** @type {Record<string, string | null>} */
const errors = reactive({})
const busy = ref(false)
/** @type {import('vue').Ref<string | null>} */
const failure = ref(null)
const sent = ref(false)

const regions = computed(() => options.data.value?.regions ?? [])
const centres = computed(() =>
  (options.data.value?.centres ?? []).filter((c) => form.region_id === '' || c.region_id === form.region_id),
)
const isNurse = computed(() => form.profil_demande === 'agent_csb')

// A centre from another region can't stay selected.
watch(
  () => form.region_id,
  () => {
    if (form.csb_id !== '' && !centres.value.some((c) => c.id === form.csb_id)) form.csb_id = ''
  },
)

/** @returns {boolean} */
function check() {
  for (const key of Object.keys(errors)) errors[key] = null
  const required = t('validation.required')
  if (!form.profil_demande) errors.profil_demande = required
  if (!form.nom.trim()) errors.nom = required
  if (!form.prenom.trim()) errors.prenom = required
  if (!form.phone.trim()) errors.phone = required
  if (form.email.trim() && !EMAIL_FORMAT.test(form.email.trim())) errors.email = t('accessRequest.errors.email')
  if (isNurse.value && form.csb_id === '') errors.csb_id = required
  if (!form.identifiant.trim()) errors.identifiant = required
  if (!PIN_FORMAT.test(form.pin)) errors.pin = t('accessRequest.errors.pin')
  else if (form.pin !== form.pinConfirm) errors.pinConfirm = t('accessRequest.errors.pinMismatch')
  return !Object.values(errors).some(Boolean)
}

/** @returns {AccessRequestForm} */
function payload() {
  return {
    profil_demande: /** @type {RequestedProfile} */ (form.profil_demande),
    nom: form.nom.trim(),
    prenom: form.prenom.trim(),
    phone: form.phone.trim(),
    email: form.email.trim(),
    fonction: form.fonction.trim(),
    region_id: form.region_id === '' ? null : form.region_id,
    csb_id: isNurse.value && form.csb_id !== '' ? form.csb_id : null,
    identifiant: form.identifiant.trim(),
    pin: form.pin,
    message: form.message.trim(),
  }
}

/** @returns {Promise<void>} */
async function submit() {
  failure.value = null
  if (!check() || busy.value) return
  busy.value = true
  try {
    await accessRequestsApi.submit(payload())
    sent.value = true
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation') {
      for (const [field, messages] of Object.entries(caught.fieldErrors)) errors[field] = messages.join(' ')
      failure.value = t('errors.validation')
    } else if (isApiError(caught) && caught.kind === 'throttled') {
      failure.value = t('accessRequest.errors.throttled')
    } else {
      failure.value = errorMessage(t, caught)
    }
  } finally {
    busy.value = false
  }
}

/**
 * @param {string} field
 * @returns {string | null}
 */
const err = (field) => errors[field] ?? null

onMounted(options.run)
</script>

<template>
  <div class="request">
    <header class="request__top">
      <RouterLink :to="{ name: 'login' }" class="request__brand">
        <BrandMark />
        <span class="request__name">{{ t('app.name') }}</span>
      </RouterLink>
      <LanguageSwitch />
    </header>

    <main class="request__main">
      <div v-if="sent" class="request__panel stack" role="status">
        <h1 tabindex="-1" data-page-title>{{ t('accessRequest.sentTitle') }}</h1>
        <p>{{ t('accessRequest.sentBody') }}</p>
        <p class="muted">{{ t('accessRequest.sentNext') }}</p>
        <RouterLink :to="{ name: 'login' }" class="request__back">{{ t('accessRequest.backToLogin') }}</RouterLink>
      </div>

      <div v-else class="request__panel">
        <RouterLink :to="{ name: 'login' }" class="request__back request__back--arrow">{{ t('accessRequest.backToLogin') }}</RouterLink>
        <h1 tabindex="-1" data-page-title>{{ t('accessRequest.title') }}</h1>
        <p class="muted">{{ t('accessRequest.intro') }}</p>
        <InlineAlert tone="info" class="request__note">{{ t('accessRequest.agentsNote') }}</InlineAlert>

        <InlineAlert v-if="options.error.value" tone="error" class="request__note">
          {{ errorMessage(t, options.error.value) }}
        </InlineAlert>
        <InlineAlert v-if="failure" tone="error" class="request__note">{{ failure }}</InlineAlert>

        <form class="request__form" novalidate @submit.prevent="submit">
          <fieldset class="group">
            <legend>{{ t('accessRequest.sections.role') }}</legend>
            <div class="choices" :aria-invalid="Boolean(err('profil_demande'))">
              <label v-for="code in PROFILES" :key="code" class="choice">
                <input v-model="form.profil_demande" type="radio" name="profil_demande" :value="code" />
                <span>
                  <strong>{{ t(`roles.${code}`) }}</strong>
                  <span class="choice__hint">{{ t(`accessRequest.profileHints.${code}`) }}</span>
                </span>
              </label>
            </div>
            <p v-if="err('profil_demande')" class="group__error">{{ err('profil_demande') }}</p>

            <AppField
              v-slot="{ id, describedBy, invalid }"
              :label="isNurse ? t('accessRequest.fields.region') : t('accessRequest.fields.supervisedRegion')"
              :hint="isNurse ? undefined : t('accessRequest.hints.nationalRegion')"
              :error="err('region_id')"
              :optional="!isNurse"
            >
              <select :id="id" v-model="form.region_id" :aria-describedby="describedBy" :aria-invalid="invalid">
                <option value="">{{ isNurse ? t('accessRequest.allRegions') : t('accessRequest.national') }}</option>
                <option v-for="region in regions" :key="region.id" :value="region.id">{{ region.nom }}</option>
              </select>
            </AppField>

            <AppField
              v-if="isNurse"
              v-slot="{ id, describedBy, invalid }"
              :label="t('accessRequest.fields.centre')"
              :error="err('csb_id')"
              required
            >
              <select :id="id" v-model="form.csb_id" required :aria-describedby="describedBy" :aria-invalid="invalid">
                <option value="" disabled>{{ t('accessRequest.chooseCentre') }}</option>
                <option v-for="centre in centres" :key="centre.id" :value="centre.id">
                  {{ centre.name }} ({{ t(`centreTypes.${centre.type_centre}`) }})
                </option>
              </select>
            </AppField>

            <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.fonction')" :error="err('fonction')" optional>
              <input :id="id" v-model="form.fonction" type="text" maxlength="150" :aria-describedby="describedBy" :aria-invalid="invalid" />
            </AppField>
          </fieldset>

          <fieldset class="group">
            <legend>{{ t('accessRequest.sections.identity') }}</legend>
            <div class="row">
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.nom')" :error="err('nom')" required>
                <input :id="id" v-model="form.nom" type="text" autocomplete="family-name" maxlength="100" required :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.prenom')" :error="err('prenom')" required>
                <input :id="id" v-model="form.prenom" type="text" autocomplete="given-name" maxlength="100" required :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
            </div>
            <div class="row">
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.phone')" :hint="t('accessRequest.hints.phone')" :error="err('phone')" required>
                <input :id="id" v-model="form.phone" type="tel" autocomplete="tel" maxlength="20" required :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.email')" :error="err('email')" optional>
                <input :id="id" v-model="form.email" type="email" autocomplete="email" :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
            </div>
          </fieldset>

          <fieldset class="group">
            <legend>{{ t('accessRequest.sections.login') }}</legend>
            <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.identifier')" :hint="t('accessRequest.hints.identifiant')" :error="err('identifiant')" required>
              <input :id="id" v-model="form.identifiant" type="text" autocomplete="username" autocapitalize="none" autocorrect="off" spellcheck="false" maxlength="50" required :aria-describedby="describedBy" :aria-invalid="invalid" />
            </AppField>
            <div class="row">
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.pin')" :hint="t('login.pinHelp')" :error="err('pin')" required>
                <input :id="id" v-model="form.pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
              <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.pinConfirm')" :error="err('pinConfirm')" required>
                <input :id="id" v-model="form.pinConfirm" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
              </AppField>
            </div>
          </fieldset>

          <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.message')" :hint="t('accessRequest.hints.message')" :error="err('message')" optional>
            <textarea :id="id" v-model="form.message" maxlength="1000" :aria-describedby="describedBy" :aria-invalid="invalid" />
          </AppField>

          <p class="muted request__after">{{ t('accessRequest.afterSubmit') }}</p>
          <AppButton type="submit" block :loading="busy">{{ t('accessRequest.submit') }}</AppButton>
        </form>
      </div>
    </main>
  </div>
</template>

<style scoped>
.request {
  min-height: 100vh;
  background: var(--white);
}

.request__top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: var(--space-3);
  padding: var(--space-4) var(--space-5);
  border-bottom: 1px solid var(--line);
}

.request__brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  color: inherit;
  text-decoration: none;
}

.request__name {
  font-weight: 700;
  letter-spacing: 0.06em;
}

.request__main {
  display: flex;
  justify-content: center;
  padding: var(--space-6) var(--space-4) var(--space-7);
}

.request__panel {
  width: 100%;
  max-width: 40rem;
}

.request__panel h1 {
  margin-top: var(--space-3);
}

.request__panel h1:focus {
  outline: none;
}

.request__back {
  font-weight: 700;
}

.request__back--arrow::before {
  content: '← ';
}

.request__note {
  margin-bottom: var(--space-4);
}

.request__form {
  display: grid;
  gap: var(--space-5);
}

.group {
  display: grid;
  gap: var(--space-4);
  margin: 0;
  padding: 0;
  border: none;
}

.group legend {
  font-size: var(--text-md);
  font-weight: 700;
  margin-bottom: var(--space-3);
  padding: 0;
}

.group__error {
  margin: 0;
  color: var(--rouge-ink);
  font-weight: 700;
  font-size: var(--text-sm);
}

.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
  gap: var(--space-4);
}

.choices {
  display: grid;
  gap: var(--space-2);
}

.choice {
  display: flex;
  align-items: flex-start;
  gap: var(--space-3);
  min-height: var(--target);
  padding: var(--space-3);
  border: 1px solid var(--field-border);
  border-radius: var(--radius-sm);
  cursor: pointer;
}

.choice:has(input:checked) {
  border: 2px solid var(--primary);
  background: var(--sky-50);
}

.choice input {
  width: 1.25rem;
  height: 1.25rem;
  margin-top: 0.15rem;
  accent-color: var(--primary);
  flex-shrink: 0;
}

.choice__hint {
  display: block;
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.request__after {
  margin: 0;
}
</style>
