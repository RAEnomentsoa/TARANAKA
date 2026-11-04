import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { referentielApi } from '@/api/referentiel'
import { statsApi } from '@/api/stats'
import { ApiError } from '@/api/errors'
import type { StatsResponse } from '@/api/types'
import StatsView from '@/views/supervisor/StatsView.vue'
import { mountWithApp } from '../helpers'

const response: StatsResponse = {
  periode: { debut: '2026-08-06', fin: '2026-11-04' },
  totaux: { depistages: 210, mam: 17, mas: 4, referencements: 21, referencements_arrives: 18, delai_moyen_arrivee_heures: 26.4, rdv_manques: 6 },
  issues_sortie: { gueri: 9, transfere: 1, non_repondant: 0, abandon: 2, deces: 0 },
  par_zone: [
    { zone_id: 1, zone_nom: 'CSB Ambohidratrimo', depistages: 120, mam: 10, mas: 3, referencements: 13, referencements_arrives: 11, delai_moyen_arrivee_heures: 20, rdv_manques: 2 },
    { zone_id: 2, zone_nom: 'CSB Talatamaty', depistages: 90, mam: 7, mas: 1, referencements: 8, referencements_arrives: 7, delai_moyen_arrivee_heures: 35, rdv_manques: 4 },
  ],
  par_periode: [{ periode: '2026-10', depistages: 80, mam: 6, mas: 2 }],
}

describe('StatsView', () => {
  it('never shows a figure about fewer than 5 cases', async () => {
    vi.spyOn(referentielApi, 'regions').mockResolvedValue([])
    vi.spyOn(referentielApi, 'facilities').mockResolvedValue([])
    const get = vi.spyOn(statsApi, 'get').mockResolvedValue(response)

    const wrapper = mountWithApp(StatsView)
    await flushPromises()

    expect(get).toHaveBeenCalledOnce()
    expect(get.mock.calls[0]![0]).toMatchObject({ date_debut: expect.any(String), date_fin: expect.any(String) })
    const text = wrapper.text()
    expect(text).toContain('210')
    expect(text).toContain('< 5')
    // Numbers in table cells and tiles: none from 1 to 4.
    const figures = wrapper.findAll('td, dd').map((n) => n.text().trim()).filter((s) => /^\d+$/.test(s)).map(Number)
    expect(figures.length).toBeGreaterThan(5)
    expect(figures.every((n) => n === 0 || n >= 5)).toBe(true)
    // Not a single individual: no child names, codes or ids.
    expect(text).not.toMatch(/R-[0-9A-F]{4}-/)
  })

  it('explains that the statistics endpoint is not available yet', async () => {
    vi.spyOn(referentielApi, 'regions').mockResolvedValue([])
    vi.spyOn(referentielApi, 'facilities').mockResolvedValue([])
    vi.spyOn(statsApi, 'get').mockRejectedValue(new ApiError({ kind: 'not_implemented', status: 404 }))

    const wrapper = mountWithApp(StatsView)
    await flushPromises()

    expect(wrapper.text()).toContain("Cette fonction n'est pas encore disponible sur le serveur.")
  })
})
