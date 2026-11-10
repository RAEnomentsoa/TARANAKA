import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { beneficiariesApi } from '@/api/beneficiaries'
import { ApiError } from '@/api/errors'
import BeneficiariesView from '@/views/staff/BeneficiariesView.vue'
import BeneficiaryRecordView from '@/views/staff/BeneficiaryRecordView.vue'
import { makeReferral, mountWithApp } from '../helpers'

/** @typedef {import('@/api/types').BeneficiaryRow} BeneficiaryRow */

const WOMAN_ID = '44444444-4444-4444-8444-444444444444'
const PREGNANCY_ID = '55555555-5555-4555-8555-555555555555'

/**
 * @param {Partial<BeneficiaryRow>} [extra]
 * @returns {BeneficiaryRow}
 */
function makeRow(extra = {}) {
  return {
    id: WOMAN_ID,
    prenom: 'Voahangy',
    nom: 'Rasoa',
    phone: '034 11 111 11',
    region_id: 1,
    code_beneficiaire: 'K7QM4Z',
    suivie: false,
    grossesse_en_cours: true,
    nb_enfants: 2,
    ...extra,
  }
}

function makeDossier() {
  const sync = {
    version: 1,
    created_at: '2026-06-01T00:00:00Z',
    updated_at: '2026-06-01T00:00:00Z',
    device_id: 'phone-1',
    deleted_at: null,
  }
  return {
    beneficiaire: {
      id: WOMAN_ID,
      identifiant: 'voahangy.1234',
      prenom: 'Voahangy',
      nom: 'Rasoa',
      phone: '034 11 111 11',
      region_id: 1,
      code_beneficiaire: 'K7QM4Z',
      partage_cycle: false,
    },
    grossesses: [
      {
        id: PREGNANCY_ID,
        user_id: WOMAN_ID,
        ddr: '2026-05-01',
        dpa: '2027-02-05',
        dpa_saisie: null,
        terme_confirme_date: null,
        terme_confirme_jours: null,
        date_accouchement: null,
        mode_allaitement: '',
        terminee: false,
        ...sync,
      },
    ],
    signes_danger: [
      {
        id: '66666666-6666-4666-8666-666666666666',
        grossesse_id: PREGNANCY_ID,
        code: 'saignement_vaginal',
        periode: 'grossesse',
        date_signalement: '2026-10-02T08:00:00Z',
        ...sync,
      },
    ],
    contacts_soin: [
      { id: 'c1', grossesse_id: PREGNANCY_ID, type: 'cpn', numero: 2, date_faite: '2026-09-01', ...sync },
      { id: 'c2', grossesse_id: PREGNANCY_ID, type: 'cpn', numero: 1, date_faite: '2026-08-01', ...sync },
      { id: 'c3', grossesse_id: PREGNANCY_ID, type: 'pn', numero: 1, date_faite: '2026-09-15', ...sync },
    ],
    suivis_grossesse: [],
    mouvements_bebe: [],
    mouvements_evenements: [],
    alimentations: [],
    cycles: [],
    cycle_jours: [],
    enfants: [
      {
        id: '77777777-7777-4777-8777-777777777777',
        nom: 'Soa',
        mere_id: WOMAN_ID,
        mere: { id: WOMAN_ID, nom: 'Rasoa', prenom: 'Voahangy' },
        asc_id: null,
        grossesse_id: null,
        region_id: 1,
        date_naissance: '2025-01-10',
        sexe: 'F',
        statut_prise_en_charge: 'aucun',
        ...sync,
      },
    ],
    mesures: [],
    journaux_alimentaires: [],
    vaccins: [],
    tetees: [],
    rendez_vous: [],
    referencements: [makeReferral({ origine: 'grossesse', grossesse_id: PREGNANCY_ID })],
  }
}

describe('BeneficiariesView', () => {
  it('lists the zone with the code, the pregnancy and the children', async () => {
    vi.spyOn(beneficiariesApi, 'list').mockResolvedValue([makeRow(), makeRow({ id: 'x', prenom: 'Lalao', code_beneficiaire: 'RZM445', grossesse_en_cours: false, suivie: true, nb_enfants: 0 })])
    const wrapper = mountWithApp(BeneficiariesView, { props: { q: '' } })
    await flushPromises()

    expect(wrapper.text()).toContain('2 bénéficiaires')
    const first = wrapper.findAll('.list__item')[0]
    expect(first.text()).toContain('Voahangy Rasoa')
    expect(first.text()).toContain('K7QM4Z')
    expect(first.text()).toContain('Enceinte')
    expect(first.text()).toContain('2 enfants')
    const second = wrapper.findAll('.list__item')[1]
    expect(second.text()).toContain('Suivie')
    expect(second.text()).toContain('Aucun enfant')
  })

  it('falls back to the code lookup when the zone has no match', async () => {
    vi.spyOn(beneficiariesApi, 'list').mockResolvedValue([])
    const lookup = vi.spyOn(beneficiariesApi, 'lookup').mockResolvedValue(makeDossier())
    const wrapper = mountWithApp(BeneficiariesView, { props: { q: 'k7q-m4z' } })
    await flushPromises()

    expect(lookup).toHaveBeenCalledWith('K7QM4Z')
    expect(wrapper.vm.$router.currentRoute.value.params.id).toBe(WOMAN_ID)
  })

  it('shows the empty state when an unknown code answers 404', async () => {
    vi.spyOn(beneficiariesApi, 'list').mockResolvedValue([])
    vi.spyOn(beneficiariesApi, 'lookup').mockRejectedValue(
      new ApiError({ kind: 'not_found', status: 404 }),
    )
    const wrapper = mountWithApp(BeneficiariesView, { props: { q: 'AAAAAA' } })
    await flushPromises()
    expect(wrapper.text()).toContain('Aucune bénéficiaire trouvée.')
  })
})

describe('BeneficiaryRecordView', () => {
  it('shows the pregnancy, the CPN, the danger signs, the children and the referrals', async () => {
    vi.spyOn(beneficiariesApi, 'get').mockResolvedValue(makeDossier())
    const wrapper = mountWithApp(BeneficiaryRecordView, { props: { id: WOMAN_ID } })
    await flushPromises()

    const text = wrapper.text()
    expect(text).toContain('Voahangy Rasoa')
    expect(text).toContain('K7QM4Z')
    expect(text).toContain('Grossesse en cours')
    expect(text).toContain('semaines') // gestational age from the ddr
    expect(text).toContain('05/02/2027') // due date
    // CPN in order, postnatal contact left out of the CPN list.
    expect(text.indexOf('CPN 1')).toBeLessThan(text.indexOf('CPN 2'))
    // The danger code is translated.
    expect(text).toContain('Saignement vaginal')
    expect(text).toContain('pendant la grossesse')
    // The child links to their record.
    const childLink = wrapper.findAll('a').find((a) => a.text().includes('Soa'))
    expect(childLink.attributes('href')).toContain('/c/77777777')
    // The referral is listed with its code.
    expect(wrapper.find('.refs').text()).toContain('R-0AA5-1104')
  })

  it('says when there is no current pregnancy', async () => {
    const dossier = makeDossier()
    dossier.grossesses[0].terminee = true
    dossier.signes_danger = []
    vi.spyOn(beneficiariesApi, 'get').mockResolvedValue(dossier)
    const wrapper = mountWithApp(BeneficiaryRecordView, { props: { id: WOMAN_ID } })
    await flushPromises()
    expect(wrapper.text()).toContain('Aucune grossesse en cours.')
    expect(wrapper.text()).toContain('1 grossesse terminée dans le dossier')
    expect(wrapper.text()).toContain('Aucun signe de danger signalé.')
  })
})
