<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useFormatters } from '@/composables/useFormatters'
import { toNumber } from '@/utils/numbers'

/** @typedef {import('@/api/types').Measurement} Measurement */

const props = defineProps({
  /** @type {import('vue').PropType<Measurement[]>} */
  measurements: { type: Array, required: true },
})
const { t } = useI18n()
const fmt = useFormatters()

const rows = computed(() => [...props.measurements].sort((a, b) => b.date_mesure.localeCompare(a.date_mesure)))

/**
 * @param {string | null} value
 * @param {number} digits
 * @returns {string}
 */
function decimal(value, digits) {
  const n = toNumber(value)
  return n === null ? '–' : fmt.number(n, digits)
}
</script>

<template>
  <div class="table-scroll">
    <table class="measures stack-on-mobile">
      <caption class="visually-hidden">{{ t('measurements.title') }}</caption>
      <thead>
        <tr>
          <th scope="col">{{ t('measurements.date') }}</th>
          <th scope="col" class="num">{{ t('measurements.age') }}</th>
          <th scope="col" class="num">{{ t('measurements.weight') }}</th>
          <th scope="col" class="num">{{ t('measurements.height') }}</th>
          <th scope="col" class="num">{{ t('measurements.muac') }}</th>
          <th scope="col">{{ t('measurements.oedema') }}</th>
          <th scope="col" class="num">{{ t('measurements.whz') }}</th>
          <th scope="col" class="num">{{ t('measurements.haz') }}</th>
          <th scope="col" class="num">{{ t('measurements.waz') }}</th>
          <th scope="col">{{ t('measurements.classification') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="m in rows" :key="m.id" :class="{ 'measures__row--flagged': m.flag_aberrant }">
          <th scope="row">
            <time :datetime="m.date_mesure">{{ fmt.date(m.date_mesure) }}</time>
          </th>
          <td class="num" :data-label="t('measurements.age')">{{ m.age_mois }}</td>
          <td class="num" :data-label="t('measurements.weight')">{{ decimal(m.poids_kg, 2) }}</td>
          <td class="num" :data-label="t('measurements.height')">
            <span>
              {{ decimal(m.taille_corrigee_cm, 1) }}
              <span class="muted">({{ t(`measurements.position.${m.position}`) }})</span>
            </span>
          </td>
          <td class="num" :data-label="t('measurements.muac')">{{ m.pb_mm ?? t('measurements.notAvailable') }}</td>
          <td :data-label="t('measurements.oedema')">{{ m.oedemes_bilateraux === 'aucun' ? t('common.none') : m.oedemes_bilateraux }}</td>
          <td class="num" :data-label="t('measurements.whz')">{{ decimal(m.whz, 2) }}</td>
          <td class="num" :data-label="t('measurements.haz')">{{ decimal(m.haz, 2) }}</td>
          <td class="num" :data-label="t('measurements.waz')">{{ decimal(m.waz, 2) }}</td>
          <td :data-label="t('measurements.classification')">
            <span>
              <span class="tag" :class="m.classification ? `tag--${m.classification}` : ''">
                {{ m.classification ? t(`measurements.classifications.${m.classification}`) : t('measurements.notClassified') }}
              </span>
              <span v-if="m.flag_aberrant" class="flag">{{ t('measurements.flagged') }}</span>
            </span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.measures {
  font-size: var(--text-sm);
}

/* Wide layout only: on phones the rows become cards (stack-on-mobile). */
@media (min-width: 40.01rem) {
  .measures {
    min-width: 52rem;
  }
}

.measures td,
.measures th[scope='row'] {
  white-space: nowrap;
}

.num {
  text-align: right;
}

.measures__row--flagged {
  background: var(--orange-bg);
}

.tag {
  display: inline-block;
  padding: 0 var(--space-2);
  border-radius: var(--radius-sm);
  font-weight: 700;
  border: 1px solid var(--line);
}

.tag--mas {
  background: var(--rouge-bg);
  color: var(--rouge-ink);
  border-color: transparent;
}

.tag--mam,
.tag--nourrisson_a_risque {
  background: var(--orange-bg);
  color: var(--orange-ink);
  border-color: transparent;
}

.tag--normal {
  background: var(--success-bg);
  color: var(--success-ink);
  border-color: transparent;
}

.flag {
  display: block;
  color: var(--orange-ink);
  font-weight: 700;
}
</style>
