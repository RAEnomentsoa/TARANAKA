/** Minimal linear scale and "nice" ticks for the hand-drawn SVG charts. */

export interface Domain {
  min: number
  max: number
}

export function extent(values: number[], include: number[] = []): Domain {
  const all = [...values, ...include].filter(Number.isFinite)
  if (all.length === 0) return { min: 0, max: 1 }
  let min = Math.min(...all)
  let max = Math.max(...all)
  if (min === max) {
    const pad = Math.abs(min) * 0.1 || 1
    min -= pad
    max += pad
  }
  return { min, max }
}

function niceStep(span: number, count: number): number {
  const raw = span / Math.max(1, count)
  const power = 10 ** Math.floor(Math.log10(raw))
  const fraction = raw / power
  const nice = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
  return nice * power
}

/** Round the domain out to whole steps and list the ticks inside it. */
export function niceTicks(domain: Domain, count = 5): { domain: Domain; ticks: number[] } {
  const step = niceStep(domain.max - domain.min, count)
  const min = Math.floor(domain.min / step) * step
  const max = Math.ceil(domain.max / step) * step
  const ticks: number[] = []
  for (let v = min; v <= max + step / 2; v += step) ticks.push(Number(v.toFixed(10)))
  return { domain: { min, max }, ticks }
}

export function linear(domain: Domain, range: [number, number]): (value: number) => number {
  const span = domain.max - domain.min || 1
  return (value) => range[0] + ((value - domain.min) / span) * (range[1] - range[0])
}
