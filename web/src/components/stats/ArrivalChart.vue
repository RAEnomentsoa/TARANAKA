<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useFormatters } from '@/composables/useFormatters'

/** @typedef {import('@/utils/privacy').ProtectedGroup} ProtectedGroup */

/*
 * "Do referred children reach the centre?"
 * One meter per region (or per month): arrived referrals over all referrals.
 * The lowest arrival rate comes first: that is where to act (call the ASC,
 * look for the families). Every figure is printed beside its bar, so there
 * is nothing to hover. A hidden figure (< 5) gets an empty dashed track:
 * never a bar drawn to an unknown size.
 */
const props = defineProps({
  /** @type {import('vue').PropType<ProtectedGroup[]>} */
  groups: { type: Array, required: true },
  caption: { type: String, required: true },
  groupHeader: { type: String, required: true },
})

const { t } = useI18n()
const fmt = useFormatters()

const rows = computed(() => {
  const list = props.groups.map((g) => {
    const sent = g.block.counts.referencements
    const arrived = g.block.counts.referencements_arrives
    const rate = g.block.arrivalRate
    const none = !sent.hidden && sent.value === 0
    const known = !sent.hidden && !arrived.hidden && !rate.hidden && !none
    return {
      key: g.key,
      label: g.label,
      none,
      known,
      rate: known ? rate.value : null,
      arrived: known ? arrived.value : null,
      sent: known ? sent.value : null,
    }
  })
  // Known rates, lowest first; then hidden figures; then groups without referrals.
  const rank = (r) => (r.known ? 0 : r.none ? 2 : 1)
  return list.sort((a, b) => rank(a) - rank(b) || (a.rate ?? 0) - (b.rate ?? 0) || a.label.localeCompare(b.label))
})
</script>

<template>
  <table class="meters">
    <caption class="visually-hidden">{{ caption }}</caption>
    <thead class="visually-hidden">
      <tr>
        <th scope="col">{{ groupHeader }}</th>
        <th scope="col">{{ t('stats.metrics.taux_arrivee_pct') }}</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="(row, i) in rows" :key="row.key">
        <th scope="row" class="meters__label">{{ row.label }}</th>
        <td class="meters__cell">
          <span class="track" :class="{ 'track--hidden': !row.known && !row.none }" aria-hidden="true">
            <span
              v-if="row.known"
              class="fill"
              :style="{ width: `${Math.max(row.rate, 1.5)}%`, animationDelay: `${i * 60}ms` }"
            />
          </span>
          <span class="meters__value">
            <template v-if="row.known">
              <strong>{{ t('stats.percentValue', { n: fmt.number(row.rate, 0) }) }}</strong>
              <span class="muted">{{ t('stats.charts.arrival.ofTotal', { arrived: row.arrived, sent: row.sent }) }}</span>
            </template>
            <span v-else-if="row.none" class="muted">{{ t('stats.charts.arrival.none') }}</span>
            <span v-else class="hidden-value">
              <span aria-hidden="true">{{ t('stats.hidden') }}</span>
              <span class="visually-hidden">{{ t('stats.hiddenLabel') }}</span>
            </span>
          </span>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.meters {
  width: 100%;
}

.meters th,
.meters td {
  border: none;
  padding: var(--space-2) var(--space-2) var(--space-2) 0;
  vertical-align: middle;
}

.meters__label {
  width: 34%;
  font-weight: 400;
  overflow-wrap: anywhere;
}

.meters__cell {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

/* Lighter step of the same ramp as the fill: the whole bar reads as one meter. */
.track {
  position: relative;
  flex: 1;
  min-width: 4rem;
  height: 0.875rem;
  border-radius: var(--radius-pill);
  background: var(--sky-100);
  overflow: hidden;
}

.track--hidden {
  background: repeating-linear-gradient(45deg, var(--sky-100) 0 3px, var(--white) 3px 6px);
  box-shadow: inset 0 0 0 1.5px var(--sky-200);
}

.fill {
  display: block;
  height: 100%;
  border-radius: var(--radius-pill);
  background: #0b5c8e;
  transform-origin: left center;
  animation: grow-x 600ms var(--easing) backwards;
}

.meters__value {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  /* Fixed width: every track starts and ends at the same place. */
  flex: 0 0 7.5rem;
  line-height: 1.25;
  text-align: right;
  font-size: var(--text-sm);
}

.meters__value strong {
  font-size: var(--text-base);
}

.hidden-value {
  color: var(--ink-muted);
  font-style: italic;
}
</style>
