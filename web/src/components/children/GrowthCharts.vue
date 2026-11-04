<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import LineChart from '@/components/charts/LineChart.vue'
import { useFormatters } from '@/composables/useFormatters'
import { parseIsoDate } from '@/utils/dates'
import { toNumber } from '@/utils/numbers'

/** @typedef {import('@/api/types').Measurement} Measurement */
/** @typedef {import('@/utils/scale').ChartPoint} ChartPoint */
/** @typedef {import('@/utils/scale').Threshold} Threshold */

/** Child's growth, from the measurements only (no WHO reference curves yet). */
const props = defineProps({
  /** @type {import('vue').PropType<Measurement[]>} */
  measurements: { type: Array, required: true },
})
const { t } = useI18n()
const fmt = useFormatters()

const DAYS_PER_MONTH = 30.4375

/**
 * @param {(m: Measurement) => number | null} pick
 * @param {(m: Measurement) => number} x
 * @returns {ChartPoint[]}
 */
function series(pick, x) {
  return props.measurements.flatMap((m) => {
    const y = pick(m)
    return y === null ? [] : [{ x: x(m), y, flagged: m.flag_aberrant }]
  })
}

/** @param {Measurement} m */
const byAge = (m) => m.age_jour / DAYS_PER_MONTH
/** @param {Measurement} m */
const byDate = (m) => parseIsoDate(m.date_mesure).getTime()

const weight = computed(() => series((m) => toNumber(m.poids_kg), byAge))
const height = computed(() => series((m) => toNumber(m.taille_corrigee_cm), byAge))
const whz = computed(() => series((m) => toNumber(m.whz), byDate))
const muac = computed(() => series((m) => m.pb_mm, byDate))

/** @type {import('vue').ComputedRef<Threshold[]>} */
const zThresholds = computed(() => [
  { value: -3, label: t('charts.thresholdMas'), tone: 'rouge' },
  { value: -2, label: t('charts.thresholdMam'), tone: 'orange' },
])
/** @type {import('vue').ComputedRef<Threshold[]>} */
const muacThresholds = computed(() => [
  { value: 115, label: t('charts.thresholdMuacMas'), tone: 'rouge' },
  { value: 125, label: t('charts.thresholdMuacMam'), tone: 'orange' },
])

const DAY_MS = 86_400_000
const DATE_PAD = 15 * DAY_MS
const AGE_PAD = 1 // month

/** @param {number} x */
const months = (x) => fmt.number(x, 1)
/** @param {number} x */
const day = (x) => fmt.date(new Date(x).toISOString().slice(0, 10))
</script>

<template>
  <div class="growth">
    <LineChart
      :title="t('charts.weightForAge')"
      :x-label="t('charts.ageAxis')"
      :y-label="t('charts.kg')"
      :points="weight"
      :format-x="months"
      :x-pad="AGE_PAD"
      :format-y="(y) => fmt.number(y, 1)"
    />
    <LineChart
      :title="t('charts.heightForAge')"
      :x-label="t('charts.ageAxis')"
      :y-label="t('charts.cm')"
      :points="height"
      :format-x="months"
      :x-pad="AGE_PAD"
      :format-y="(y) => fmt.number(y, 1)"
    />
    <LineChart
      :title="t('charts.whzOverTime')"
      :x-label="t('charts.dateAxis')"
      :y-label="t('charts.z')"
      :points="whz"
      :thresholds="zThresholds"
      :format-x="day"
      :x-pad="DATE_PAD"
      :format-y="(y) => fmt.number(y, 1)"
    />
    <LineChart
      v-if="muac.length"
      :title="t('charts.muacOverTime')"
      :x-label="t('charts.dateAxis')"
      :y-label="t('charts.mm')"
      :points="muac"
      :thresholds="muacThresholds"
      :format-x="day"
      :x-pad="DATE_PAD"
      :format-y="(y) => fmt.number(y, 0)"
    />
  </div>
  <p class="muted note">{{ t('charts.noReferenceCurves') }} {{ t('measurements.zscoreSource') }}</p>
</template>

<style scoped>
.growth {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 22rem), 1fr));
  gap: var(--space-6) var(--space-5);
}

.note {
  margin-top: var(--space-4);
  font-size: var(--text-sm);
}
</style>
