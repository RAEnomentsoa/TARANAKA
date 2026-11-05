import { describe, expect, it } from 'vitest'
import { DAYS_PER_MONTH, referenceCurves, referenceQuery, weightForSizeRegime } from '@/utils/who'

/** @param {number} age_jour */
const measurement = (age_jour) => /** @type {import('@/api/types').Measurement} */ ({ age_jour })

describe('WHO reference queries', () => {
  it('asks only for the child’s age range, with a margin and about 60 points', () => {
    expect(referenceQuery('wfa', 'F', [397, 548])).toEqual({ indicateur: 'wfa', sexe: 'F', cle_min: 336, cle_max: 609, pas: 5 })
  })

  it('stays inside the official tables', () => {
    expect(referenceQuery('lhfa', 'M', [10])).toMatchObject({ cle_min: 0 })
    expect(referenceQuery('wfa', 'M', [1850])).toMatchObject({ cle_max: 1856 })
    expect(referenceQuery('wfl', 'M', [46])).toMatchObject({ cle_min: 45, cle_max: 51, pas: 1 })
  })

  it('asks nothing without measurements', () => {
    expect(referenceQuery('wfa', 'F', [])).toBeNull()
  })

  it('uses weight for length before 2 years and weight for height after', () => {
    const young = [measurement(400), measurement(700)]
    expect(weightForSizeRegime(young).indicateur).toBe('wfl')
    const crossed = [measurement(700), measurement(800)]
    const regime = weightForSizeRegime(crossed)
    expect(regime.indicateur).toBe('wfh')
    // Only the measurements taken standing are drawn against the height table.
    expect(regime.measurements.map((m) => m.age_jour)).toEqual([800])
  })
})

describe('WHO reference curves', () => {
  const reference = {
    source: 'OMS 2006',
    indicateur: /** @type {'wfa'} */ ('wfa'),
    sexe: /** @type {'F'} */ ('F'),
    unite_cle: 'jours',
    unite_valeur: 'kg',
    points: [
      { cle: '365.0', l: '0', m: '8.9', s: '0.1', mesure_type: '', courbes: { '-3': 7.0, '-2': 7.5, 0: 8.9, 2: 10.6, 3: 11.5 } },
      { cle: '395.0', l: '0', m: '9.2', s: '0.1', mesure_type: '', courbes: { '-3': 7.2, '-2': 7.7, 0: 9.2, 2: 10.9, 3: 11.9 } },
    ],
  }

  it('gives one curve per z-score, lowest first, with x mapped like the child', () => {
    const curves = referenceCurves(reference, (days) => days / DAYS_PER_MONTH)
    expect(curves.map((c) => c.z)).toEqual(['-3', '-2', '0', '2', '3'])
    expect(curves[2].points[0]).toEqual({ x: 365 / DAYS_PER_MONTH, y: 8.9 })
  })

  it('draws nothing when the table is missing or too short', () => {
    expect(referenceCurves(null)).toEqual([])
    expect(referenceCurves({ ...reference, points: reference.points.slice(0, 1) })).toEqual([])
  })
})
