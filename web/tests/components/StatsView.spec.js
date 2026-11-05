import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/errors'
import { referentielApi } from '@/api/referentiel'
import { statsApi } from '@/api/stats'
import { useAuthStore } from '@/stores/auth'
import StatsView from '@/views/supervisor/StatsView.vue'
import { makeUser, mountWithApp } from '../helpers'

/** @typedef {import('@/api/types').StatsQuery} StatsQuery */
/** @typedef {import('@/api/types').StatsResponse} StatsResponse */

const total = {
  indicateurs: {
    depistages: 210,
    enfants_depistes: 190,
    cas_mas: 9,
    cas_mam: 17,
    nourrissons_a_risque: null,
    referencements: 21,
    referencements_arrives: 18,
    rendez_vous_manques: 6,
    taux_arrivee_pct: 85.7,
    delai_moyen_arrivee_heures: 26.4,
    sorties_gueri: 9,
    sorties_transfere: null,
    sorties_non_repondant: 0,
    sorties_abandon: null,
    sorties_decede: 0,
  },
  masques: ['nourrissons_a_risque', 'sorties_transfere', 'sorties_abandon'],
}

/**
 * @param {StatsQuery} query
 * @returns {StatsResponse}
 */
function response(query) {
  const base = { periode: { date_debut: query.date_debut, date_fin: query.date_fin }, seuil_petits_effectifs: 5, total }
  if (query.grouper_par === 'mois') {
    return {
      ...base,
      grouper_par: 'mois',
      groupes: [
        {
          cle: '2026-10',
          libelle: '10/2026',
          indicateurs: { depistages: 80, cas_mas: null, cas_mam: 6 },
          masques: ['cas_mas'],
        },
      ],
    }
  }
  return {
    ...base,
    grouper_par: 'region',
    groupes: [
      {
        cle: '1',
        libelle: 'Analamanga',
        indicateurs: {
          depistages: 120,
          // 6, masked by the server's complementary suppression (D11).
          cas_mas: null,
          cas_mam: 10,
          referencements: 13,
          referencements_arrives: 11,
          rendez_vous_manques: null,
        },
        masques: ['cas_mas', 'rendez_vous_manques'],
      },
      {
        cle: '2',
        libelle: 'Atsinanana',
        indicateurs: {
          depistages: 90,
          cas_mas: null,
          cas_mam: 7,
          referencements: 8,
          referencements_arrives: 7,
          rendez_vous_manques: 0,
        },
        masques: ['cas_mas'],
      },
    ],
  }
}

function mockApis() {
  vi.spyOn(referentielApi, 'regions').mockResolvedValue([{ id: 1, nom: 'Analamanga', province_id: 1 }])
  vi.spyOn(referentielApi, 'facilities').mockResolvedValue([])
  return vi.spyOn(statsApi, 'get').mockImplementation(async (q) => response(q))
}

describe('StatsView', () => {
  it('shows aggregates by region and month, never a figure under 5', async () => {
    const get = mockApis()
    const wrapper = mountWithApp(StatsView)
    useAuthStore().user = makeUser('superviseur', { region_id: null })
    await flushPromises()

    expect(get.mock.calls.map((c) => c[0].grouper_par).sort()).toEqual(['mois', 'region'])
    const text = wrapper.text()
    expect(text).toContain('210')
    expect(text).toContain('Analamanga')
    expect(text).toContain('< 5')
    const figures = wrapper
      .findAll('td, dd')
      .map((n) => n.text().trim())
      .filter((s) => /^\d+$/.test(s))
      .map(Number)
    expect(figures.length).toBeGreaterThan(5)
    expect(figures.every((n) => n === 0 || n >= 5)).toBe(true)
    // The server hid Analamanga's MAS too, so Atsinanana's cannot be subtracted.
    const firstRow = wrapper.findAll('tbody tr')[0]
    expect(firstRow.findAll('td')[1].text()).toContain('< 5')
  })

  it('locks a regional supervisor to their region', async () => {
    const get = mockApis()
    const pinia = (await import('pinia')).createPinia()
    const { setActivePinia } = await import('pinia')
    setActivePinia(pinia)
    useAuthStore(pinia).user = makeUser('superviseur', { region_id: 1 })
    const wrapper = mountWithApp(StatsView, { pinia })
    await flushPromises()

    expect(get.mock.calls[0][0]).toMatchObject({ region: 1 })
    expect(wrapper.find('select').attributes('disabled')).toBeDefined()
  })

  it('downloads the audited CSV export from the server', async () => {
    mockApis()
    const exportCsv = vi.spyOn(statsApi, 'exportCsv').mockResolvedValue(new Blob(['groupe,indicateur,valeur']))
    URL.createObjectURL = vi.fn(() => 'blob:x')
    URL.revokeObjectURL = vi.fn()
    const wrapper = mountWithApp(StatsView)
    await flushPromises()

    await wrapper
      .findAll('button')
      .find((b) => b.text() === 'Exporter en CSV')
      .trigger('click')
    await flushPromises()

    expect(exportCsv).toHaveBeenCalledWith(expect.objectContaining({ grouper_par: 'region' }))
    expect(wrapper.text()).not.toContain('Exporter en CSV…')
  })

  it('explains a refused region', async () => {
    vi.spyOn(referentielApi, 'regions').mockResolvedValue([])
    vi.spyOn(referentielApi, 'facilities').mockResolvedValue([])
    vi.spyOn(statsApi, 'get').mockRejectedValue(new ApiError({ kind: 'forbidden', status: 403 }))
    const wrapper = mountWithApp(StatsView)
    await flushPromises()
    expect(wrapper.text()).toContain('Votre profil ne permet pas cette action.')
  })
})
