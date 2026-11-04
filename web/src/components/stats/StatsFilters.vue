<script setup>
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import { addDays, todayIso } from '@/utils/dates'

/** @typedef {import('@/api/types').Region} Region */
/** @typedef {import('@/api/types').StatsQuery} StatsQuery */

/** @typedef {import('@/stores/statsFilters').PeriodPreset} PeriodPreset */
/** @typedef {import('@/stores/statsFilters').StatsFilterValues} StatsFilterValues */

/**
 * Period and zone. A regional supervisor is locked to their region by the
 * server (403 otherwise): the selector is then shown fixed.
 */
const props = defineProps({
  /** @type {import('vue').PropType<Region[]>} */
  regions: { type: Array, required: true },
  lockedRegion: { type: Number, default: null },
  /** @type {import('vue').PropType<StatsFilterValues | null>} */
  initial: { type: Object, default: null },
  busy: { type: Boolean, required: true },
})
/** apply(query: StatsQuery, values: StatsFilterValues) */
const emit = defineEmits(['apply'])

/** @type {PeriodPreset[]} */
const PRESETS = ['30d', '90d', '365d', 'custom']
/** @type {Record<Exclude<PeriodPreset, 'custom'>, number>} */
const DAYS = { '30d': 30, '90d': 90, '365d': 365 }

const { t } = useI18n()
const today = todayIso()
/** @type {StatsFilterValues} */
const form = reactive(
  props.initial ?? { preset: '30d', from: addDays(today, -30), to: today, region: props.lockedRegion },
)
/** @type {import('vue').Ref<string | null>} */
const rangeError = ref(null)

/**
 * The query the form describes; null when the dates are not valid.
 * @returns {StatsQuery | null}
 */
function query() {
  const from = form.preset === 'custom' ? form.from : addDays(today, -DAYS[form.preset])
  const to = form.preset === 'custom' ? form.to : today
  rangeError.value = !from || !to || from > to ? t('stats.invalidRange') : null
  if (rangeError.value) return null
  const region = props.lockedRegion ?? form.region
  return { date_debut: from, date_fin: to, ...(region !== null ? { region } : {}) }
}

function submit() {
  const q = query()
  if (q) emit('apply', q, { ...form })
}

defineExpose({ submit })
</script>

<template>
  <form class="filters" :aria-label="t('stats.filters')" novalidate @submit.prevent="submit">
    <fieldset class="filters__period">
      <legend>{{ t('stats.period') }}</legend>
      <div class="segmented">
        <label v-for="preset in PRESETS" :key="preset" class="segmented__option">
          <input v-model="form.preset" type="radio" name="period" :value="preset" />
          <span>{{ t(`stats.periods.${preset}`) }}</span>
        </label>
      </div>
    </fieldset>

    <div v-if="form.preset === 'custom'" class="filters__row">
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('stats.from')" :error="rangeError">
        <input :id="id" v-model="form.from" type="date" :max="today" :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
      <AppField v-slot="{ id, describedBy }" :label="t('stats.to')">
        <input :id="id" v-model="form.to" type="date" :max="today" :aria-describedby="describedBy" />
      </AppField>
    </div>

    <div class="filters__row">
      <AppField v-slot="{ id, describedBy }" :label="t('stats.region')" :hint="lockedRegion !== null ? t('stats.zoneLocked') : undefined">
        <select :id="id" v-model="form.region" :disabled="lockedRegion !== null" :aria-describedby="describedBy">
          <option :value="null">{{ t('stats.allRegions') }}</option>
          <option v-for="r in regions" :key="r.id" :value="r.id">{{ r.nom }}</option>
        </select>
      </AppField>
      <AppButton type="submit" :loading="busy">{{ t('stats.apply') }}</AppButton>
    </div>
  </form>
</template>

<style scoped>
.filters {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-4) var(--space-5);
  background: var(--white);
  border: 1px solid var(--sky-200);
  border-radius: var(--radius-md);
  margin-bottom: var(--space-5);
}

.filters__period {
  border: none;
  margin: 0;
  padding: 0;
}

.filters__period legend {
  font-weight: 700;
  padding: 0;
  margin-bottom: var(--space-2);
}

.segmented {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.segmented__option {
  position: relative;
}

.segmented__option input {
  position: absolute;
  opacity: 0;
  inset: 0;
  margin: 0;
  cursor: pointer;
}

.segmented__option span {
  display: inline-flex;
  align-items: center;
  min-height: var(--target);
  padding: 0 var(--space-4);
  border: 1px solid var(--field-border);
  border-radius: 999px;
  font-weight: 700;
  color: var(--ink-muted);
}

.segmented__option input:checked + span {
  background: var(--primary);
  border-color: var(--primary);
  color: var(--white);
}

.segmented__option input:focus-visible + span {
  outline: 3px solid var(--focus);
  outline-offset: 2px;
}

.filters__row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 14rem), 1fr));
  gap: var(--space-3);
  align-items: end;
}

@media (max-width: 40rem) {
  .filters {
    padding: var(--space-4);
  }
}
</style>
