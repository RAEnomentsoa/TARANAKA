<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { accessRequestsApi } from '@/api/accounts'
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

/** @typedef {import('@/api/types').AccessRequest} AccessRequest */
/** @typedef {import('@/api/types').AccessRequestStatus} AccessRequestStatus */
/** @typedef {import('@/api/types').RequestedProfile} RequestedProfile */

/*
 * Admin review of the access requests (D15). Before approving, the admin
 * checks who the person is (a phone call to the centre) and may correct the
 * profile, centre or region: they decide which records the account sees.
 */

const { t } = useI18n()
const fmt = useFormatters()
const notifications = useNotificationsStore()

/** @type {AccessRequestStatus[]} */
const STATUSES = ['en_attente', 'approuvee', 'refusee']
/** @type {RequestedProfile[]} */
const PROFILES = ['agent_csb', 'superviseur']

/** @type {import('vue').Ref<AccessRequestStatus>} */
const status = ref('en_attente')
const requests = useAsync(() => accessRequestsApi.list(status.value))
const options = useAsync(() => accessRequestsApi.options())
watch(status, () => requests.run())

const regions = computed(() => options.data.value?.regions ?? [])
const allCentres = computed(() => options.data.value?.centres ?? [])

// ---------- Approve ----------

/** @type {import('vue').Ref<AccessRequest | null>} */
const approving = ref(null)
const approval = reactive({
  /** @type {RequestedProfile} */
  profil_demande: 'agent_csb',
  /** @type {number | ''} */
  csb_id: '',
  /** @type {number | ''} */
  region_id: '',
})
/** @type {import('vue').Ref<Record<string, string>>} */
const approvalErrors = ref({})
const busy = ref(false)

const centresForRegion = computed(() =>
  allCentres.value.filter((c) => approval.region_id === '' || c.region_id === approval.region_id),
)

/** @param {AccessRequest} request */
function openApprove(request) {
  approval.profil_demande = request.profil_demande
  approval.csb_id = request.csb_id ?? ''
  approval.region_id = request.region_id ?? ''
  approvalErrors.value = {}
  approving.value = request
}

/** @returns {Promise<void>} */
async function approve() {
  const request = approving.value
  if (!request || busy.value) return
  const nurse = approval.profil_demande === 'agent_csb'
  if (nurse && approval.csb_id === '') {
    approvalErrors.value = { csb_id: t('validation.required') }
    return
  }
  busy.value = true
  try {
    await accessRequestsApi.approve(request.id, {
      profil_demande: approval.profil_demande,
      csb_id: nurse ? /** @type {number} */ (approval.csb_id) : null,
      region_id: approval.region_id === '' ? null : approval.region_id,
    })
    remove(request)
    approving.value = null
    notifications.push(t('accessRequests.approved', { name: `${request.prenom} ${request.nom}` }))
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation') {
      approvalErrors.value = Object.fromEntries(
        Object.entries(caught.fieldErrors).map(([field, messages]) => [field, messages.join(' ')]),
      )
    } else {
      notifications.push(errorMessage(t, caught), 'error')
    }
  } finally {
    busy.value = false
  }
}

// ---------- Refuse ----------

/** @type {import('vue').Ref<AccessRequest | null>} */
const refusing = ref(null)
const reason = ref('')

/** @param {AccessRequest} request */
function openRefuse(request) {
  reason.value = ''
  refusing.value = request
}

/** @returns {Promise<void>} */
async function refuse() {
  const request = refusing.value
  if (!request || busy.value) return
  busy.value = true
  try {
    await accessRequestsApi.refuse(request.id, reason.value.trim())
    remove(request)
    refusing.value = null
    notifications.push(t('accessRequests.refused', { name: `${request.prenom} ${request.nom}` }))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    busy.value = false
  }
}

/** @param {AccessRequest} request */
function remove(request) {
  requests.data.value = (requests.data.value ?? []).filter((r) => r.id !== request.id)
}

/**
 * @param {string} phone
 * @returns {string}
 */
const telHref = (phone) => `tel:${phone.replace(/[^\d+]/g, '')}`

/**
 * @param {AccessRequest} request
 * @returns {string}
 */
function place(request) {
  if (request.csb_nom) {
    const type = request.csb_type ? ` (${t(`centreTypes.${request.csb_type}`)})` : ''
    return `${request.csb_nom}${type}`
  }
  return request.region_nom ?? t('accessRequest.national')
}

onMounted(() => {
  requests.run()
  options.run()
})
</script>

<template>
  <PageHeader :title="t('accessRequests.title')" :intro="t('accessRequests.intro')">
    <template #actions>
      <AppButton variant="secondary" :loading="requests.loading.value" @click="requests.run">{{ t('common.refresh') }}</AppButton>
    </template>
  </PageHeader>

  <div class="filters" role="group" :aria-label="t('accessRequests.filterLabel')">
    <button
      v-for="value in STATUSES"
      :key="value"
      type="button"
      class="filter"
      :class="{ 'filter--active': status === value }"
      :aria-pressed="status === value"
      @click="status = value"
    >
      {{ t(`accessRequests.statuses.${value}`) }}
    </button>
  </div>

  <ErrorState v-if="requests.error.value" :error="requests.error.value" retryable @retry="requests.run" />
  <LoadingState v-else-if="requests.loading.value && !requests.data.value" :rows="4" />
  <EmptyState v-else-if="!requests.data.value?.length" :title="t(`accessRequests.empty.${status}`)" />
  <ul v-else class="requests">
    <li v-for="request in requests.data.value" :key="request.id" class="card">
      <div class="card__head">
        <h2 class="card__name">{{ request.prenom }} {{ request.nom }}</h2>
        <span class="badge">{{ t(`roles.${request.profil_demande}`) }}</span>
      </div>
      <dl class="card__facts">
        <div>
          <dt>{{ t('accessRequests.place') }}</dt>
          <dd>{{ place(request) }}</dd>
        </div>
        <div v-if="request.fonction">
          <dt>{{ t('accessRequest.fields.fonction') }}</dt>
          <dd>{{ request.fonction }}</dd>
        </div>
        <div>
          <dt>{{ t('accessRequest.fields.phone') }}</dt>
          <dd><a :href="telHref(request.phone)">{{ request.phone }}</a></dd>
        </div>
        <div v-if="request.email">
          <dt>{{ t('accessRequest.fields.email') }}</dt>
          <dd><a :href="`mailto:${request.email}`">{{ request.email }}</a></dd>
        </div>
        <div>
          <dt>{{ t('login.identifier') }}</dt>
          <dd class="mono">{{ request.identifiant }}</dd>
        </div>
        <div>
          <dt>{{ t('accessRequests.sentOn') }}</dt>
          <dd>{{ fmt.dateTime(request.date_creation) }}</dd>
        </div>
        <div v-if="request.date_traitement">
          <dt>{{ t(`accessRequests.handledOn.${request.statut}`) }}</dt>
          <dd>
            {{ fmt.dateTime(request.date_traitement) }}
            <template v-if="request.traitee_par">– {{ request.traitee_par.prenom }} {{ request.traitee_par.nom }}</template>
          </dd>
        </div>
      </dl>
      <blockquote v-if="request.message" class="card__message card__quote">{{ request.message }}</blockquote>
      <p v-if="request.motif_refus" class="card__message muted">
        <strong>{{ t('accessRequests.reason') }}</strong>
        {{ request.motif_refus }}
      </p>
      <div v-if="request.statut === 'en_attente'" class="card__actions">
        <AppButton variant="ghost" @click="openRefuse(request)">{{ t('accessRequests.refuse') }}</AppButton>
        <AppButton @click="openApprove(request)">{{ t('accessRequests.approve') }}</AppButton>
      </div>
    </li>
  </ul>

  <AppDialog
    :open="approving !== null"
    :title="t('accessRequests.approveTitle', { name: approving ? `${approving.prenom} ${approving.nom}` : '' })"
    @close="approving = null"
  >
    <form id="approve-form" class="stack" novalidate @submit.prevent="approve">
      <InlineAlert tone="warning">{{ t('accessRequests.checkFirst') }}</InlineAlert>
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequests.profile')" :error="approvalErrors.profil_demande ?? null" required>
        <select :id="id" v-model="approval.profil_demande" :aria-describedby="describedBy" :aria-invalid="invalid">
          <option v-for="code in PROFILES" :key="code" :value="code">{{ t(`roles.${code}`) }}</option>
        </select>
      </AppField>
      <AppField
        v-slot="{ id, describedBy, invalid }"
        :label="approval.profil_demande === 'agent_csb' ? t('accessRequest.fields.region') : t('accessRequest.fields.supervisedRegion')"
        :error="approvalErrors.region_id ?? null"
        :optional="approval.profil_demande !== 'agent_csb'"
      >
        <select :id="id" v-model="approval.region_id" :aria-describedby="describedBy" :aria-invalid="invalid">
          <option value="">
            {{ approval.profil_demande === 'agent_csb' ? t('accessRequest.allRegions') : t('accessRequest.national') }}
          </option>
          <option v-for="region in regions" :key="region.id" :value="region.id">{{ region.nom }}</option>
        </select>
      </AppField>
      <AppField
        v-if="approval.profil_demande === 'agent_csb'"
        v-slot="{ id, describedBy, invalid }"
        :label="t('accessRequest.fields.centre')"
        :error="approvalErrors.csb_id ?? null"
        required
      >
        <select :id="id" v-model="approval.csb_id" :aria-describedby="describedBy" :aria-invalid="invalid">
          <option value="" disabled>{{ t('accessRequest.chooseCentre') }}</option>
          <option v-for="centre in centresForRegion" :key="centre.id" :value="centre.id">
            {{ centre.name }} ({{ t(`centreTypes.${centre.type_centre}`) }})
          </option>
        </select>
      </AppField>
      <p v-if="approvalErrors.identifiant" class="dialog-error">{{ approvalErrors.identifiant }}</p>
      <p v-if="approvalErrors.statut" class="dialog-error">{{ approvalErrors.statut }}</p>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="approving = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="approve-form" :loading="busy">{{ t('accessRequests.approveSubmit') }}</AppButton>
    </template>
  </AppDialog>

  <AppDialog
    :open="refusing !== null"
    :title="t('accessRequests.refuseTitle', { name: refusing ? `${refusing.prenom} ${refusing.nom}` : '' })"
    @close="refusing = null"
  >
    <form id="refuse-form" class="stack" novalidate @submit.prevent="refuse">
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequests.reason')" :hint="t('accessRequests.reasonHint')" optional>
        <textarea :id="id" v-model="reason" maxlength="1000" :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="refusing = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="refuse-form" variant="danger" :loading="busy">{{ t('accessRequests.refuseSubmit') }}</AppButton>
    </template>
  </AppDialog>
</template>

<style scoped>
.filters {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  margin-bottom: var(--space-5);
}

.filter {
  min-height: var(--target);
  padding: var(--space-2) var(--space-4);
  border: 1px solid var(--field-border);
  border-radius: var(--radius-pill);
  background: var(--white);
  font-weight: 700;
  cursor: pointer;
}

.filter--active {
  border-color: var(--primary);
  background: var(--primary);
  color: var(--white);
}

.requests {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: var(--space-4);
}

.card {
  padding: var(--space-5);
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background: var(--white);
}

.card__head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  margin-bottom: var(--space-4);
}

.card__name {
  margin: 0;
  font-size: var(--text-md);
}

.badge {
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius-pill);
  background: var(--sky-100);
  font-size: var(--text-sm);
  font-weight: 700;
}

.card__facts {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
  gap: var(--space-3) var(--space-5);
  margin: 0;
}

.card__facts dt {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.card__facts dd {
  margin: 0;
  font-weight: 700;
  overflow-wrap: anywhere;
}

.mono {
  font-family: var(--font-mono, monospace);
}

.card__message {
  margin: var(--space-4) 0 0;
}

.card__quote {
  padding-left: var(--space-3);
  border-left: 3px solid var(--line);
  font-style: italic;
}

.card__actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: var(--space-3);
  margin-top: var(--space-4);
  padding-top: var(--space-4);
  border-top: 1px solid var(--line);
}

.dialog-error {
  margin: 0;
  color: var(--rouge-ink);
  font-weight: 700;
}
</style>
