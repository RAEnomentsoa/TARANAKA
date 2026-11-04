<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { statsApi } from '@/api/stats'
import type { StatsQuery } from '@/api/types'
import BarList from '@/components/stats/BarList.vue'
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
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import { useReferentielStore } from '@/stores/referentiel'
import { downloadCsv } from '@/utils/csv'
import { COUNT_METRICS, OUTCOMES, protectStats } from '@/utils/privacy'
import { buildStatsCsv } from '@/utils/statsCsv'

const { t } = useI18n()
const fmt = useFormatters()
const auth = useAuthStore()
const referentiel = useReferentielStore()
const notifications = useNotificationsStore()

const filters = ref<InstanceType<typeof StatsFilters> | null>(null)
const lastQuery = ref<StatsQuery | null>(null)
// Raw server numbers never reach the template: only protectStats() output.
const result = useAsync(async () => (lastQuery.value ? protectStats(await statsApi.get(lastQuery.value)) : null))
const stats = computed(() => result.data.value)

const zoneName = computed(() => {
  const q = lastQuery.value
  if (q?.csb_id) return referentiel.facilityName(q.csb_id) ?? String(q.csb_id)
  if (q?.region_id) return referentiel.regions.find((r) => r.id === q.region_id)?.nom ?? String(q.region_id)
  return t('stats.allRegions')
})

const isEmpty = computed(() => {
  const s = stats.value
  return !!s && COUNT_METRICS.every((k) => !s.totals.counts[k].hidden && s.totals.counts[k].value === 0)
})

const percent = (n: number) => `${fmt.number(n * 100, 0)} %`
const hours = (n: number) => t('stats.hoursValue', { n: fmt.number(n, 1) })

const outcomeItems = computed(() =>
  OUTCOMES.map((o) => ({ key: o, label: t(`discharge.outcomes.${o}`), value: stats.value!.outcomes[o] })),
)

function apply(query: StatsQuery): void {
  lastQuery.value = query
  void result.run()
}

function exportCsv(): void {
  const s = stats.value
  if (!s) return
  const rows = buildStatsCsv(s, { translate: (key, values) => t(key, values ?? {}), hidden: t('stats.hiddenLabel'), zoneName: zoneName.value })
  downloadCsv(t('stats.csv.filename', { start: s.period.start, end: s.period.end }), rows)
  notifications.push(t('stats.exported'))
}

onMounted(async () => {
  await referentiel.load().catch(() => undefined)
  const q = filters.value?.query()
  if (q) apply(q)
})
</script>

<template>
  <PageHeader :title="t('stats.title')" :intro="t('stats.intro')">
    <template #actions>
      <AppButton variant="secondary" :disabled="!stats" @click="exportCsv">{{ t('stats.export') }}</AppButton>
    </template>
  </PageHeader>

  <StatsFilters
    ref="filters"
    :regions="referentiel.regions"
    :facilities="referentiel.facilities"
    :initial-region="auth.user?.region_id ?? null"
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
          <StatTile :label="t('stats.metrics.depistages')" :value="stats.totals.counts.depistages" emphasis />
          <StatTile :label="t('stats.metrics.mas')" :value="stats.totals.counts.mas" emphasis />
          <StatTile :label="t('stats.metrics.mam')" :value="stats.totals.counts.mam" emphasis />
          <StatTile :label="t('stats.metrics.arrivalRate')" :value="stats.totals.arrivalRate" :format="percent" />
          <StatTile :label="t('stats.metrics.meanDelay')" :value="stats.totals.meanDelayHours" :format="hours" />
          <StatTile :label="t('stats.metrics.rdv_manques')" :value="stats.totals.counts.rdv_manques" />
        </dl>

        <SectionPanel v-if="stats.zones.length" :title="t('stats.byZone')">
          <div class="table-scroll" tabindex="0" role="region" :aria-label="t('stats.byZone')">
            <table class="zones">
              <caption class="visually-hidden">{{ t('stats.byZone') }}</caption>
              <thead>
                <tr>
                  <th scope="col">{{ t('stats.zoneColumn') }}</th>
                  <th v-for="key in COUNT_METRICS" :key="key" scope="col" class="num">{{ t(`stats.metrics.${key}`) }}</th>
                  <th scope="col" class="num">{{ t('stats.metrics.arrivalRate') }}</th>
                  <th scope="col" class="num">{{ t('stats.metrics.meanDelay') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="zone in stats.zones" :key="zone.zoneId">
                  <th scope="row">{{ zone.zoneName }}</th>
                  <td v-for="key in COUNT_METRICS" :key="key" class="num"><ProtectedValue :value="zone.metrics.counts[key]" /></td>
                  <td class="num"><ProtectedValue :value="zone.metrics.arrivalRate" :format="percent" /></td>
                  <td class="num"><ProtectedValue :value="zone.metrics.meanDelayHours" :format="hours" /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </SectionPanel>

        <div class="two-col">
          <SectionPanel :title="t('stats.outcomes')">
            <BarList :caption="t('stats.outcomes')" :label-header="t('stats.outcomeColumn')" :value-header="t('stats.casesColumn')" :items="outcomeItems" />
          </SectionPanel>

          <SectionPanel v-if="stats.periods.length" :title="t('stats.byPeriod')">
            <div class="table-scroll">
              <table>
                <caption class="visually-hidden">{{ t('stats.byPeriod') }}</caption>
                <thead>
                  <tr>
                    <th scope="col">{{ t('stats.monthColumn') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.depistages') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.mas') }}</th>
                    <th scope="col" class="num">{{ t('stats.metrics.mam') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="p in stats.periods" :key="p.period">
                    <th scope="row">{{ p.period }}</th>
                    <td class="num"><ProtectedValue :value="p.counts.depistages" /></td>
                    <td class="num"><ProtectedValue :value="p.counts.mas" /></td>
                    <td class="num"><ProtectedValue :value="p.counts.mam" /></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </SectionPanel>
        </div>

        <InlineAlert tone="info">{{ t('stats.hiddenNote') }}</InlineAlert>
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
  grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
  gap: var(--space-3);
  margin: 0;
}

.zones {
  min-width: 56rem;
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
