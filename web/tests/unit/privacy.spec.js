import { describe, expect, it } from 'vitest'
import { HIDDEN, protectBlock, protectCount, protectStats, suppressComplementary } from '@/utils/privacy'

/** @typedef {import('@/api/types').StatsBlock} StatsBlock */
/** @typedef {import('@/api/types').StatsResponse} StatsResponse */
/** @typedef {import('@/utils/privacy').Protected} Protected */

/**
 * @param {number} value
 * @returns {Protected}
 */
const shown = (value) => ({ hidden: false, value })

/**
 * @param {StatsBlock['indicateurs']} indicateurs
 * @param {string[]} [masques=[]]
 * @returns {StatsBlock}
 */
function block(indicateurs, masques = []) {
  return { indicateurs, masques }
}

describe('small-group protection', () => {
  it.each([1, 2, 3, 4])('hides a count of %i even if the server sent it', (n) => {
    expect(protectCount(n)).toEqual(HIDDEN)
  })

  it('shows zero and counts of 5 or more', () => {
    expect(protectCount(0)).toEqual(shown(0))
    expect(protectCount(5)).toEqual(shown(5))
  })

  it('keeps what the server hid (null, or listed in "masques")', () => {
    const result = protectBlock(block({ cas_mas: null, cas_mam: 12 }, ['cas_mas', 'cas_mam']))
    expect(result.counts.cas_mas).toEqual(HIDDEN)
    expect(result.counts.cas_mam).toEqual(HIDDEN)
  })

  it('hides an arrival rate whose complement is a small group', () => {
    /**
     * @param {number} sent
     * @param {number} arrived
     */
    const rate = (sent, arrived) =>
      protectBlock(
        block({ referencements: sent, referencements_arrives: arrived, taux_arrivee_pct: (100 * arrived) / sent }),
      ).arrivalRate
    expect(rate(4, 4)).toEqual(HIDDEN) // fewer than 5 referrals
    expect(rate(10, 8)).toEqual(HIDDEN) // 2 did not arrive
    expect(rate(20, 3)).toEqual(HIDDEN) // 3 arrived
    expect(rate(20, 10)).toEqual(shown(50))
    expect(rate(20, 20)).toEqual(shown(100))
  })

  it('hides a mean delay over fewer than 5 arrivals', () => {
    expect(protectBlock(block({ referencements_arrives: 4, delai_moyen_arrivee_heures: 30 })).meanDelayHours).toEqual(
      HIDDEN,
    )
    expect(protectBlock(block({ referencements_arrives: 5, delai_moyen_arrivee_heures: 30 })).meanDelayHours).toEqual(
      shown(30),
    )
  })

  it('hides a second cell when a single hidden one could be found from the total', () => {
    const result = suppressComplementary([shown(40), HIDDEN, shown(7), shown(12)], true)
    expect(result.filter((c) => c.hidden)).toHaveLength(2)
    expect(result[2]).toEqual(HIDDEN)
  })

  it('needs no second hidden cell when the total is hidden or two are already hidden', () => {
    expect(suppressComplementary([shown(40), HIDDEN], false)).toEqual([shown(40), HIDDEN])
    expect(suppressComplementary([HIDDEN, HIDDEN, shown(9)], true)).toEqual([HIDDEN, HIDDEN, shown(9)])
  })

  it('never lets a small number through protectStats', () => {
    /** @type {StatsResponse} */
    const byRegion = {
      periode: { date_debut: '2026-10-05', date_fin: '2026-11-04' },
      seuil_petits_effectifs: 5,
      grouper_par: 'region',
      total: block(
        {
          depistages: 52,
          cas_mam: 9,
          cas_mas: null,
          referencements: 12,
          referencements_arrives: 10,
          rendez_vous_manques: null,
        },
        ['cas_mas', 'rendez_vous_manques'],
      ),
      groupes: [
        {
          cle: '1',
          libelle: 'Analamanga',
          ...block({ depistages: 40, cas_mam: 6, cas_mas: null, referencements: 7, referencements_arrives: 6 }, [
            'cas_mas',
          ]),
        },
        // The server forgot to hide a 3: the dashboard does it.
        {
          cle: '2',
          libelle: 'Atsinanana',
          ...block({ depistages: 12, cas_mam: 3, cas_mas: 0, referencements: 5, referencements_arrives: 4 }),
        },
      ],
    }

    const result = protectStats(byRegion, null)
    /** @type {number[]} */
    const visible = []
    for (const b of [result.total, ...result.byRegion.map((g) => g.block)]) {
      for (const cell of Object.values(b.counts)) if (!cell.hidden) visible.push(cell.value)
    }

    expect(visible.every((v) => v === 0 || v >= 5)).toBe(true)
    // Atsinanana's 3 MAM could be found as 9 - 6: Analamanga's 6 is hidden too.
    expect(result.byRegion[0].block.counts.cas_mam).toEqual(HIDDEN)
    expect(result.byRegion[1].block.counts.cas_mam).toEqual(HIDDEN)
    expect(result.period).toEqual({ start: '2026-10-05', end: '2026-11-04' })
  })
})
