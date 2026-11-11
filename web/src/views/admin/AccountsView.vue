<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { accountsApi } from '@/api/accounts'
import { isApiError } from '@/api/errors'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import AppField from '@/components/ui/AppField.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useAsync } from '@/composables/useAsync'
import { errorMessage } from '@/i18n/errors'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferentielStore } from '@/stores/referentiel'

/** @typedef {import('@/api/types').AgentAccount} Account */
/** @typedef {import('@/api/types').ProfileCode} ProfileCode */

/*
 * The admin's view of every account: filter, edit, deactivate. Nothing is
 * deleted: an account stays linked to its referrals and to the audit log.
 * A deactivated account can no longer sign in.
 */

const { t } = useI18n()
const auth = useAuthStore()
const notifications = useNotificationsStore()
const referentiel = useReferentielStore()
const PIN_FORMAT = /^[0-9]{4,6}$/
/** @type {ProfileCode[]} */
const PROFILES = ['asc', 'agent_csb', 'superviseur', 'admin', 'beneficiaire']
/** Profiles that sign in on the web, so may use two-factor login. */
const WEB_PROFILES = ['agent_csb', 'superviseur', 'admin']

// ---------- List and filters ----------

const filters = reactive({ profil: '', region: '', actif: '', q: '' })
const accounts = useAsync(() =>
  accountsApi.list({
    profil: /** @type {ProfileCode | undefined} */ (filters.profil || undefined),
    region: filters.region ? Number(filters.region) : undefined,
    actif: filters.actif === '' ? undefined : filters.actif === 'true',
    q: filters.q.trim() || undefined,
  }),
)
const rows = computed(() =>
  [...(accounts.data.value ?? [])].sort((a, b) =>
    `${a.nom} ${a.prenom}`.localeCompare(`${b.nom} ${b.prenom}`),
  ),
)

/**
 * @param {number | null | undefined} id
 * @returns {string}
 */
function regionName(id) {
  return referentiel.regions.find((r) => r.id === id)?.nom ?? '–'
}

/** @param {Account} account */
const isSelf = (account) => account.id === auth.user?.id

// ---------- Edit ----------

/** @type {import('vue').Ref<Account | null>} */
const editing = ref(null)
const form = reactive({
  nom: '',
  prenom: '',
  phone: '',
  email: '',
  profile_code: /** @type {ProfileCode} */ ('asc'),
  region_id: '',
  csb_id: '',
})
/** @type {Record<string, string | null>} */
const formErrors = reactive({})
const busy = ref(false)
const centres = computed(() =>
  referentiel.facilitiesOf(form.region_id ? Number(form.region_id) : null),
)

/** @param {Account} account */
function openEdit(account) {
  Object.assign(form, {
    nom: account.nom,
    prenom: account.prenom,
    phone: account.phone ?? '',
    email: account.email ?? '',
    profile_code: account.profile.code,
    region_id: account.region_id === null ? '' : String(account.region_id),
    csb_id: account.csb_id ? String(account.csb_id) : '',
  })
  for (const key of Object.keys(formErrors)) formErrors[key] = null
  editing.value = account
}

/** @returns {boolean} */
function checkForm() {
  for (const key of Object.keys(formErrors)) formErrors[key] = null
  const required = t('validation.required')
  if (!form.nom.trim()) formErrors.nom = required
  if (!form.prenom.trim()) formErrors.prenom = required
  if (form.profile_code === 'agent_csb' && !form.csb_id) formErrors.csb_id = t('accounts.centreRequired')
  if (form.profile_code === 'beneficiaire' && !form.region_id) formErrors.region_id = required
  return !Object.values(formErrors).some(Boolean)
}

/**
 * @param {Account} updated
 */
function replaceRow(updated) {
  accounts.data.value = (accounts.data.value ?? []).map((a) => (a.id === updated.id ? updated : a))
}

/** @returns {Promise<void>} */
async function save() {
  const account = editing.value
  if (!account || !checkForm() || busy.value) return
  busy.value = true
  try {
    const updated = await accountsApi.update(account.id, {
      nom: form.nom.trim(),
      prenom: form.prenom.trim(),
      phone: form.phone.trim(),
      email: form.email.trim(),
      ...(isSelf(account) ? {} : { profile_code: form.profile_code }),
      region_id: form.region_id ? Number(form.region_id) : null,
      csb_id: form.profile_code === 'agent_csb' && form.csb_id ? Number(form.csb_id) : null,
    })
    replaceRow(updated)
    notifications.push(t('accounts.saved', { name: `${updated.prenom} ${updated.nom}` }))
    editing.value = null
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation' && Object.keys(caught.fieldErrors).length) {
      for (const [field, messages] of Object.entries(caught.fieldErrors)) formErrors[field] = messages.join(' ')
    } else {
      notifications.push(errorMessage(t, caught), 'error')
    }
  } finally {
    busy.value = false
  }
}

// ---------- Deactivate / reactivate ----------

/** @type {import('vue').Ref<Account | null>} */
const toggling = ref(null)

/** @returns {Promise<void>} */
async function toggleActive() {
  const account = toggling.value
  if (!account || busy.value) return
  busy.value = true
  try {
    const updated = await accountsApi.update(account.id, { is_active: !account.is_active })
    replaceRow(updated)
    notifications.push(
      t(updated.is_active ? 'accounts.reactivated' : 'accounts.deactivated', {
        name: `${updated.prenom} ${updated.nom}`,
      }),
    )
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    busy.value = false
    toggling.value = null
  }
}

// ---------- PIN and two-factor login ----------

/** @type {import('vue').Ref<Account | null>} */
const resetting = ref(null)
const reset = reactive({ pin: '', pinConfirm: '' })
const resetErrors = reactive({ pin: /** @type {string | null} */ (null), pinConfirm: /** @type {string | null} */ (null) })
/** @type {import('vue').Ref<{ name: string, identifiant: string, pin: string } | null>} */
const handover = ref(null)

/** @param {Account} account */
function openReset(account) {
  Object.assign(reset, { pin: '', pinConfirm: '' })
  Object.assign(resetErrors, { pin: null, pinConfirm: null })
  resetting.value = account
}

/** @returns {Promise<void>} */
async function resetPin() {
  const account = resetting.value
  if (!account || busy.value) return
  resetErrors.pin = PIN_FORMAT.test(reset.pin) ? null : t('accessRequest.errors.pin')
  resetErrors.pinConfirm =
    !resetErrors.pin && reset.pin !== reset.pinConfirm ? t('accessRequest.errors.pinMismatch') : null
  if (resetErrors.pin || resetErrors.pinConfirm) return
  busy.value = true
  try {
    await accountsApi.resetPin(account.id, reset.pin)
    handover.value = { name: `${account.prenom} ${account.nom}`, identifiant: account.identifiant, pin: reset.pin }
    resetting.value = null
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation' && caught.fieldErrors.nouveau_pin) {
      resetErrors.pin = caught.fieldErrors.nouveau_pin.join(' ')
    } else {
      notifications.push(errorMessage(t, caught), 'error')
    }
  } finally {
    busy.value = false
  }
}

/** @type {import('vue').Ref<Account | null>} */
const resettingTotp = ref(null)

/** @returns {Promise<void>} */
async function resetTotp() {
  const account = resettingTotp.value
  if (!account || busy.value) return
  busy.value = true
  try {
    await accountsApi.resetTwoFactor(account.id)
    notifications.push(t('accounts.totpDone', { name: `${account.prenom} ${account.nom}` }))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    busy.value = false
    resettingTotp.value = null
  }
}

onMounted(() => {
  void accounts.run()
  void referentiel.load().catch(() => undefined)
})
</script>

<template>
  <PageHeader :title="t('accounts.title')" :intro="t('accounts.intro')">
    <template #actions>
      <AppButton variant="secondary" :loading="accounts.loading.value" @click="accounts.run">{{ t('common.refresh') }}</AppButton>
    </template>
  </PageHeader>

  <InlineAlert v-if="handover" tone="success" class="handover">
    <p class="handover__title">{{ t('agents.handover.resetTitle', { name: handover.name }) }}</p>
    <dl class="handover__facts">
      <div>
        <dt>{{ t('login.identifier') }}</dt>
        <dd class="mono">{{ handover.identifiant }}</dd>
      </div>
      <div>
        <dt>{{ t('login.pin') }}</dt>
        <dd class="mono">{{ handover.pin }}</dd>
      </div>
    </dl>
    <p class="handover__note">{{ t('agents.handover.note') }}</p>
    <AppButton variant="secondary" @click="handover = null">{{ t('agents.handover.done') }}</AppButton>
  </InlineAlert>

  <form class="filters" role="search" @submit.prevent="accounts.run">
    <AppField v-slot="{ id }" :label="t('accounts.filters.profile')">
      <select :id="id" v-model="filters.profil" @change="accounts.run">
        <option value="">{{ t('accounts.filters.allProfiles') }}</option>
        <option v-for="code in PROFILES" :key="code" :value="code">{{ t(`roles.${code}`) }}</option>
      </select>
    </AppField>
    <AppField v-slot="{ id }" :label="t('accounts.filters.region')">
      <select :id="id" v-model="filters.region" @change="accounts.run">
        <option value="">{{ t('stats.allRegions') }}</option>
        <option v-for="r in referentiel.regions" :key="r.id" :value="String(r.id)">{{ r.nom }}</option>
      </select>
    </AppField>
    <AppField v-slot="{ id }" :label="t('agents.state')">
      <select :id="id" v-model="filters.actif" @change="accounts.run">
        <option value="">{{ t('accounts.filters.allStates') }}</option>
        <option value="true">{{ t('agents.active') }}</option>
        <option value="false">{{ t('agents.inactive') }}</option>
      </select>
    </AppField>
    <AppField v-slot="{ id }" :label="t('agents.search')">
      <input :id="id" v-model="filters.q" type="search" autocomplete="off" />
    </AppField>
    <AppButton type="submit" variant="secondary">{{ t('beneficiaries.submit') }}</AppButton>
  </form>

  <div :aria-busy="accounts.loading.value">
    <ErrorState v-if="accounts.error.value" :error="accounts.error.value" retryable @retry="accounts.run" />
    <LoadingState v-else-if="accounts.loading.value && !accounts.data.value" :rows="5" />
    <EmptyState v-else-if="!rows.length" :title="t('accounts.empty')" />
    <template v-else>
      <p class="muted count" aria-live="polite">{{ t('accounts.count', rows.length) }}</p>
      <div class="table-scroll">
        <table class="stack-on-mobile">
          <caption class="visually-hidden">{{ t('accounts.title') }}</caption>
          <thead>
            <tr>
              <th scope="col">{{ t('agents.name') }}</th>
              <th scope="col">{{ t('login.identifier') }}</th>
              <th scope="col">{{ t('accounts.profile') }}</th>
              <th scope="col">{{ t('accounts.place') }}</th>
              <th scope="col">{{ t('agents.state') }}</th>
              <th scope="col"><span class="visually-hidden">{{ t('agents.actions') }}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="account in rows" :key="account.id">
              <th scope="row">
                {{ account.prenom }} {{ account.nom }}
                <span v-if="isSelf(account)" class="muted you">{{ t('accounts.you') }}</span>
              </th>
              <td :data-label="t('login.identifier')" class="mono">{{ account.identifiant }}</td>
              <td :data-label="t('accounts.profile')">{{ t(`roles.${account.profile.code}`) }}</td>
              <td :data-label="t('accounts.place')">
                <template v-if="account.csb_id">{{ referentiel.facilityName(account.csb_id) ?? '–' }}</template>
                <template v-else>{{ regionName(account.region_id) }}</template>
              </td>
              <td :data-label="t('agents.state')">
                <span class="state" :class="account.is_active ? 'state--on' : 'state--off'">
                  {{ account.is_active ? t('agents.active') : t('agents.inactive') }}
                </span>
              </td>
              <td data-label="">
                <div class="actions">
                  <AppButton variant="secondary" @click="openEdit(account)">{{ t('accounts.edit') }}</AppButton>
                  <AppButton variant="ghost" @click="openReset(account)">{{ t('agents.resetPin') }}</AppButton>
                  <AppButton
                    v-if="WEB_PROFILES.includes(account.profile.code)"
                    variant="ghost"
                    @click="resettingTotp = account"
                  >
                    {{ t('accounts.resetTotp') }}
                  </AppButton>
                  <AppButton
                    v-if="!isSelf(account)"
                    :variant="account.is_active ? 'danger' : 'secondary'"
                    @click="toggling = account"
                  >
                    {{ account.is_active ? t('accounts.deactivate') : t('accounts.reactivate') }}
                  </AppButton>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>

  <AppDialog
    :open="editing !== null"
    :title="t('accounts.editTitle', { name: editing ? `${editing.prenom} ${editing.nom}` : '' })"
    @close="editing = null"
  >
    <form id="account-form" class="stack" novalidate @submit.prevent="save">
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.nom')" :error="formErrors.nom ?? null" required>
          <input :id="id" v-model="form.nom" type="text" maxlength="100" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.prenom')" :error="formErrors.prenom ?? null" required>
          <input :id="id" v-model="form.prenom" type="text" maxlength="100" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.phone')" :error="formErrors.phone ?? null" optional>
          <input :id="id" v-model="form.phone" type="tel" maxlength="20" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accounts.email')" :error="formErrors.email ?? null" optional>
          <input :id="id" v-model="form.email" type="email" maxlength="254" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
      <AppField
        v-slot="{ id, describedBy, invalid }"
        :label="t('accounts.profile')"
        :hint="editing && isSelf(editing) ? t('accounts.ownProfile') : undefined"
        :error="formErrors.profile_code ?? null"
      >
        <select :id="id" v-model="form.profile_code" :disabled="!!editing && isSelf(editing)" :aria-describedby="describedBy" :aria-invalid="invalid">
          <option v-for="code in PROFILES" :key="code" :value="code">{{ t(`roles.${code}`) }}</option>
        </select>
      </AppField>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accounts.filters.region')" :error="formErrors.region_id ?? null">
          <select :id="id" v-model="form.region_id" :aria-describedby="describedBy" :aria-invalid="invalid" @change="form.csb_id = ''">
            <option value="">{{ t('common.none') }}</option>
            <option v-for="r in referentiel.regions" :key="r.id" :value="String(r.id)">{{ r.nom }}</option>
          </select>
        </AppField>
        <AppField
          v-if="form.profile_code === 'agent_csb'"
          v-slot="{ id, describedBy, invalid }"
          :label="t('accounts.centre')"
          :error="formErrors.csb_id ?? null"
          required
        >
          <select :id="id" v-model="form.csb_id" :aria-describedby="describedBy" :aria-invalid="invalid">
            <option value="">–</option>
            <option v-for="c in centres" :key="c.id" :value="String(c.id)">
              {{ c.name }} ({{ t(`centreTypes.${c.type_centre}`) }})
            </option>
          </select>
        </AppField>
      </div>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="editing = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="account-form" :loading="busy">{{ t('common.save') }}</AppButton>
    </template>
  </AppDialog>

  <AppDialog
    :open="resetting !== null"
    :title="t('agents.resetTitle', { name: resetting ? `${resetting.prenom} ${resetting.nom}` : '' })"
    @close="resetting = null"
  >
    <form id="account-reset-form" class="stack" novalidate @submit.prevent="resetPin">
      <p class="muted">{{ t('agents.resetIntro') }}</p>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('agents.newPin')" :hint="t('login.pinHelp')" :error="resetErrors.pin" required>
          <input :id="id" v-model="reset.pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.pinConfirm')" :error="resetErrors.pinConfirm" required>
          <input :id="id" v-model="reset.pinConfirm" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="resetting = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="account-reset-form" :loading="busy">{{ t('agents.resetSubmit') }}</AppButton>
    </template>
  </AppDialog>

  <ConfirmDialog
    :open="toggling !== null"
    :title="toggling?.is_active ? t('accounts.deactivate') : t('accounts.reactivate')"
    :message="
      toggling
        ? t(toggling.is_active ? 'accounts.confirmDeactivate' : 'accounts.confirmReactivate', {
            name: `${toggling.prenom} ${toggling.nom}`,
          })
        : ''
    "
    :confirm-label="toggling?.is_active ? t('accounts.deactivate') : t('accounts.reactivate')"
    :danger="!!toggling?.is_active"
    :busy="busy"
    @confirm="toggleActive"
    @cancel="toggling = null"
  />

  <ConfirmDialog
    :open="resettingTotp !== null"
    :title="t('accounts.resetTotp')"
    :message="resettingTotp ? t('accounts.confirmTotp', { name: `${resettingTotp.prenom} ${resettingTotp.nom}` }) : ''"
    :confirm-label="t('accounts.resetTotp')"
    :busy="busy"
    @confirm="resetTotp"
    @cancel="resettingTotp = null"
  />
</template>

<style scoped>
.handover {
  margin-bottom: var(--space-5);
}

.handover__title {
  font-weight: 700;
  margin: 0 0 var(--space-3);
}

.handover__facts {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3) var(--space-6);
  margin: 0 0 var(--space-3);
}

.handover__facts dd {
  margin: 0;
  font-size: var(--text-lg);
  font-weight: 700;
  letter-spacing: 0.05em;
}

.handover__note {
  margin: 0 0 var(--space-3);
}

.filters {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 11rem), 1fr));
  align-items: end;
  gap: var(--space-3);
  margin-bottom: var(--space-4);
}

.count {
  font-size: var(--text-sm);
  margin: 0 0 var(--space-2);
}

.mono {
  font-family: var(--font-code);
}

.you {
  font-size: var(--text-sm);
  font-weight: 400;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  justify-content: flex-end;
}

.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
  gap: var(--space-4);
}

.state {
  display: inline-block;
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius-pill);
  font-size: var(--text-sm);
  font-weight: 700;
}

.state--on {
  background: var(--sky-100);
}

.state--off {
  background: var(--line);
  color: var(--ink-muted);
}
</style>
