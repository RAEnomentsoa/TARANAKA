<script setup>
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { referentielApi } from '@/api/referentiel'
import LineChart from '@/components/charts/LineChart.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { parseIsoDate } from '@/utils/dates'
import { toNumber } from '@/utils/numbers'
import { DAYS_PER_MONTH, referenceCurves, referenceQuery, weightForSizeRegime } from '@/utils/who'

/** @typedef {import('@/api/types').Measurement} Measurement */
/** @typedef {import('@/api/types').Sexe} Sexe */
/** @typedef {import('@/api/types').WhoReference} WhoReference */
/** @typedef {import('@/api/types').WhoReferenceQuery} WhoReferenceQuery */
/** @typedef {import('@/utils/scale').ChartPoint} ChartPoint */
/** @typedef {import('@/utils/scale').Threshold} Threshold */

/**
 * The child's growth against the WHO 2006 standards (curves -3 to +3 z,
 * served by /api/who-reference/ from the official tables), plus the
 * weight-for-height z-score and the MUAC over time with the MAS/MAM limits.
 */
const props = defineProps({
  /** @type {import('vue').PropType<Measurement[]>} */
  measurements: { type: Array, required: true },
  /** @type {import('vue').PropType<Sexe>} */
  sexe: { type: String, required: true },
})
const { t } = useI18n()
const fmt = useFormatters()

/**
 * @param {Measurement[]} list
 * @param {(m: Measurement) => number | null} pick
 * @param {(m: Measurement) => number} x
 * @returns {ChartPoint[]}
 */
function series(list, pick, x) {
  return list.flatMap((m) => {
    const y = pick(m)
    return y === null ? [] : [{ x: x(m), y, flagged: m.flag_aberrant }]
  })
}

/** @param {Measurement} m */
const byAge = (m) => m.age_jour / DAYS_PER_MONTH
/** @param {Measurement} m */
const byDate = (m) => parseIsoDate(m.date_mesure).getTime()
/** @param {Measurement} m */
const bySize = (m) => toNumber(m.taille_corrigee_cm) ?? 0
/** @param {number} days */
const daysToMonths = (days) => days / DAYS_PER_MONTH

const weight = computed(() => series(props.measurements, (m) => toNumber(m.poids_kg), byAge))
const height = computed(() => series(props.measurements, (m) => toNumber(m.taille_corrigee_cm), byAge))
const regime = computed(() => weightForSizeRegime(props.measurements))
const weightForSize = computed(() => series(regime.value.measurements, (m) => toNumber(m.poids_kg), bySize))
const whz = computed(() => series(props.measurements, (m) => toNumber(m.whz), byDate))
const muac = computed(() => series(props.measurements, (m) => m.pb_mm, byDate))

/** The three tables to read, limited to the child's ages and sizes. */
const queries = computed(() => {
  const ages = props.measurements.map((m) => m.age_jour)
  return {
    wfa: referenceQuery('wfa', props.sexe, ages),
    lhfa: referenceQuery('lhfa', props.sexe, ages),
    size: referenceQuery(regime.value.indicateur, props.sexe, regime.value.measurements.map(bySize)),
  }
})

/**
 * A table that is not loaded on the server answers 404: the chart is then
 * drawn without curves, never with invented values.
 * @param {WhoReferenceQuery | null} query
 * @returns {Promise<WhoReference | null>}
 */
async function fetchReference(query) {
  if (!query) return null
  try {
    return await referentielApi.whoReference(query)
  } catch {
    return null
  }
}

const who = useAsync(async () => {
  const [wfa, lhfa, size] = await Promise.all([
    fetchReference(queries.value.wfa),
    fetchReference(queries.value.lhfa),
    fetchReference(queries.value.size),
  ])
  return { wfa, lhfa, size }
})

const curves = computed(() => ({
  wfa: referenceCurves(who.data.value?.wfa ?? null, daysToMonths),
  lhfa: referenceCurves(who.data.value?.lhfa ?? null, daysToMonths),
  size: referenceCurves(who.data.value?.size ?? null),
}))
const whoLoaded = computed(() => curves.value.wfa.length > 0 || curves.value.lhfa.length > 0 || curves.value.size.length > 0)

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
const SIZE_PAD = 2 // cm

/** @param {number} x */
const months = (x) => fmt.number(x, 1)
/** @param {number} x */
const day = (x) => fmt.date(new Date(x).toISOString().slice(0, 10))
/** @param {number} y */
const oneDecimal = (y) => fmt.number(y, 1)
/** @param {number} y */
const whole = (y) => fmt.number(y, 0)

onMounted(who.run)
watch(queries, () => void who.run(), { deep: true })
</script>

<template>
  <div class="growth">
    <LineChart
      :title="t('charts.weightForAge')"
      :x-label="t('charts.ageAxis')"
      :y-label="t('charts.kg')"
      :points="weight"
      :references="curves.wfa"
      :format-x="months"
      :x-pad="AGE_PAD"
      :format-y="oneDecimal"
    />
    <LineChart
      :title="t('charts.heightForAge')"
      :x-label="t('charts.ageAxis')"
      :y-label="t('charts.cm')"
      :points="height"
      :references="curves.lhfa"
      :format-x="months"
      :x-pad="AGE_PAD"
      :format-y="oneDecimal"
    />
    <LineChart
      v-if="weightForSize.length"
      :title="regime.indicateur === 'wfl' ? t('charts.weightForLength') : t('charts.weightForHeight')"
      :x-label="regime.indicateur === 'wfl' ? t('charts.lengthAxis') : t('charts.heightAxis')"
      :y-label="t('charts.kg')"
      :points="weightForSize"
      :references="curves.size"
      :format-x="whole"
      :x-pad="SIZE_PAD"
      :format-y="oneDecimal"
    />
    <LineChart
      :title="t('charts.whzOverTime')"
      :x-label="t('charts.dateAxis')"
      :y-label="t('charts.z')"
      :points="whz"
      :thresholds="zThresholds"
      :format-x="day"
      :x-pad="DATE_PAD"
      :format-y="oneDecimal"
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
      :format-y="whole"
    />
  </div>
  <p class="muted note">
    {{ who.loading.value ? '' : whoLoaded ? t('charts.whoNote') : t('charts.whoMissing') }}
    {{ t('measurements.zscoreSource') }}
  </p>
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
