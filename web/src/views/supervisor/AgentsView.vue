<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { agentsApi } from '@/api/accounts'
import { isApiError } from '@/api/errors'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import AppField from '@/components/ui/AppField.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { errorMessage } from '@/i18n/errors'
import { useNotificationsStore } from '@/stores/notifications'

/** @typedef {import('@/api/types').AgentAccount} AgentAccount */

/*
 * The supervisor's community agents (spec §2, §8, D1). The server lists only
 * the ASC accounts of the supervisor's region, creates new ones there, and
 * lets the supervisor reset a forgotten PIN. Identity only: no health data.
 */

const { t } = useI18n()
const fmt = useFormatters()
const notifications = useNotificationsStore()
const PIN_FORMAT = /^[0-9]{4,6}$/

const agents = useAsync(() => agentsApi.list())
const search = ref('')

const rows = computed(() => {
  const query = search.value.trim().toLowerCase()
  const list = [...(agents.data.value ?? [])].sort((a, b) =>
    `${a.nom} ${a.prenom}`.localeCompare(`${b.nom} ${b.prenom}`),
  )
  if (!query) return list
  return list.filter((a) =>
    [a.nom, a.prenom, a.identifiant, a.phone].some((v) => (v ?? '').toLowerCase().includes(query)),
  )
})

/**
 * Identifiant and PIN to hand over to the agent. Shown once, after a
 * creation or a reset: the server never sends a PIN back.
 * @type {import('vue').Ref<{ name: string, identifiant: string, pin: string, reset: boolean } | null>}
 */
const handover = ref(null)
const busy = ref(false)

// ---------- Create ----------

const creating = ref(false)
const form = reactive({ nom: '', prenom: '', phone: '', identifiant: '', pin: '', pinConfirm: '' })
/** @type {Record<string, string | null>} */
const formErrors = reactive({})

function openCreate() {
  Object.assign(form, { nom: '', prenom: '', phone: '', identifiant: '', pin: '', pinConfirm: '' })
  for (const key of Object.keys(formErrors)) formErrors[key] = null
  creating.value = true
}

/** @returns {boolean} */
function checkForm() {
  for (const key of Object.keys(formErrors)) formErrors[key] = null
  const required = t('validation.required')
  if (!form.nom.trim()) formErrors.nom = required
  if (!form.prenom.trim()) formErrors.prenom = required
  if (!form.identifiant.trim()) formErrors.identifiant = required
  if (!PIN_FORMAT.test(form.pin)) formErrors.pin = t('accessRequest.errors.pin')
  else if (form.pin !== form.pinConfirm) formErrors.pinConfirm = t('accessRequest.errors.pinMismatch')
  return !Object.values(formErrors).some(Boolean)
}

/** @returns {Promise<void>} */
async function create() {
  if (!checkForm() || busy.value) return
  busy.value = true
  try {
    const agent = await agentsApi.create({
      nom: form.nom.trim(),
      prenom: form.prenom.trim(),
      phone: form.phone.trim(),
      identifiant: form.identifiant.trim(),
      pin: form.pin,
    })
    agents.data.value = [...(agents.data.value ?? []), agent]
    handover.value = { name: `${agent.prenom} ${agent.nom}`, identifiant: agent.identifiant, pin: form.pin, reset: false }
    creating.value = false
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation') {
      for (const [field, messages] of Object.entries(caught.fieldErrors)) formErrors[field] = messages.join(' ')
    } else {
      notifications.push(errorMessage(t, caught), 'error')
    }
  } finally {
    busy.value = false
  }
}

// ---------- Reset PIN ----------

/** @type {import('vue').Ref<AgentAccount | null>} */
const resetting = ref(null)
const reset = reactive({ pin: '', pinConfirm: '' })
/** @type {Record<string, string | null>} */
const resetErrors = reactive({ pin: null, pinConfirm: null })

/** @param {AgentAccount} agent */
function openReset(agent) {
  Object.assign(reset, { pin: '', pinConfirm: '' })
  Object.assign(resetErrors, { pin: null, pinConfirm: null })
  resetting.value = agent
}

/** @returns {Promise<void>} */
async function resetPin() {
  const agent = resetting.value
  if (!agent || busy.value) return
  resetErrors.pin = PIN_FORMAT.test(reset.pin) ? null : t('accessRequest.errors.pin')
  resetErrors.pinConfirm = !resetErrors.pin && reset.pin !== reset.pinConfirm ? t('accessRequest.errors.pinMismatch') : null
  if (resetErrors.pin || resetErrors.pinConfirm) return
  busy.value = true
  try {
    await agentsApi.resetPin(agent.id, reset.pin)
    handover.value = { name: `${agent.prenom} ${agent.nom}`, identifiant: agent.identifiant, pin: reset.pin, reset: true }
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

/**
 * @param {string} phone
 * @returns {string}
 */
const telHref = (phone) => `tel:${phone.replace(/[^\d+]/g, '')}`

onMounted(agents.run)
</script>

<template>
  <PageHeader :title="t('agents.title')" :intro="t('agents.intro')">
    <template #actions>
      <AppButton variant="secondary" :loading="agents.loading.value" @click="agents.run">{{ t('common.refresh') }}</AppButton>
      <AppButton @click="openCreate">{{ t('agents.create') }}</AppButton>
    </template>
  </PageHeader>

  <InlineAlert v-if="handover" tone="success" class="handover">
    <p class="handover__title">
      {{ handover.reset ? t('agents.handover.resetTitle', { name: handover.name }) : t('agents.handover.createdTitle', { name: handover.name }) }}
    </p>
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

  <ErrorState v-if="agents.error.value" :error="agents.error.value" retryable @retry="agents.run" />
  <LoadingState v-else-if="agents.loading.value && !agents.data.value" :rows="5" />
  <EmptyState v-else-if="!agents.data.value?.length" :title="t('agents.empty')" :hint="t('agents.emptyHint')" />
  <template v-else>
    <div class="toolbar">
      <AppField v-slot="{ id }" :label="t('agents.search')">
        <input :id="id" v-model="search" type="search" autocomplete="off" />
      </AppField>
      <p class="muted" aria-live="polite">{{ t('agents.count', rows.length) }}</p>
    </div>
    <div class="table-scroll">
      <table class="stack-on-mobile">
        <caption class="visually-hidden">{{ t('agents.title') }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ t('agents.name') }}</th>
            <th scope="col">{{ t('login.identifier') }}</th>
            <th scope="col">{{ t('accessRequest.fields.phone') }}</th>
            <th scope="col">{{ t('agents.createdOn') }}</th>
            <th scope="col">{{ t('agents.state') }}</th>
            <th scope="col"><span class="visually-hidden">{{ t('agents.actions') }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="agent in rows" :key="agent.id">
            <th scope="row">{{ agent.prenom }} {{ agent.nom }}</th>
            <td :data-label="t('login.identifier')" class="mono">{{ agent.identifiant }}</td>
            <td :data-label="t('accessRequest.fields.phone')">
              <a v-if="agent.phone" :href="telHref(agent.phone)">{{ agent.phone }}</a>
              <span v-else class="muted">–</span>
            </td>
            <td :data-label="t('agents.createdOn')">{{ fmt.date(agent.date_creation) }}</td>
            <td :data-label="t('agents.state')">
              <span class="state" :class="agent.is_active ? 'state--on' : 'state--off'">
                {{ agent.is_active ? t('agents.active') : t('agents.inactive') }}
              </span>
            </td>
            <td data-label="">
              <AppButton variant="secondary" @click="openReset(agent)">{{ t('agents.resetPin') }}</AppButton>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <EmptyState v-if="!rows.length" :title="t('agents.noMatch')" />
  </template>

  <AppDialog :open="creating" :title="t('agents.createTitle')" @close="creating = false">
    <form id="agent-form" class="stack" novalidate @submit.prevent="create">
      <p class="muted">{{ t('agents.createIntro') }}</p>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.nom')" :error="formErrors.nom ?? null" required>
          <input :id="id" v-model="form.nom" type="text" maxlength="100" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.prenom')" :error="formErrors.prenom ?? null" required>
          <input :id="id" v-model="form.prenom" type="text" maxlength="100" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.phone')" :error="formErrors.phone ?? null" optional>
        <input :id="id" v-model="form.phone" type="tel" maxlength="20" :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('login.identifier')" :hint="t('agents.identifiantHint')" :error="formErrors.identifiant ?? null" required>
        <input :id="id" v-model="form.identifiant" type="text" autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false" maxlength="50" required :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('agents.firstPin')" :hint="t('login.pinHelp')" :error="formErrors.pin ?? null" required>
          <input :id="id" v-model="form.pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.pinConfirm')" :error="formErrors.pinConfirm ?? null" required>
          <input :id="id" v-model="form.pinConfirm" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="creating = false">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="agent-form" :loading="busy">{{ t('agents.createSubmit') }}</AppButton>
    </template>
  </AppDialog>

  <AppDialog
    :open="resetting !== null"
    :title="t('agents.resetTitle', { name: resetting ? `${resetting.prenom} ${resetting.nom}` : '' })"
    @close="resetting = null"
  >
    <form id="reset-form" class="stack" novalidate @submit.prevent="resetPin">
      <p class="muted">{{ t('agents.resetIntro') }}</p>
      <div class="row">
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('agents.newPin')" :hint="t('login.pinHelp')" :error="resetErrors.pin" required>
          <input :id="id" v-model="reset.pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.pinConfirm')" :error="resetErrors.pinConfirm" required>
          <input :id="id" v-model="reset.pinConfirm" type="password" inputmode="numeric" autocomplete="new-password" maxlength="6" required :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </div>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="resetting = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="reset-form" :loading="busy">{{ t('agents.resetSubmit') }}</AppButton>
    </template>
  </AppDialog>
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

.handover__facts dt {
  font-size: var(--text-sm);
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

.mono {
  font-family: var(--font-mono, monospace);
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--space-3);
  margin-bottom: var(--space-4);
}

.toolbar :deep(.field) {
  flex: 1 1 16rem;
  max-width: 24rem;
}

.toolbar p {
  margin: 0;
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
