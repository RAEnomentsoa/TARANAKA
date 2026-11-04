/** Minimal linear scale and "nice" ticks for the hand-drawn SVG charts. */

/**
 * One point of a chart series.
 * @typedef {Object} ChartPoint
 * @property {number} x
 * @property {number} y
 * @property {boolean} [flagged] Marks a value the phone flagged as implausible.
 */

/**
 * A horizontal reference line (MAS / MAM threshold).
 * @typedef {Object} Threshold
 * @property {number} value
 * @property {string} label
 * @property {'rouge' | 'orange'} tone
 */

/**
 * @typedef {Object} Domain
 * @property {number} min
 * @property {number} max
 */

/**
 * Range of the values. A single value is widened by `pad` on each side
 * (default 10 % of it, or 1): a date axis must pass a duration instead.
 * @param {number[]} values
 * @param {number[]} [include=[]]
 * @param {number} [pad]
 * @returns {Domain}
 */
export function extent(values, include = [], pad) {
  const all = [...values, ...include].filter(Number.isFinite)
  if (all.length === 0) return { min: 0, max: 1 }
  let min = Math.min(...all)
  let max = Math.max(...all)
  if (min === max) {
    const widen = pad ?? (Math.abs(min) * 0.1 || 1)
    min -= widen
    max += widen
  }
  return { min, max }
}

/**
 * @param {number} span
 * @param {number} count
 * @returns {number}
 */
function niceStep(span, count) {
  const raw = span / Math.max(1, count)
  const power = 10 ** Math.floor(Math.log10(raw))
  const fraction = raw / power
  const nice = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
  return nice * power
}

/**
 * Round the domain out to whole steps and list the ticks inside it.
 * @param {Domain} domain
 * @param {*} [count=5]
 * @returns {{ domain: Domain, ticks: number[] }}
 */
export function niceTicks(domain, count = 5) {
  const step = niceStep(domain.max - domain.min, count)
  const min = Math.floor(domain.min / step) * step
  const max = Math.ceil(domain.max / step) * step
  /** @type {number[]} */
  const ticks = []
  for (let v = min; v <= max + step / 2; v += step) ticks.push(Number(v.toFixed(10)))
  return { domain: { min, max }, ticks }
}

/**
 * @param {Domain} domain
 * @param {[number, number]} range
 * @returns {(value: number) => number}
 */
export function linear(domain, range) {
  const span = domain.max - domain.min || 1
  return (value) => range[0] + ((value - domain.min) / span) * (range[1] - range[0])
}
