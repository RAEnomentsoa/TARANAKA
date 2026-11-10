<script setup>
import { onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, useRouter } from 'vue-router'
import { beneficiariesApi, beneficiaryCode } from '@/api/beneficiaries'
import { isApiError } from '@/api/errors'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'

/** @typedef {import('@/api/types').BeneficiaryRow} BeneficiaryRow */

/** The zone's connected beneficiaries, searched by name, phone or code. */
const props = defineProps({ q: { type: String, default: '' } })
const { t } = useI18n()
const router = useRouter()

const form = reactive({ q: props.q })
const searching = ref(false)
/** @type {import('vue').Ref<unknown>} */
const error = ref(null)
/** @type {import('vue').Ref<BeneficiaryRow[] | null>} */
const rows = ref(null)
let generation = 0

/**
 * @param {string} text
 * @returns {Promise<void>}
 */
async function search(text) {
  const current = ++generation
  searching.value = true
  error.value = null
  try {
    const list = await beneficiariesApi.list(text.trim() || undefined)
    if (current !== generation) return
    // Nothing in the zone, but the text is a code: she may be from elsewhere.
    const code = beneficiaryCode(text)
    if (!list.length && code) {
      try {
        const dossier = await beneficiariesApi.lookup(code)
        await router.push({ name: 'beneficiary', params: { id: dossier.beneficiaire.id } })
        return
      } catch (caught) {
        if (!isApiError(caught) || caught.kind !== 'not_found') throw caught
      }
    }
    if (current === generation) rows.value = list
  } catch (caught) {
    if (current === generation) error.value = caught
  } finally {
    if (current === generation) searching.value = false
  }
}

function submit() {
  const text = form.q.trim()
  if (text === props.q) void search(text)
  else void router.replace({ name: 'beneficiaries', query: text ? { q: text } : {} })
}

onMounted(() => void search(props.q))
watch(
  () => props.q,
  (q) => {
    form.q = q
    void search(q)
  },
)
</script>

<template>
  <PageHeader :title="t('beneficiaries.title')" :intro="t('beneficiaries.intro')" />

  <form class="search-form" role="search" novalidate @submit.prevent="submit">
    <AppField v-slot="{ id, describedBy }" :label="t('beneficiaries.searchLabel')" :hint="t('beneficiaries.searchHint')">
      <input
        :id="id"
        v-model="form.q"
        type="search"
        autocomplete="off"
        spellcheck="false"
        :placeholder="t('beneficiaries.searchPlaceholder')"
        :aria-describedby="describedBy"
      />
    </AppField>
    <AppButton type="submit" :loading="searching">{{ t('beneficiaries.submit') }}</AppButton>
  </form>

  <div class="results" :aria-busy="searching" aria-live="polite">
    <ErrorState v-if="error" :error="error" retryable @retry="search(form.q)" />
    <LoadingState v-else-if="searching && !rows" variant="list" :rows="5" />
    <EmptyState
      v-else-if="rows && !rows.length"
      :title="t('beneficiaries.empty')"
      :hint="t('beneficiaries.emptyHint')"
    />
    <template v-else-if="rows">
      <p class="results__count muted">{{ t('beneficiaries.count', rows.length) }}</p>
      <ol class="list">
        <li v-for="row in rows" :key="row.id" class="list__item">
          <div class="list__who">
            <RouterLink :to="{ name: 'beneficiary', params: { id: row.id } }" class="list__link">
              {{ row.prenom }} {{ row.nom }}
            </RouterLink>
            <span v-if="row.phone" class="list__phone muted">{{ row.phone }}</span>
          </div>
          <code v-if="row.code_beneficiaire" class="list__code" :title="t('beneficiaries.codeColumn')">
            {{ row.code_beneficiaire }}
          </code>
          <div class="list__tags">
            <span v-if="row.grossesse_en_cours" class="tag tag--pregnant">{{ t('beneficiaries.pregnant') }}</span>
            <span v-if="row.suivie" class="tag">{{ t('beneficiaries.followed') }}</span>
            <span class="muted">{{ t('beneficiaries.children', row.nb_enfants) }}</span>
          </div>
        </li>
      </ol>
    </template>
  </div>
</template>

<style scoped>
.search-form {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--space-3);
  max-width: 36rem;
}

.search-form > :first-child {
  flex: 1 1 16rem;
}

.results {
  margin-top: var(--space-5);
}

.results__count {
  font-size: var(--text-sm);
  margin-bottom: var(--space-2);
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
  display: grid;
  grid-template-columns: minmax(12rem, 1.4fr) auto minmax(0, 1fr);
  align-items: center;
  gap: var(--space-2) var(--space-4);
  padding: var(--space-3) var(--space-4);
}

.list__item + .list__item {
  border-top: 1px solid var(--line);
}

.list__who {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.list__link {
  display: inline-flex;
  align-items: center;
  min-height: var(--target-min);
  font-weight: 700;
  color: var(--primary);
}

.list__phone {
  font-size: var(--text-sm);
}

.list__code {
  font-family: var(--font-code);
  letter-spacing: 0.08em;
  padding: var(--space-1) var(--space-2);
  background: var(--sky-50);
  border-radius: var(--radius-sm);
}

.list__tags {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
  justify-self: end;
  font-size: var(--text-sm);
}

.tag {
  padding: calc(var(--space-1) / 2) var(--space-2);
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  font-weight: 700;
}

.tag--pregnant {
  background: var(--sky-100);
  border-color: var(--sky-100);
  color: var(--primary);
}

@media (max-width: 40rem) {
  .list__item {
    grid-template-columns: minmax(0, 1fr) auto;
  }

  .list__tags {
    grid-column: 1 / -1;
    justify-self: start;
  }
}
</style>
