<script setup>
import { computed, ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import { extent, linear, niceTicks } from '@/utils/scale'

/**
 * One series over x, drawn in SVG. Optional threshold lines (MAS / MAM).
 * Accessible: a text summary, focusable points with tooltips, and a table
 * view with the same numbers.
 */
/** @typedef {import('@/utils/scale').ChartPoint} ChartPoint */
/** @typedef {import('@/utils/scale').Threshold} Threshold */
/** @typedef {import('@/utils/who').ReferenceCurve} ReferenceCurve */

const props = defineProps({
  title: { type: String, required: true },
  xLabel: { type: String, required: true },
  yLabel: { type: String, required: true },
  /** @type {import('vue').PropType<ChartPoint[]>} */
  points: { type: Array, required: true },
  /** (x: number) => string */
  formatX: { type: Function, required: true },
  /** (y: number) => string */
  formatY: { type: Function, required: true },
  /** @type {import('vue').PropType<Threshold[]>} */
  thresholds: { type: Array, default: () => [] },
  minPoints: { type: Number, default: 1 },
  /** How far to widen the x axis around a single point (a duration for dates). */
  xPad: { type: Number, default: undefined },
  /**
   * Reference curves drawn behind the child's points (WHO z-scores),
   * labelled at their right end.
   * @type {import('vue').PropType<ReferenceCurve[]>}
   */
  references: { type: Array, default: () => [] },
})

const { t } = useI18n()
const id = useId()
const showTable = ref(false)
/** @type {import('vue').Ref<number | null>} */
const active = ref(null)

// A small viewBox keeps the text legible once the chart is scaled to its column.
const WIDTH = 480
const HEIGHT = 260
const hasReferences = computed(() => props.references.length > 0)
// Room on the right for the curve labels ("+3 z", "médiane").
const M = computed(() => ({ top: 34, right: hasReferences.value ? 64 : 16, bottom: 46, left: 48 }))

const sorted = computed(() => [...props.points].sort((a, b) => a.x - b.x))
const enough = computed(() => sorted.value.length >= props.minPoints)

const xScale = computed(() => {
  const d = extent(
    sorted.value.map((p) => p.x),
    props.references.flatMap((curve) => curve.points.map((p) => p.x)),
    props.xPad,
  )
  return { domain: d, ticks: niceTicks(d, 4).ticks.filter((v) => v >= d.min && v <= d.max) }
})
const yScale = computed(() =>
  niceTicks(
    extent(
      sorted.value.map((p) => p.y),
      [...props.thresholds.map((th) => th.value), ...props.references.flatMap((curve) => curve.points.map((p) => p.y))],
    ),
    5,
  ),
)

const sx = computed(() => linear(xScale.value.domain, [M.value.left, WIDTH - M.value.right]))
const sy = computed(() => linear(yScale.value.domain, [HEIGHT - M.value.bottom, M.value.top]))

/** @param {{ x: number, y: number }[]} points */
function line(points) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${sx.value(p.x).toFixed(1)},${sy.value(p.y).toFixed(1)}`).join('')
}

/** @param {string} z */
function curveLabel(z) {
  if (z === '0') return t('charts.median')
  return t('charts.curveLabel', { z: Number(z) > 0 ? `+${z}` : z.replace('-', '−') })
}

const curves = computed(() =>
  props.references.map((curve) => {
    const last = curve.points[curve.points.length - 1]
    return {
      z: curve.z,
      d: line(curve.points),
      tier: Math.abs(Number(curve.z)),
      label: curveLabel(curve.z),
      labelY: last ? sy.value(last.y) : 0,
    }
  }),
)

const path = computed(() => line(sorted.value))

const summary = computed(() => {
  const first = sorted.value[0]
  const last = sorted.value[sorted.value.length - 1]
  if (!enough.value || !first || !last) return t('charts.summaryEmpty', { title: props.title })
  return t('charts.summary', {
    title: props.title,
    count: sorted.value.length,
    first: `${props.formatX(first.x)} (${props.formatY(first.y)})`,
    last: `${props.formatX(last.x)} (${props.formatY(last.y)})`,
  })
})

const activePoint = computed(() => (active.value === null ? null : (sorted.value[active.value] ?? null)))

/** @param {PointerEvent} event */
function onPointerMove(event) {
  const svg = event.currentTarget
  const box = svg.getBoundingClientRect()
  if (!box.width) return
  const x = ((event.clientX - box.left) / box.width) * WIDTH
  let best = 0
  sorted.value.forEach((p, i) => {
    const current = sorted.value[best]
    if (current && Math.abs(sx.value(p.x) - x) < Math.abs(sx.value(current.x) - x)) best = i
  })
  active.value = sorted.value.length ? best : null
}
</script>

<template>
  <figure class="chart">
    <figcaption :id="`${id}-title`" class="chart__title">{{ title }}</figcaption>
    <p :id="`${id}-summary`" class="visually-hidden">{{ summary }}</p>
    <ul v-if="hasReferences && enough" class="chart__legend">
      <li><span class="chart__key chart__key--child" aria-hidden="true" />{{ t('charts.childSeries') }}</li>
      <li><span class="chart__key chart__key--who" aria-hidden="true" />{{ t('charts.whoSeries') }}</li>
    </ul>

    <div v-if="enough" class="chart__plot">
      <svg
        :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
        role="group"
        :aria-labelledby="`${id}-title`"
        :aria-describedby="`${id}-summary`"
        @pointermove="onPointerMove"
        @pointerleave="active = null"
      >
        <!-- Grid and axes: recessive -->
        <g class="chart__grid" aria-hidden="true">
          <line v-for="tick in yScale.ticks" :key="`y${tick}`" :x1="M.left" :x2="WIDTH - M.right" :y1="sy(tick)" :y2="sy(tick)" />
        </g>
        <g class="chart__axis" aria-hidden="true">
          <text v-for="tick in yScale.ticks" :key="`yl${tick}`" :x="M.left - 8" :y="sy(tick)" text-anchor="end" dominant-baseline="middle">
            {{ formatY(tick) }}
          </text>
          <text v-for="tick in xScale.ticks" :key="`xl${tick}`" :x="sx(tick)" :y="HEIGHT - M.bottom + 20" text-anchor="middle">
            {{ formatX(tick) }}
          </text>
          <text :x="WIDTH - M.right" :y="HEIGHT - 6" text-anchor="end" class="chart__axis-label">{{ xLabel }}</text>
          <text :x="M.left - 8" :y="M.top - 22" text-anchor="end" class="chart__axis-label">{{ yLabel }}</text>
        </g>

        <!-- WHO reference curves: behind everything, labelled at the right -->
        <g v-if="hasReferences" class="chart__refs" aria-hidden="true">
          <path v-for="c in curves" :key="c.z" :d="c.d" class="chart__ref" :class="`chart__ref--${c.tier}`" />
          <text v-for="c in curves" :key="`l${c.z}`" :x="WIDTH - M.right + 6" :y="c.labelY" dominant-baseline="middle" class="chart__ref-label">
            {{ c.label }}
          </text>
        </g>

        <!-- Thresholds -->
        <g v-for="th in thresholds" :key="th.label" class="chart__threshold" :class="`chart__threshold--${th.tone}`" aria-hidden="true">
          <line :x1="M.left" :x2="WIDTH - M.right" :y1="sy(th.value)" :y2="sy(th.value)" />
          <text :x="WIDTH - M.right - 4" :y="sy(th.value) - 6" text-anchor="end">{{ th.label }}</text>
        </g>

        <!-- Series -->
        <path :d="path" class="chart__line" aria-hidden="true" />
        <line
          v-if="activePoint"
          class="chart__crosshair"
          :x1="sx(activePoint.x)"
          :x2="sx(activePoint.x)"
          :y1="M.top"
          :y2="HEIGHT - M.bottom"
          aria-hidden="true"
        />
        <g
          v-for="(p, i) in sorted"
          :key="i"
          class="chart__point"
          :class="{ 'chart__point--flagged': p.flagged, 'chart__point--active': active === i }"
          tabindex="0"
          role="img"
          :aria-label="t('charts.point', { x: formatX(p.x), y: formatY(p.y) }) + (p.flagged ? `, ${t('measurements.flagged')}` : '')"
          @focus="active = i"
          @blur="active = null"
        >
          <circle :cx="sx(p.x)" :cy="sy(p.y)" r="14" class="chart__hit" />
          <rect v-if="p.flagged" :x="sx(p.x) - 5" :y="sy(p.y) - 5" width="10" height="10" />
          <circle v-else :cx="sx(p.x)" :cy="sy(p.y)" r="5" />
        </g>
      </svg>

      <div
        v-if="activePoint"
        class="chart__tooltip"
        :style="{ left: `${(sx(activePoint.x) / WIDTH) * 100}%`, top: `${(sy(activePoint.y) / HEIGHT) * 100}%` }"
        aria-hidden="true"
      >
        <strong>{{ formatY(activePoint.y) }}</strong>
        <span>{{ formatX(activePoint.x) }}</span>
        <span v-if="activePoint.flagged" class="chart__flag">{{ t('measurements.flagged') }}</span>
      </div>
    </div>
    <p v-else class="muted">{{ summary }}</p>

    <button
      v-if="enough"
      type="button"
      class="chart__toggle"
      :aria-expanded="showTable"
      :aria-controls="`${id}-table`"
      @click="showTable = !showTable"
    >
      {{ showTable ? t('common.hideTable') : t('common.seeTable') }}
    </button>
    <div v-if="showTable" :id="`${id}-table`" class="table-scroll">
      <table>
        <caption class="visually-hidden">{{ title }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ xLabel }}</th>
            <th scope="col">{{ yLabel }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(p, i) in sorted" :key="i">
            <td>{{ formatX(p.x) }}</td>
            <td>
              {{ formatY(p.y) }}<span v-if="p.flagged" class="chart__flag"> ({{ t('measurements.flagged') }})</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </figure>
</template>

<style scoped>
.chart {
  margin: 0;
}

.chart__title {
  font-weight: 700;
  margin-bottom: var(--space-2);
}

.chart__plot {
  position: relative;
}

.chart svg {
  display: block;
  width: 100%;
  height: auto;
  overflow: visible;
  touch-action: pan-y;
}

.chart__grid line {
  stroke: var(--sky-100);
  stroke-width: 1;
}

.chart__axis text {
  fill: var(--ink-muted);
  font-size: 14px;
}

.chart__axis-label {
  font-weight: 700;
}

.chart__threshold line {
  stroke-width: 2;
  stroke-dasharray: 6 5;
}

.chart__threshold text {
  font-size: 13px;
  font-weight: 700;
}

.chart__threshold--rouge line {
  stroke: var(--rouge-bar);
}

.chart__threshold--rouge text {
  fill: var(--rouge-ink);
}

.chart__threshold--orange line {
  stroke: var(--orange-bar);
}

.chart__threshold--orange text {
  fill: var(--orange-ink);
}

.chart__legend {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1) var(--space-4);
  margin: 0 0 var(--space-2);
  padding: 0;
  list-style: none;
  font-size: var(--text-sm);
}

.chart__legend li {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
}

.chart__key {
  display: inline-block;
  width: 1.25rem;
  height: 0;
}

.chart__key--child {
  border-top: 2px solid var(--primary);
}

.chart__key--who {
  border-top: 2px dashed var(--who-curve);
}

.chart__ref {
  fill: none;
  stroke: var(--who-curve);
  stroke-width: 1.25;
}

.chart__ref--0 {
  stroke: var(--who-median);
  stroke-width: 1.5;
}

.chart__ref--2 {
  stroke-dasharray: 6 4;
}

.chart__ref--3 {
  stroke-dasharray: 2 4;
}

.chart__ref-label {
  fill: var(--ink-muted);
  font-size: 12px;
}

.chart__line {
  fill: none;
  stroke: var(--primary);
  stroke-width: 2;
  stroke-linejoin: round;
}

.chart__crosshair {
  stroke: var(--sky-300);
  stroke-width: 1.5;
}

.chart__point circle:not(.chart__hit),
.chart__point rect {
  fill: var(--primary);
  stroke: var(--white);
  stroke-width: 2;
}

.chart__point--flagged rect {
  fill: var(--orange-bar);
}

.chart__point--active circle:not(.chart__hit) {
  r: 7;
}

.chart__hit {
  fill: transparent;
  stroke: none;
}

.chart__point:focus {
  outline: none;
}

.chart__point:focus-visible .chart__hit {
  stroke: var(--focus);
  stroke-width: 3;
}

.chart__tooltip {
  position: absolute;
  transform: translate(-50%, calc(-100% - 14px));
  display: flex;
  flex-direction: column;
  padding: var(--space-1) var(--space-3);
  background: var(--ink);
  color: var(--white);
  border-radius: var(--radius-sm);
  font-size: var(--text-sm);
  white-space: nowrap;
  pointer-events: none;
}

.chart__flag {
  color: var(--orange-ink);
  font-weight: 700;
}

.chart__tooltip .chart__flag {
  color: var(--warning-on-dark);
}

.chart__toggle {
  min-height: var(--target);
  margin-top: var(--space-2);
  padding: 0 var(--space-3);
  border: none;
  background: none;
  color: var(--primary);
  font-weight: 700;
  text-decoration: underline;
  text-underline-offset: 0.2em;
  cursor: pointer;
}
</style>
