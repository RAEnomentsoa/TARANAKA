<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Facility, Region, StatsQuery } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import { addDays, todayIso } from '@/utils/dates'

export type PeriodPreset = '30d' | '90d' | '365d' | 'custom'

const props = defineProps<{ regions: Region[]; facilities: Facility[]; initialRegion: number | null; busy: boolean }>()
const emit = defineEmits<{ apply: [query: StatsQuery] }>()

const PRESETS: PeriodPreset[] = ['30d', '90d', '365d', 'custom']
const DAYS: Record<Exclude<PeriodPreset, 'custom'>, number> = { '30d': 30, '90d': 90, '365d': 365 }

const { t } = useI18n()
const today = todayIso()
const form = reactive({
  preset: '90d' as PeriodPreset,
  from: addDays(today, -90),
  to: today,
  region: props.initialRegion as number | null,
  facility: null as number | null,
})
const rangeError = ref<string | null>(null)
const facilityOptions = computed(() =>
  form.region === null ? props.facilities : props.facilities.filter((f) => f.region_id === form.region),
)

/** The query the form describes; null when the dates are not valid. */
function query(): StatsQuery | null {
  const from = form.preset === 'custom' ? form.from : addDays(today, -DAYS[form.preset])
  const to = form.preset === 'custom' ? form.to : today
  rangeError.value = !from || !to || from > to ? t('stats.invalidRange') : null
  if (rangeError.value) return null
  return {
    date_debut: from,
    date_fin: to,
    region_id: form.region ?? undefined,
    csb_id: form.facility ?? undefined,
  }
}

function onRegion(): void {
  if (form.facility !== null && !facilityOptions.value.some((f) => f.id === form.facility)) form.facility = null
}

function submit(): void {
  const q = query()
  if (q) emit('apply', q)
}

defineExpose({ query })
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

    <div v-if="form.preset === 'custom'" class="filters__dates">
      <AppField v-slot="{ id, describedBy, invalid }" :label="t('stats.from')" :error="rangeError">
        <input :id="id" v-model="form.from" type="date" :max="today" :aria-describedby="describedBy" :aria-invalid="invalid" />
      </AppField>
      <AppField v-slot="{ id, describedBy }" :label="t('stats.to')">
        <input :id="id" v-model="form.to" type="date" :max="today" :aria-describedby="describedBy" />
      </AppField>
    </div>

    <div class="filters__zone">
      <AppField v-slot="{ id, describedBy }" :label="t('stats.region')">
        <select :id="id" v-model="form.region" :aria-describedby="describedBy" @change="onRegion">
          <option :value="null">{{ t('stats.allRegions') }}</option>
          <option v-for="r in regions" :key="r.id" :value="r.id">{{ r.nom }}</option>
        </select>
      </AppField>
      <AppField v-slot="{ id, describedBy }" :label="t('stats.facility')">
        <select :id="id" v-model="form.facility" :aria-describedby="describedBy">
          <option :value="null">{{ t('stats.allFacilities') }}</option>
          <option v-for="f in facilityOptions" :key="f.id" :value="f.id">{{ f.name }}</option>
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
  border: 2px solid var(--sky-200);
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

.filters__dates,
.filters__zone {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
  gap: var(--space-3);
  align-items: end;
}
</style>
