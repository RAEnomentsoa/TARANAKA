<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { isApiError } from '@/api/errors'
import { territoryApi } from '@/api/referentiel'
import AppButton from '@/components/ui/AppButton.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import AppField from '@/components/ui/AppField.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import TabBar from '@/components/ui/TabBar.vue'
import { useAsync } from '@/composables/useAsync'
import { errorMessage } from '@/i18n/errors'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferentielStore } from '@/stores/referentiel'

/** @typedef {import('@/api/referentiel').TerritoryKind} Kind */
/** @typedef {import('@/api/types').CentreType} CentreType */
/** @typedef {{ id: number, label: string, detail: string }} Row */

/*
 * The admin's territory: provinces, regions and health centres. A row still
 * used (regions of a province, accounts or referrals of a centre…) can't be
 * deleted: the server says why, and the message is shown as is.
 */

const { t } = useI18n()
const notifications = useNotificationsStore()
const referentiel = useReferentielStore()
/** @type {CentreType[]} */
const CENTRE_TYPES = ['csb', 'crenam', 'crenas', 'creni']

/** @type {import('vue').Ref<Kind>} */
const active = ref('regions')
const tabs = computed(() => [
  { value: 'provinces', label: t('territory.tabs.provinces'), count: referentiel.provinces.length },
  { value: 'regions', label: t('territory.tabs.regions'), count: referentiel.regions.length },
  { value: 'facilities', label: t('territory.tabs.facilities'), count: referentiel.facilities.length },
])

const loader = useAsync(() => referentiel.reload())

/**
 * @param {number} id
 * @returns {string}
 */
const provinceName = (id) => referentiel.provinces.find((p) => p.id === id)?.nom ?? '–'
/**
 * @param {number} id
 * @returns {string}
 */
const regionName = (id) => referentiel.regions.find((r) => r.id === id)?.nom ?? '–'
/** @param {string} a @param {string} b */
const byName = (a, b) => a.localeCompare(b)

/** @type {import('vue').ComputedRef<Row[]>} */
const rows = computed(() => {
  if (active.value === 'provinces') {
    return referentiel.provinces
      .map((p) => ({
        id: p.id,
        label: p.nom,
        detail: t('territory.regionsCount', referentiel.regions.filter((r) => r.province_id === p.id).length),
      }))
      .sort((a, b) => byName(a.label, b.label))
  }
  if (active.value === 'regions') {
    return referentiel.regions
      .map((r) => ({
        id: r.id,
        label: r.nom,
        detail: `${provinceName(r.province_id)} · ${t('territory.centresCount', referentiel.facilitiesOf(r.id).length)}`,
      }))
      .sort((a, b) => byName(a.label, b.label))
  }
  return referentiel.facilities
    .map((f) => ({
      id: f.id,
      label: `${f.name} (${t(`centreTypes.${f.type_centre}`)})`,
      detail: [regionName(f.region_id), f.tel].filter(Boolean).join(' · '),
    }))
    .sort((a, b) => byName(a.label, b.label))
})

// ---------- Create and edit ----------

/** @type {import('vue').Ref<{ kind: Kind, id: number | null } | null>} */
const editing = ref(null)
const form = reactive({ nom: '', parent: '', type_centre: /** @type {CentreType} */ ('csb'), tel: '' })
/** @type {Record<string, string | null>} */
const errors = reactive({})
const busy = ref(false)

const dialogTitle = computed(() => {
  if (!editing.value) return ''
  const what = t(`territory.kinds.${editing.value.kind}`)
  return editing.value.id === null ? t('territory.addTitle', { what }) : t('territory.editTitle', { what })
})

/**
 * @param {Kind} kind
 * @param {number | null} [id=null]
 */
function openForm(kind, id = null) {
  for (const key of Object.keys(errors)) errors[key] = null
  if (kind === 'provinces') {
    const p = referentiel.provinces.find((x) => x.id === id)
    Object.assign(form, { nom: p?.nom ?? '', parent: '' })
  } else if (kind === 'regions') {
    const r = referentiel.regions.find((x) => x.id === id)
    Object.assign(form, { nom: r?.nom ?? '', parent: r ? String(r.province_id) : '' })
  } else {
    const f = referentiel.facilities.find((x) => x.id === id)
    Object.assign(form, {
      nom: f?.name ?? '',
      parent: f ? String(f.region_id) : '',
      type_centre: f?.type_centre ?? 'csb',
      tel: f?.tel ?? '',
    })
  }
  editing.value = { kind, id }
}

/**
 * The body the server expects for each kind.
 * @param {Kind} kind
 * @returns {Record<string, unknown>}
 */
function body(kind) {
  if (kind === 'provinces') return { nom: form.nom.trim() }
  if (kind === 'regions') return { nom: form.nom.trim(), province_id: Number(form.parent) }
  return { name: form.nom.trim(), region_id: Number(form.parent), type_centre: form.type_centre, tel: form.tel.trim() }
}

/** @returns {Promise<void>} */
async function save() {
  const target = editing.value
  if (!target || busy.value) return
  for (const key of Object.keys(errors)) errors[key] = null
  const required = t('validation.required')
  if (!form.nom.trim()) errors.nom = required
  if (target.kind !== 'provinces' && !form.parent) errors.parent = required
  if (target.kind === 'facilities' && !form.tel.trim()) errors.tel = required
  if (Object.values(errors).some(Boolean)) return

  busy.value = true
  try {
    if (target.id === null) await territoryApi.create(target.kind, body(target.kind))
    else await territoryApi.update(target.kind, target.id, body(target.kind))
    await referentiel.reload()
    notifications.push(t('territory.saved'))
    editing.value = null
  } catch (caught) {
    if (isApiError(caught) && caught.kind === 'validation' && Object.keys(caught.fieldErrors).length) {
      // The server names the fields as stored: name/nom, region_id/province_id.
      for (const [field, messages] of Object.entries(caught.fieldErrors)) {
        const key = { name: 'nom', region_id: 'parent', province_id: 'parent' }[field] ?? field
        errors[key] = messages.join(' ')
      }
    } else {
      notifications.push(errorMessage(t, caught), 'error')
    }
  } finally {
    busy.value = false
  }
}

// ---------- Delete ----------

/** @type {import('vue').Ref<Row | null>} */
const deleting = ref(null)

/** @returns {Promise<void>} */
async function remove() {
  const row = deleting.value
  if (!row || busy.value) return
  busy.value = true
  try {
    await territoryApi.remove(active.value, row.id)
    await referentiel.reload()
    notifications.push(t('territory.deleted', { name: row.label }))
  } catch (caught) {
    // "Still used": the server's sentence explains what blocks it.
    const detail = isApiError(caught) ? caught.detail : null
    notifications.push(detail ?? errorMessage(t, caught), 'error')
  } finally {
    busy.value = false
    deleting.value = null
  }
}

onMounted(loader.run)
</script>

<template>
  <PageHeader :title="t('territory.title')" :intro="t('territory.intro')">
    <template #actions>
      <AppButton @click="openForm(active)">{{ t('territory.add', { what: t(`territory.kinds.${active}`) }) }}</AppButton>
    </template>
  </PageHeader>

  <TabBar v-model="active" :label="t('territory.title')" :tabs="tabs" id-prefix="territory" />

  <div id="territory-panel" role="tabpanel" :aria-labelledby="`territory-tab-${active}`" class="panel" :aria-busy="loader.loading.value">
    <ErrorState v-if="loader.error.value" :error="loader.error.value" retryable @retry="loader.run" />
    <LoadingState v-else-if="loader.loading.value && !rows.length" :rows="5" />
    <EmptyState v-else-if="!rows.length" :title="t('territory.empty')" />
    <ul v-else class="list">
      <li v-for="row in rows" :key="row.id" class="list__item">
        <div class="list__text">
          <strong>{{ row.label }}</strong>
          <span class="muted">{{ row.detail }}</span>
        </div>
        <div class="list__actions">
          <AppButton variant="secondary" @click="openForm(active, row.id)">{{ t('accounts.edit') }}</AppButton>
          <AppButton variant="ghost" @click="deleting = row">{{ t('territory.delete') }}</AppButton>
        </div>
      </li>
    </ul>
  </div>

  <AppDialog :open="editing !== null" :title="dialogTitle" @close="editing = null">
    <form id="territory-form" class="stack" novalidate @submit.prevent="save">
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('territory.name')" :error="errors.nom ?? null" required>
        <input :id="id" v-model="form.nom" type="text" maxlength="150" :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
      <AppField
        v-if="editing?.kind === 'regions'"
        v-slot="{ id, describedBy, invalid }"
        :label="t('territory.province')"
        :error="errors.parent ?? null"
        required
      >
        <select :id="id" v-model="form.parent" :aria-describedby="describedBy" :aria-invalid="invalid">
          <option value="">–</option>
          <option v-for="p in referentiel.provinces" :key="p.id" :value="String(p.id)">{{ p.nom }}</option>
        </select>
      </AppField>
      <template v-if="editing?.kind === 'facilities'">
        <div class="row">
          <AppField v-slot="{ id, describedBy, invalid }" :label="t('accounts.filters.region')" :error="errors.parent ?? null" required>
            <select :id="id" v-model="form.parent" :aria-describedby="describedBy" :aria-invalid="invalid">
              <option value="">–</option>
              <option v-for="r in referentiel.regions" :key="r.id" :value="String(r.id)">{{ r.nom }}</option>
            </select>
          </AppField>
          <AppField v-slot="{ id, describedBy, invalid }" :label="t('territory.centreType')" :error="errors.type_centre ?? null" required>
            <select :id="id" v-model="form.type_centre" :aria-describedby="describedBy" :aria-invalid="invalid">
              <option v-for="type in CENTRE_TYPES" :key="type" :value="type">{{ t(`centreTypes.${type}`) }}</option>
            </select>
          </AppField>
        </div>
        <AppField v-slot="{ id, describedBy, invalid }" :label="t('accessRequest.fields.phone')" :error="errors.tel ?? null" required>
          <input :id="id" v-model="form.tel" type="tel" maxlength="20" :aria-describedby="describedBy" :aria-invalid="invalid" />
        </AppField>
      </template>
    </form>
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="editing = null">{{ t('common.cancel') }}</AppButton>
      <AppButton type="submit" form="territory-form" :loading="busy">{{ t('common.save') }}</AppButton>
    </template>
  </AppDialog>

  <ConfirmDialog
    :open="deleting !== null"
    :title="t('territory.delete')"
    :message="deleting ? t('territory.confirmDelete', { name: deleting.label }) : ''"
    :confirm-label="t('territory.delete')"
    danger
    :busy="busy"
    @confirm="remove"
    @cancel="deleting = null"
  />
</template>

<style scoped>
.panel {
  margin-top: var(--space-4);
}

.list {
  list-style: none;
  margin: 0;
  padding: 0;
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  overflow: hidden;
}

.list__item {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-4);
}

.list__item + .list__item {
  border-top: 1px solid var(--line);
}

.list__text {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.list__text .muted {
  font-size: var(--text-sm);
}

.list__actions {
  display: flex;
  gap: var(--space-2);
}

.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
  gap: var(--space-4);
}
</style>
