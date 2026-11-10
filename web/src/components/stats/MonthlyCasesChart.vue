<script setup>
import { computed, ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import { linear, niceTicks } from '@/utils/scale'
import ProtectedValue from './ProtectedValue.vue'

/** @typedef {import('@/utils/privacy').Protected} Protected */
/** @typedef {import('@/utils/privacy').ProtectedGroup} ProtectedGroup */

/*
 * "Are acute malnutrition cases going up from month to month?"
 * One stacked column per month: SAM at the base (darker, more severe), MAM
 * on top, 2px surface gap between them. A figure hidden by the server (< 5)
 * is never drawn to scale: it gets a fixed, hatched stub with a dashed
 * outline, so its presence shows but not its size. Hover or focus a column
 * for its figures; the table view has them all.
 */
const props = defineProps({
  /** @type {import('vue').PropType<ProtectedGroup[]>} */
  months: { type: Array, required: true },
})

const { t } = useI18n()
const uid = useId()
const showTable = ref(false)
/** @type {import('vue').Ref<number | null>} */
const active = ref(null)

const W = 560
const H = 260
const M = { top: 28, right: 12, bottom: 34, left: 40 }
const GAP = 2
const STUB = 12 // px height of a hidden segment
const RADIUS = 4

/** @param {Protected} p */
const val = (p) => (p.hidden ? 0 : p.value)

const columns = computed(() =>
  props.months.map((m) => ({
    key: m.key,
    label: m.label,
    sam: m.block.counts.cas_mas,
    mam: m.block.counts.cas_mam,
    screenings: m.block.counts.depistages,
  })),
)

// Children are counted in whole numbers: never a 2.5 tick.
const yTicks = computed(() => {
  const max = Math.max(4, ...columns.value.map((c) => val(c.sam) + val(c.mam)))
  const nice = niceTicks({ min: 0, max }, 4)
  const step = Math.max(1, Math.ceil(nice.ticks[1] - nice.ticks[0]))
  const top = Math.ceil(max / step) * step
  const ticks = []
  for (let v = 0; v <= top; v += step) ticks.push(v)
  return { domain: { min: 0, max: top }, ticks }
})
const sy = computed(() => linear(yTicks.value.domain, [H - M.bottom, M.top]))

const band = computed(() => (W - M.left - M.right) / Math.max(1, columns.value.length))
const barWidth = computed(() => Math.min(28, band.value * 0.56))

/**
 * Rectangle with rounded top corners only (data-end), square at the base.
 * @param {number} x
 * @param {number} y
 * @param {number} w
 * @param {number} h
 * @param {boolean} rounded
 */
function bar(x, y, w, h, rounded) {
  const r = rounded ? Math.min(RADIUS, h, w / 2) : 0
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`
}

/**
 * Segments of one column, bottom-up.
 * @param {(typeof columns.value)[number]} c
 * @param {number} i
 */
function segments(c, i) {
  const x = M.left + band.value * i + (band.value - barWidth.value) / 2
  let base = H - M.bottom
  /** @type {{ kind: 'sam' | 'mam', hidden: boolean, d: string, top: number }[]} */
  const out = []
  for (const [kind, value] of /** @type {const} */ ([
    ['sam', c.sam],
    ['mam', c.mam],
  ])) {
    if (!value.hidden && value.value === 0) continue
    const h = value.hidden ? STUB : H - M.bottom - sy.value(value.value)
    const y = base - h
    out.push({ kind, hidden: value.hidden, d: '', top: y, h, x })
    base = y - GAP
  }
  return out.map((s, k) => ({ ...s, d: bar(s.x, s.top, barWidth.value, s.h, k === out.length - 1) }))
}

const drawn = computed(() =>
  columns.value.map((c, i) => {
    const segs = segments(c, i)
    const top = segs.length ? Math.min(...segs.map((s) => s.top)) : H - M.bottom
    const anyHidden = c.sam.hidden || c.mam.hidden
    return {
      ...c,
      i,
      segs,
      cx: M.left + band.value * (i + 0.5),
      top,
      total: anyHidden ? null : c.sam.value + c.mam.value,
    }
  }),
)

// Label sparingly: the latest month and the peak, when their totals are known.
const labelled = computed(() => {
  const known = drawn.value.filter((c) => c.total !== null)
  const keys = new Set()
  if (known.length) {
    keys.add(known[known.length - 1].key)
    keys.add(known.reduce((a, b) => (b.total > a.total ? b : a)).key)
  }
  return keys
})

/** Last month compared with the previous one, when both are known. */
const trend = computed(() => {
  const known = drawn.value.filter((c) => c.total !== null)
  if (known.length < 2) return null
  const last = known[known.length - 1]
  const prev = known[known.length - 2]
  return { last, prev, diff: last.total - prev.total }
})

const summary = computed(() => {
  const tr = trend.value
  if (!tr) return t('stats.charts.cases.summaryShort', { n: columns.value.length })
  const key = tr.diff > 0 ? 'up' : tr.diff < 0 ? 'down' : 'same'
  return t(`stats.charts.cases.trend.${key}`, {
    month: tr.last.label,
    previous: tr.prev.label,
    n: tr.last.total,
    diff: Math.abs(tr.diff),
  })
})

/** @param {Protected} p */
const text = (p) => (p.hidden ? t('stats.hidden') : String(p.value))

/** @param {(typeof drawn.value)[number]} c */
function columnLabel(c) {
  return t('stats.charts.cases.columnLabel', {
    month: c.label,
    sam: text(c.sam),
    mam: text(c.mam),
    screenings: text(c.screenings),
  })
}

const tooltip = computed(() => (active.value === null ? null : drawn.value[active.value]))
</script>

<template>
  <figure class="chart">
    <figcaption class="chart__summary">{{ summary }}</figcaption>

    <ul class="legend">
      <li><span class="swatch swatch--sam" aria-hidden="true" />{{ t('stats.metrics.cas_mas') }}</li>
      <li><span class="swatch swatch--mam" aria-hidden="true" />{{ t('stats.metrics.cas_mam') }}</li>
      <li><span class="swatch swatch--hidden" aria-hidden="true" />{{ t('stats.charts.hiddenKey') }}</li>
    </ul>

    <div class="chart__plot" @mouseleave="active = null">
      <svg :viewBox="`0 0 ${W} ${H}`" role="img" :aria-label="summary" class="chart__svg">
        <defs>
          <pattern :id="`${uid}-hatch`" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="6" height="6" class="hatch-bg" />
            <line x1="0" y1="0" x2="0" y2="6" class="hatch-line" />
          </pattern>
        </defs>

        <g class="grid">
          <g v-for="tick in yTicks.ticks" :key="tick">
            <line :x1="M.left" :x2="W - M.right" :y1="sy(tick)" :y2="sy(tick)" />
            <text :x="M.left - 8" :y="sy(tick)" dy="0.32em" text-anchor="end">{{ tick }}</text>
          </g>
        </g>

        <g v-for="c in drawn" :key="c.key">
          <rect
            v-if="active === c.i"
            class="hover-band"
            :x="M.left + band * c.i"
            :y="M.top - 8"
            :width="band"
            :height="H - M.bottom - M.top + 8"
          />
          <path
            v-for="s in c.segs"
            :key="s.kind"
            :d="s.d"
            class="seg"
            :class="[`seg--${s.kind}`, { 'seg--hidden': s.hidden }]"
            :style="{ animationDelay: `${c.i * 45}ms`, fill: s.hidden ? `url(#${uid}-hatch)` : undefined }"
          />
          <text v-if="labelled.has(c.key)" :x="c.cx" :y="c.top - 7" text-anchor="middle" class="cap">{{ c.total }}</text>
          <text :x="c.cx" :y="H - M.bottom + 20" text-anchor="middle" class="axis-label">{{ c.label }}</text>
          <rect
            class="hit"
            :x="M.left + band * c.i"
            :y="M.top - 8"
            :width="band"
            :height="H - M.top + 8"
            tabindex="0"
            role="img"
            :aria-label="columnLabel(c)"
            @mouseenter="active = c.i"
            @focus="active = c.i"
            @blur="active = null"
          />
        </g>
        <line class="baseline" :x1="M.left" :x2="W - M.right" :y1="H - M.bottom" :y2="H - M.bottom" />
      </svg>

      <div
        v-if="tooltip"
        class="tip"
        :class="{ 'tip--left': tooltip.cx > W * 0.6 }"
        :style="{ left: `${(tooltip.cx / W) * 100}%`, top: `${(tooltip.top / H) * 100}%` }"
        aria-hidden="true"
      >
        <p class="tip__title">{{ tooltip.label }}</p>
        <p><span class="swatch swatch--sam" />{{ t('stats.metrics.cas_mas') }} <strong>{{ text(tooltip.sam) }}</strong></p>
        <p><span class="swatch swatch--mam" />{{ t('stats.metrics.cas_mam') }} <strong>{{ text(tooltip.mam) }}</strong></p>
        <p class="tip__muted">{{ t('stats.metrics.depistages') }} <strong>{{ text(tooltip.screenings) }}</strong></p>
      </div>
    </div>

    <button type="button" class="table-toggle" :aria-expanded="showTable" @click="showTable = !showTable">
      {{ showTable ? t('common.hideTable') : t('common.seeTable') }}
    </button>
    <div v-if="showTable" class="table-scroll">
      <table class="stack-on-mobile">
        <caption class="visually-hidden">{{ t('stats.charts.cases.title') }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ t('stats.monthColumn') }}</th>
            <th scope="col" class="num">{{ t('stats.metrics.cas_mas') }}</th>
            <th scope="col" class="num">{{ t('stats.metrics.cas_mam') }}</th>
            <th scope="col" class="num">{{ t('stats.metrics.depistages') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in columns" :key="c.key">
            <th scope="row">{{ c.label }}</th>
            <td class="num" :data-label="t('stats.metrics.cas_mas')"><ProtectedValue :value="c.sam" /></td>
            <td class="num" :data-label="t('stats.metrics.cas_mam')"><ProtectedValue :value="c.mam" /></td>
            <td class="num" :data-label="t('stats.metrics.depistages')"><ProtectedValue :value="c.screenings" /></td>
          </tr>
        </tbody>
      </table>
    </div>
  </figure>
</template>

<style scoped>
/* Validated pair (dataviz validator, white surface): both >= 3:1, ΔE 20 CVD. */
.chart {
  --sam: #0b5c8e;
  --mam: #4a9bd0;
  margin: 0;
}

.chart__summary {
  margin: 0 0 var(--space-3);
  font-weight: 700;
}

.legend {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2) var(--space-4);
  margin: 0 0 var(--space-2);
  padding: 0;
  list-style: none;
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.legend li {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
}

.swatch {
  display: inline-block;
  width: 0.75rem;
  height: 0.75rem;
  border-radius: 3px;
  flex-shrink: 0;
}

.swatch--sam {
  background: var(--sam);
}

.swatch--mam {
  background: var(--mam);
}

.swatch--hidden {
  border: 1.5px dashed var(--field-border);
  background: repeating-linear-gradient(45deg, var(--sky-100) 0 3px, var(--white) 3px 6px);
}

.chart__plot {
  position: relative;
}

.chart__svg {
  display: block;
  width: 100%;
  height: auto;
  overflow: visible;
}

.grid line {
  stroke: var(--line);
  stroke-width: 1;
}

.grid text,
.axis-label {
  fill: var(--ink-muted);
  font-size: 12px;
}

.baseline {
  stroke: var(--field-border);
  stroke-width: 1;
}

.seg {
  transform-box: fill-box;
  transform-origin: 50% 100%;
  animation: grow-y 520ms var(--easing) backwards;
}

.seg--sam {
  fill: var(--sam);
}

.seg--mam {
  fill: var(--mam);
}

.seg--hidden {
  stroke: var(--field-border);
  stroke-width: 1.5;
  stroke-dasharray: 3 2;
}

.hatch-bg {
  fill: var(--white);
}

.hatch-line {
  stroke: var(--sky-200);
  stroke-width: 3;
}

.cap {
  fill: var(--ink);
  font-size: 13px;
  font-weight: 700;
}

.hover-band {
  fill: var(--sky-50);
}

.hit {
  fill: transparent;
  cursor: default;
  outline: none;
}

.hit:focus-visible {
  stroke: var(--focus);
  stroke-width: 2;
}

.tip {
  position: absolute;
  z-index: 2;
  transform: translate(12px, -50%);
  min-width: 11rem;
  padding: var(--space-2) var(--space-3);
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  box-shadow: var(--shadow-float);
  font-size: var(--text-sm);
  pointer-events: none;
  animation: rise-in 120ms var(--easing) backwards;
}

.tip--left {
  transform: translate(calc(-100% - 12px), -50%);
}

.tip p {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin: 0;
}

.tip strong {
  margin-left: auto;
  padding-left: var(--space-3);
}

.tip__title {
  font-weight: 700;
  margin-bottom: var(--space-1) !important;
}

.tip__muted {
  color: var(--ink-muted);
  padding-left: calc(0.75rem + var(--space-2));
}

.table-toggle {
  margin-top: var(--space-3);
  padding: 0;
  border: none;
  background: none;
  color: var(--primary);
  font-weight: 700;
  text-decoration: underline;
  text-underline-offset: 0.2em;
  cursor: pointer;
  min-height: var(--target-min);
}

.num {
  text-align: right;
}
</style>
