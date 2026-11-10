<script setup>
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { statsApi } from '@/api/stats'
import ArrivalChart from '@/components/stats/ArrivalChart.vue'
import BarList from '@/components/stats/BarList.vue'
import MonthlyCasesChart from '@/components/stats/MonthlyCasesChart.vue'
import ProtectedValue from '@/components/stats/ProtectedValue.vue'
import StatTile from '@/components/stats/StatTile.vue'
import StatsFilters from '@/components/stats/StatsFilters.vue'
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
import { COUNT_INDICATORS, OUTCOME_INDICATORS, protectStats } from '@/utils/privacy'

/** @typedef {import('@/api/types').StatsQuery} StatsQuery */
/** @typedef {import('@/stores/statsFilters').StatsFilterValues} StatsFilterValues */
/** @typedef {import('@/utils/privacy').CountIndicator} CountIndicator */

const { t } = useI18n()
const fmt = useFormatters()
const auth = useAuthStore()
const referentiel = useReferentielStore()
const notifications = useNotificationsStore()
const savedFilters = useStatsFiltersStore()

/**
 * Indicators shown as columns of the tables, in reading order.
 * @type {CountIndicator[]}
 */
const TABLE_COLUMNS = [
  'depistages',
  'cas_mas',
  'cas_mam',
  'referencements',
  'referencements_arrives',
  'rendez_vous_manques',
]

/** @type {import('vue').Ref<InstanceType<typeof StatsFilters> | null>} */
const filters = ref(null)
/** @type {import('vue').Ref<StatsQuery | null>} */
const lastQuery = ref(null)
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

/** @param {number} n */
const percent = (n) => t('stats.percentValue', { n: fmt.number(n, 0) })
/** @param {number} n */
const hours = (n) => t('stats.hoursValue', { n: fmt.number(n, 1) })

// Arrivals by region when there are several, else month by month.
const arrivalByRegion = computed(() => (stats.value?.byRegion.length ?? 0) > 1)
const arrivalGroups = computed(() => (arrivalByRegion.value ? stats.value.byRegion : stats.value.byMonth))

const outcomeItems = computed(() =>
  OUTCOME_INDICATORS.map((key) => ({
    key,
    label: t(`discharge.outcomes.${key.replace('sorties_', '')}`),
    value: stats.value.total.counts[key],
  })),
)

/**
 * @param {StatsQuery} query
 * @param {StatsFilterValues} values
 */
function apply(query, values) {
  savedFilters.values = values
  lastQuery.value = query
  void result.run()
}

/**
 * The server's CSV: same masking, and every export is audited.
 * @returns {Promise<void>}
 */
async function exportCsv() {
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
    <LoadingState v-else-if="result.loading.value && !stats" variant="stats" />
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

        <SectionPanel :title="t('stats.beneficiariesTitle')">
          <p class="muted panel-intro">{{ t('stats.beneficiariesIntro') }}</p>
          <dl class="tiles">
            <StatTile :label="t('stats.metrics.beneficiaires_actives')" :value="stats.total.counts.beneficiaires_actives" />
            <StatTile :label="t('stats.metrics.grossesses_suivies')" :value="stats.total.counts.grossesses_suivies" />
            <StatTile :label="t('stats.metrics.signes_danger')" :value="stats.total.counts.signes_danger" />
            <StatTile :label="t('stats.metrics.referencements_grossesse')" :value="stats.total.counts.referencements_grossesse" />
            <StatTile :label="t('stats.metrics.taux_arrivee_grossesse_pct')" :value="stats.total.pregnancyArrivalRate" :format="percent" />
            <StatTile :label="t('stats.metrics.couverture_vaccinale_pct')" :value="stats.total.vaccineCoverage" :format="percent" />
          </dl>
        </SectionPanel>

        <div class="charts">
          <SectionPanel v-if="stats.byMonth.length" :title="t('stats.charts.cases.title')" class="charts__main">
            <MonthlyCasesChart :months="stats.byMonth" />
          </SectionPanel>

          <SectionPanel :title="t('stats.charts.arrival.title')">
            <p class="muted panel-intro">
              {{ arrivalByRegion ? t('stats.charts.arrival.introRegion') : t('stats.charts.arrival.introMonth') }}
            </p>
            <ArrivalChart
              :groups="arrivalGroups"
              :caption="t('stats.charts.arrival.title')"
              :group-header="arrivalByRegion ? t('stats.zoneColumn') : t('stats.monthColumn')"
            />
          </SectionPanel>

          <SectionPanel :title="t('stats.outcomes')">
            <p class="muted panel-intro">{{ t('stats.charts.outcomesIntro') }}</p>
            <BarList :caption="t('stats.outcomes')" :label-header="t('stats.outcomeColumn')" :value-header="t('stats.casesColumn')" :items="outcomeItems" />
          </SectionPanel>
        </div>

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

/* Wide screens: the monthly chart takes two thirds, the meters one third;
   the outcomes go under them. One column on phones. */
.charts {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: var(--space-4);
}

@media (min-width: 64rem) {
  .charts {
    grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
  }

  .charts__main {
    grid-row: span 2;
  }
}

.panel-intro {
  margin: calc(-1 * var(--space-2)) 0 var(--space-3);
  font-size: var(--text-sm);
}

/* The headline figures arrive one after the other. */
.tiles > :nth-child(1) { animation-delay: 0ms; }
.tiles > :nth-child(2) { animation-delay: 50ms; }
.tiles > :nth-child(3) { animation-delay: 100ms; }
.tiles > :nth-child(4) { animation-delay: 150ms; }
.tiles > :nth-child(5) { animation-delay: 200ms; }
.tiles > :nth-child(6) { animation-delay: 250ms; }

.tiles > * {
  animation: rise-in 360ms var(--easing) backwards;
}
</style>
