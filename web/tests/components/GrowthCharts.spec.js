import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/errors'
import { referentielApi } from '@/api/referentiel'
import GrowthCharts from '@/components/children/GrowthCharts.vue'
import { mountWithApp } from '../helpers'

/** @param {string} date @param {number} age_jour @param {string} poids @param {string} taille */
const measurement = (date, age_jour, poids, taille) => ({
  id: date,
  date_mesure: date,
  age_jour,
  poids_kg: poids,
  taille_corrigee_cm: taille,
  whz: '-2.5',
  pb_mm: 118,
  flag_aberrant: false,
})
const measurements = [measurement('2026-06-04', 397, '7.90', '72.0'), measurement('2026-11-02', 548, '7.10', '74.2')]

/** @param {import('@/api/types').WhoReferenceQuery} query */
function reference(query) {
  const keys = [query.cle_min, query.cle_max]
  return {
    source: 'OMS 2006',
    indicateur: query.indicateur,
    sexe: query.sexe,
    unite_cle: 'jours',
    unite_valeur: 'kg',
    points: keys.map((k) => ({ cle: String(k), l: '0', m: '9', s: '0.1', mesure_type: '', courbes: { '-3': 7, '-2': 7.6, 0: 9, 2: 10.5, 3: 11.4 } })),
  }
}

describe('GrowthCharts', () => {
  it('draws the WHO curves of the child’s sex behind the measurements', async () => {
    const who = vi.spyOn(referentielApi, 'whoReference').mockImplementation(async (q) => reference(q))
    const wrapper = mountWithApp(GrowthCharts, { props: { measurements, sexe: 'F' } })
    await flushPromises()

    expect(who.mock.calls.map((c) => c[0].indicateur).sort()).toEqual(['lhfa', 'wfa', 'wfl'])
    expect(who.mock.calls.every((c) => c[0].sexe === 'F')).toBe(true)
    // Weight/age, height/age and weight/length each get 5 curves.
    expect(wrapper.findAll('.chart__ref')).toHaveLength(15)
    expect(wrapper.text()).toContain('médiane')
    expect(wrapper.text()).toContain('Poids selon la longueur')
    expect(wrapper.find('.chart__legend').text()).toContain('Courbes OMS')
    expect(wrapper.text()).toContain('standards de croissance OMS 2006')
  })

  it('falls back to the measurements alone when the tables are not loaded', async () => {
    vi.spyOn(referentielApi, 'whoReference').mockRejectedValue(new ApiError({ kind: 'not_found', status: 404 }))
    const wrapper = mountWithApp(GrowthCharts, { props: { measurements, sexe: 'M' } })
    await flushPromises()

    expect(wrapper.findAll('.chart__ref')).toHaveLength(0)
    expect(wrapper.findAll('.chart__point').length).toBeGreaterThan(0)
    expect(wrapper.text()).toContain('Les tables OMS ne sont pas chargées')
  })
})
