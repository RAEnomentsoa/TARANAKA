import { describe, expect, it } from 'vitest'
import { HIDDEN, protectBlock, protectCount, protectStats } from '@/utils/privacy'

/** @typedef {import('@/api/types').StatsBlock} StatsBlock */
/** @typedef {import('@/utils/privacy').Protected} Protected */

/** @param {number} value @returns {Protected} */
const shown = (value) => ({ hidden: false, value })

/**
 * @param {StatsBlock['indicateurs']} indicateurs
 * @param {string[]} [masques]
 * @returns {StatsBlock}
 */
const block = (indicateurs, masques = []) => ({ indicateurs, masques })

describe('small-group protection', () => {
  it('shows exactly what the server masked (null or listed in "masques")', () => {
    const result = protectBlock(
      block({ cas_mas: null, cas_mam: 12, depistages: 40, taux_arrivee_pct: null, delai_moyen_arrivee_heures: 30 }, [
        'cas_mas',
        'cas_mam',
        'taux_arrivee_pct',
      ]),
    )
    expect(result.counts.cas_mas).toEqual(HIDDEN)
    // Complementary suppression is the server's job (D11): a masked 12 stays hidden.
    expect(result.counts.cas_mam).toEqual(HIDDEN)
    expect(result.counts.depistages).toEqual(shown(40))
    expect(result.arrivalRate).toEqual(HIDDEN)
    expect(result.meanDelayHours).toEqual(shown(30))
  })

  it.each([1, 2, 3, 4])('still hides a count of %i that would arrive unmasked (safety net)', (n) => {
    expect(protectCount(n)).toEqual(HIDDEN)
  })

  it('shows zero and counts of 5 or more', () => {
    expect(protectCount(0)).toEqual(shown(0))
    expect(protectCount(5)).toEqual(shown(5))
  })

  it('keeps groups in server order and maps their labels', () => {
    const response = {
      periode: { date_debut: '2026-10-05', date_fin: '2026-11-04' },
      seuil_petits_effectifs: 5,
      grouper_par: /** @type {'region'} */ ('region'),
      total: block({ cas_mas: 9 }),
      groupes: [
        { cle: '1', libelle: 'Analamanga', ...block({ cas_mas: null }, ['cas_mas']) },
        { cle: '2', libelle: 'Atsinanana', ...block({ cas_mas: null }, ['cas_mas']) },
      ],
    }
    const result = protectStats(response, null)
    expect(result.period).toEqual({ start: '2026-10-05', end: '2026-11-04' })
    expect(result.total.counts.cas_mas).toEqual(shown(9))
    expect(result.byRegion.map((g) => [g.key, g.label, g.block.counts.cas_mas])).toEqual([
      ['1', 'Analamanga', HIDDEN],
      ['2', 'Atsinanana', HIDDEN],
    ])
    expect(result.byMonth).toEqual([])
  })
})
