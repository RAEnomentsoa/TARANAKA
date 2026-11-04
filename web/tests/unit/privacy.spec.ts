import { describe, expect, it } from 'vitest'
import type { StatsResponse } from '@/api/types'
import {
  HIDDEN,
  protectCount,
  protectMean,
  protectRate,
  protectStats,
  suppressComplementary,
  type Protected,
} from '@/utils/privacy'

const shown = (value: number): Protected => ({ hidden: false, value })

describe('small-group protection', () => {
  it.each([1, 2, 3, 4])('hides a count of %i', (n) => {
    expect(protectCount(n)).toEqual(HIDDEN)
  })

  it('shows zero and counts of 5 or more', () => {
    expect(protectCount(0)).toEqual(shown(0))
    expect(protectCount(5)).toEqual(shown(5))
    expect(protectCount(120)).toEqual(shown(120))
  })

  it('keeps a value the server already hid', () => {
    expect(protectCount(null)).toEqual(HIDDEN)
  })

  it('hides a rate over fewer than 5 cases, or with a small remainder', () => {
    expect(protectRate(3, 4)).toEqual(HIDDEN)
    expect(protectRate(8, 10)).toEqual(HIDDEN) // 2 did not arrive
    expect(protectRate(3, 20)).toEqual(HIDDEN) // 3 arrived
    expect(protectRate(10, 20)).toEqual(shown(0.5))
    expect(protectRate(20, 20)).toEqual(shown(1))
  })

  it('hides a mean computed over fewer than 5 cases', () => {
    expect(protectMean(30, 4)).toEqual(HIDDEN)
    expect(protectMean(30, 5)).toEqual(shown(30))
  })

  it('adds a second hidden cell when a single one could be subtracted from the total', () => {
    const cells = [shown(40), HIDDEN, shown(7), shown(12)]
    const result = suppressComplementary(cells, true)
    expect(result.filter((c) => c.hidden)).toHaveLength(2)
    expect(result[2]).toEqual(HIDDEN) // the smallest visible one
  })

  it('needs no second hidden cell when the total is hidden or two are already hidden', () => {
    expect(suppressComplementary([shown(40), HIDDEN], false)).toEqual([shown(40), HIDDEN])
    expect(suppressComplementary([HIDDEN, HIDDEN, shown(9)], true)).toEqual([HIDDEN, HIDDEN, shown(9)])
  })

  it('never exposes a small number anywhere in protectStats', () => {
    const raw: StatsResponse = {
      periode: { debut: '2026-08-01', fin: '2026-10-31' },
      totaux: {
        depistages: 52,
        mam: 9,
        mas: 3,
        referencements: 12,
        referencements_arrives: 10,
        delai_moyen_arrivee_heures: 20.5,
        rdv_manques: 1,
      },
      issues_sortie: { gueri: 6, transfere: 2, non_repondant: 0, abandon: 1, deces: 1 },
      par_zone: [
        { zone_id: 1, zone_nom: 'A', depistages: 40, mam: 6, mas: 2, referencements: 7, referencements_arrives: 6, delai_moyen_arrivee_heures: 18, rdv_manques: 1 },
        { zone_id: 2, zone_nom: 'B', depistages: 12, mam: 3, mas: 1, referencements: 5, referencements_arrives: 4, delai_moyen_arrivee_heures: 30, rdv_manques: 0 },
      ],
      par_periode: [{ periode: '2026-10', depistages: 20, mam: 4, mas: 0 }],
    }

    const result = protectStats(raw)
    const visible: number[] = []
    const collect = (p: Protected) => {
      if (!p.hidden && Number.isInteger(p.value)) visible.push(p.value)
    }
    Object.values(result.totals.counts).forEach(collect)
    Object.values(result.outcomes).forEach(collect)
    result.zones.forEach((z) => Object.values(z.metrics.counts).forEach(collect))
    result.periods.forEach((p) => Object.values(p.counts).forEach(collect))

    expect(visible.every((v) => v === 0 || v >= 5)).toBe(true)
    expect(result.totals.counts.mas).toEqual(HIDDEN)
    expect(result.totals.meanDelayHours).toEqual(shown(20.5))
    // Zone B's 3 MAM could be found as 9 - 6: zone A's 6 is hidden as well.
    expect(result.zones[0]!.metrics.counts.mam).toEqual(HIDDEN)
    expect(result.zones[1]!.metrics.counts.mam).toEqual(HIDDEN)
  })
})
