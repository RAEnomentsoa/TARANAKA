<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Measurement } from '@/api/types'
import { useFormatters } from '@/composables/useFormatters'
import { toNumber } from '@/utils/numbers'

const props = defineProps<{ measurements: Measurement[] }>()
const { t } = useI18n()
const fmt = useFormatters()

const rows = computed(() => [...props.measurements].sort((a, b) => b.date_mesure.localeCompare(a.date_mesure)))

function z(value: string | null): string {
  const n = toNumber(value)
  return n === null ? '–' : fmt.number(n, 2)
}
</script>

<template>
  <div class="table-scroll" tabindex="0" role="region" :aria-label="t('measurements.title')">
    <table class="measures">
      <caption class="visually-hidden">{{ t('measurements.title') }}</caption>
      <thead>
        <tr>
          <th scope="col">{{ t('measurements.date') }}</th>
          <th scope="col">{{ t('measurements.age') }}</th>
          <th scope="col">{{ t('measurements.weight') }}</th>
          <th scope="col">{{ t('measurements.height') }}</th>
          <th scope="col">{{ t('measurements.muac') }}</th>
          <th scope="col">{{ t('measurements.oedema') }}</th>
          <th scope="col">{{ t('measurements.whz') }}</th>
          <th scope="col">{{ t('measurements.haz') }}</th>
          <th scope="col">{{ t('measurements.waz') }}</th>
          <th scope="col">{{ t('measurements.alert') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="m in rows" :key="m.id" :class="{ 'measures__row--flagged': m.flag_aberrant }">
          <th scope="row">
            <time :datetime="m.date_mesure">{{ fmt.date(m.date_mesure) }}</time>
          </th>
          <td>{{ m.age_mois }}</td>
          <td>{{ fmt.number(toNumber(m.poids_kg) ?? 0, 2) }}</td>
          <td>
            {{ fmt.number(toNumber(m.taille_corrigee_cm) ?? 0) }}
            <span class="muted">({{ t(`measurements.position.${m.position}`) }})</span>
          </td>
          <td>{{ m.pb_mm ?? t('measurements.notAvailable') }}</td>
          <td>{{ m.oedemes_bilateraux === 'aucun' ? t('common.none') : m.oedemes_bilateraux }}</td>
          <td>{{ z(m.whz) }}</td>
          <td>{{ z(m.haz) }}</td>
          <td>{{ z(m.waz) }}</td>
          <td>
            <span class="alert-tag" :class="`alert-tag--${m.alerte}`">{{ t(`measurements.alerts.${m.alerte}`) }}</span>
            <span v-if="m.flag_aberrant" class="flag">{{ t('measurements.flagged') }}</span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.measures {
  min-width: 52rem;
}

.measures td,
.measures th[scope='row'] {
  white-space: nowrap;
}

.measures th[scope='row'] {
  font-weight: 700;
}

.measures__row--flagged {
  background: var(--orange-bg);
}

.alert-tag {
  display: inline-block;
  padding: 0 var(--space-2);
  border-radius: var(--radius-sm);
  font-weight: 700;
  font-size: var(--text-sm);
}

.alert-tag--vert {
  background: var(--success-bg);
  color: var(--success-ink);
}

.alert-tag--orange {
  background: var(--orange-bg);
  color: var(--orange-ink);
}

.alert-tag--rouge {
  background: var(--rouge-bg);
  color: var(--rouge-ink);
}

.flag {
  display: block;
  font-size: var(--text-sm);
  color: var(--orange-ink);
  font-weight: 700;
}
</style>
