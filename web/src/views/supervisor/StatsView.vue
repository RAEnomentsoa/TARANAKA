<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { statsApi } from '@/api/stats'
import type { StatsQuery } from '@/api/types'
import BarList from '@/components/stats/BarList.vue'
import ProtectedValue from '@/components/stats/ProtectedValue.vue'
import StatTile from '@/components/stats/StatTile.vue'
import StatsFilters, { type StatsFilterValues } from '@/components/stats/StatsFilters.vue'
import AppButton from '@/components/ui/AppButton.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { errorMessage } from '@/i18n/errors'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferentielStore } from '@/stores/referentiel'
import { useStatsFiltersStore } from '@/stores/statsFilters'
import { downloadBlob } from '@/utils/download'
import { COUNT_INDICATORS, OUTCOME_INDICATORS, protectStats, type CountIndicator } from '@/utils/privacy'

const { t } = useI18n()
const fmt = useFormatters()
const auth = useAuthStore()
const referentiel = useReferentielStore()
const notifications = useNotificationsStore()
const savedFilters = useStatsFiltersStore()

/** Indicators shown as columns of the tables, in reading order. */
const TABLE_COLUMNS: CountIndicator[] = ['depistages', 'cas_mas', 'cas_mam', 'referencements', 'referencements_arrives', 'rendez_vous_manques']

const filters = ref<InstanceType<typeof StatsFilters> | null>(null)
const lastQuery = ref<StatsQuery | null>(null)
const exporting = ref(false)
const lockedRegion = computed(() => (auth.user?.profile.code === 'superviseur' ? auth.user.region_id : null))

// Raw server numbers never reach the template: only protectStats() output.
const result = useAsync(async () => {
  const q = lastQuery.value
  if (!q) return null
  const [byRegion, byMonth] = await Promise.all([
    statsApi.get({ ...q, grouper_par: 'region' }),
    statsApi.get({ ...q, grouper_par: 'mois' }),
  ])
  return protectStats(byRegion, byMonth)
})
const stats = computed(() => result.data.value)

const zoneName = computed(() => {
  const region = lastQuery.value?.region
  if (region === undefined) return t('stats.allRegions')
  return referentiel.regions.find((r) => r.id === region)?.nom ?? String(region)
})

const isEmpty = computed(() => {
  const s = stats.value
  return !!s && COUNT_INDICATORS.every((k) => !s.total.counts[k].hidden && s.total.counts[k].value === 0)
})

const percent = (n: number) => t('stats.percentValue', { n: fmt.number(n, 0) })
const hours = (n: number) => t('stats.hoursValue', { n: fmt.number(n, 1) })

const outcomeItems = computed(() =>
  OUTCOME_INDICATORS.map((key) => ({
    key,
    label: t(`discharge.outcomes.${key.replace('sorties_', '')}`),
    value: stats.value!.total.counts[key],
  })),
)

function apply(query: StatsQuery, values: StatsFilterValues): void {
  savedFilters.values = values
  lastQuery.value = query
  void result.run()
}

/** The server's CSV: same masking, and every export is audited. */
async function exportCsv(): Promise<void> {
  const q = lastQuery.value
  if (!q) return
  exporting.value = true
  try {
    const blob = await statsApi.exportCsv({ ...q, grouper_par: 'region' })
    downloadBlob(t('stats.filename', { start: q.date_debut, end: q.date_fin }), blob)
    notifications.push(t('stats.exported'))
  } catch (caught) {
    notifications.push(errorMessage(t, caught), 'error')
  } finally {
    exporting.value = false
  }
}

onMounted(async () => {
  await referentiel.load().catch(() => undefined)
  filters.value?.submit()
})
</script>

<template>
  <PageHeader :title="t('stats.title')" :intro="t('stats.intro')">
    <template #actions>
      <AppButton variant="secondary" :disabled="!stats" :loading="exporting" @click="exportCsv">{{ t('stats.export') }}</AppButton>
    </template>
  </PageHeader>

  <StatsFilters
    ref="filters"
    :regions="referentiel.regions"
    :locked-region="lockedRegion"
    :initial="savedFilters.values"
    :busy="result.loading.value"
    @apply="apply"
  />

  <div :aria-busy="result.loading.value">
    <ErrorState v-if="result.error.value" :error="result.error.value" retryable @retry="result.run" />
    <LoadingState v-else-if="result.loading.value && !stats" />
    <template v-else-if="stats">
      <p class="period">
        <strong>{{ t('stats.periodLabel', { start: fmt.date(stats.period.start), end: fmt.date(stats.period.end) }) }}</strong>
        <span class="muted">{{ zoneName }}</span>
      </p>

      <EmptyState v-if="isEmpty" :title="t('stats.noData')" />
      <div v-else class="stack">
        <dl class="tiles">
          <StatTile :label="t('stats.metrics.depistages')" :value="stats.total.counts.depistages" />
          <StatTile :label="t('stats.metrics.cas_mas')" :value="stats.total.counts.cas_mas" />
          <StatTile :label="t('stats.metrics.cas_mam')" :value="stats.total.counts.cas_mam" />
          <StatTile :label="t('stats.metrics.taux_arrivee_pct')" :value="stats.total.arrivalRate" :format="percent" />
          <StatTile :label="t('stats.metrics.delai_moyen_arrivee_heures')" :value="stats.total.meanDelayHours" :format="hours" />
          <StatTile :label="t('stats.metrics.rendez_vous_manques')" :value="stats.total.counts.rendez_vous_manques" />
        </dl>

        <SectionPanel v-if="stats.byRegion.length > 1" :title="t('stats.byZone')">
          <div class="table-scroll">
            <table class="groups stack-on-mobile">
              <caption class="visually-hidden">{{ t('stats.byZone') }}</caption>
              <thead>
                <tr>
                  <th scope="col">{{ t('stats.zoneColumn') }}</th>
                  <th v-for="key in TABLE_COLUMNS" :key="key" scope="col" class="num">{{ t(`stats.metrics.${key}`) }}</th>
                  <th scope="col" class="num">{{ t('stats.metrics.taux_arrivee_pct') }}</th>
                  <th scope="col" class="num">{{ t('stats.metrics.delai_moyen_arrivee_heures') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in stats.byRegion" :key="row.key">
                  <th scope="row">{{ row.label }}</th>
                  <td v-for="key in TABLE_COLUMNS" :key="key" class="num" :data-label="t(`stats.metrics.${key}`)">
                    <ProtectedValue :value="row.block.counts[key]" />
                  </td>
                  <td class="num" :data-label="t('stats.metrics.taux_arrivee_pct')"><ProtectedValue :value="row.block.arrivalRate" :format="percent" /></td>
                  <td class="num" :data-label="t('stats.metrics.delai_moyen_arrivee_heures')"><ProtectedValue :value="row.block.meanDelayHours" :format="hours" /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </SectionPanel>

        <div class="two-col">
          <SectionPanel :title="t('stats.outcomes')">
            <BarList :caption="t('stats.outcomes')" :label-header="t('stats.outcomeColumn')" :value-header="t('stats.casesColumn')" :items="outcomeItems" />
          </SectionPanel>

          <SectionPanel v-if="stats.byMonth.length" :title="t('stats.byPeriod')">
            <div class="table-scroll">
              <table class="stack-on-mobile">
                <caption class="visually-hidden">{{ t('stats.byPeriod') }}</caption>
                <thead>
                  <tr>
                    <th scope="col">{{ t('stats.monthColumn') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.depistages') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.cas_mas') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.cas_mam') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in stats.byMonth" :key="row.key">
                    <th scope="row">{{ row.label }}</th>
                    <td class="num" :data-label="t('stats.metrics.depistages')"><ProtectedValue :value="row.block.counts.depistages" /></td>
                    <td class="num" :data-label="t('stats.metrics.cas_mas')"><ProtectedValue :value="row.block.counts.cas_mas" /></td>
                    <td class="num" :data-label="t('stats.metrics.cas_mam')"><ProtectedValue :value="row.block.counts.cas_mam" /></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </SectionPanel>
        </div>

        <InlineAlert tone="info">
          <p>{{ t('stats.hiddenNote') }}</p>
          <p>{{ t('stats.exportHint') }}</p>
        </InlineAlert>
      </div>
    </template>
  </div>
</template>

<style scoped>
.period {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
  align-items: baseline;
}

.tiles {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 10rem), 1fr));
  gap: var(--space-3);
  margin: 0;
}

.groups {
  font-size: var(--text-sm);
}

@media (min-width: 40.01rem) {
  .groups {
    min-width: 56rem;
  }
}

.num {
  text-align: right;
}

.two-col {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 22rem), 1fr));
  gap: var(--space-4);
}
</style>
