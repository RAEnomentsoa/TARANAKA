import { flushPromises } from '@vue/test-utils'
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { accessRequestsApi, agentsApi } from '@/api/accounts'
import AccessRequestsView from '@/views/admin/AccessRequestsView.vue'
import AgentsView from '@/views/supervisor/AgentsView.vue'
import { mountWithApp } from '../helpers'

/** @typedef {import('@/api/types').AccessRequest} AccessRequest */
/** @typedef {import('@/api/types').AgentAccount} AgentAccount */

// jsdom has no <dialog> methods.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal ??= function () {
    this.setAttribute('open', '')
  }
  HTMLDialogElement.prototype.close ??= function () {
    this.removeAttribute('open')
  }
})

afterEach(() => vi.restoreAllMocks())

/**
 * @param {import('@vue/test-utils').VueWrapper} wrapper
 * @param {string} text
 */
function button(wrapper, text) {
  const found = wrapper.findAll('button').find((b) => b.text() === text)
  if (!found) throw new Error(`No button "${text}"`)
  return found
}

/**
 * @param {import('@vue/test-utils').VueWrapper} wrapper
 * @param {string} label
 */
function field(wrapper, label) {
  const node = wrapper.findAll('label').find((l) => l.text().startsWith(label))
  if (!node) throw new Error(`No field "${label}"`)
  return wrapper.find(`#${node.attributes('for')}`)
}

/** @type {AgentAccount} */
const RASOA = {
  id: 'a1',
  identifiant: 'ac.rasoa',
  nom: 'Rasoanirina',
  prenom: 'Rasoa',
  email: '',
  phone: '034 11 222 33',
  profile: { code: 'asc', libelle: 'Agent' },
  region_id: 1,
  is_active: true,
  date_creation: '2026-10-01T08:00:00Z',
}

describe('AgentsView (supervisor)', () => {
  it('lists the agents and creates one, showing the PIN once to hand over', async () => {
    vi.spyOn(agentsApi, 'list').mockResolvedValue([RASOA])
    const create = vi.spyOn(agentsApi, 'create').mockImplementation(async (a) => ({
      ...RASOA,
      id: 'a2',
      identifiant: a.identifiant,
      nom: a.nom,
      prenom: a.prenom,
      phone: a.phone,
    }))
    const wrapper = mountWithApp(AgentsView)
    await flushPromises()
    expect(wrapper.text()).toContain('ac.rasoa')
    expect(wrapper.text()).toContain('1 agent')

    await button(wrapper, 'Nouvel agent').trigger('click')
    await field(wrapper, 'Nom').setValue('Rabe')
    await field(wrapper, 'Prénom').setValue('Koto')
    await field(wrapper, 'Identifiant').setValue('koto.village')
    await field(wrapper, 'PIN de départ').setValue('1357')
    await field(wrapper, 'Confirmer le PIN').setValue('1357')
    await wrapper.find('#agent-form').trigger('submit')
    await flushPromises()

    expect(create).toHaveBeenCalledWith({ nom: 'Rabe', prenom: 'Koto', phone: '', identifiant: 'koto.village', pin: '1357' })
    expect(wrapper.text()).toContain('Compte créé pour Koto Rabe')
    expect(wrapper.text()).toContain('1357')
    expect(wrapper.text()).toContain('2 agents')

    await button(wrapper, "C'est noté").trigger('click')
    expect(wrapper.text()).not.toContain('1357')
  })

  it('refuses a short PIN before calling the server', async () => {
    vi.spyOn(agentsApi, 'list').mockResolvedValue([RASOA])
    const reset = vi.spyOn(agentsApi, 'resetPin')
    const wrapper = mountWithApp(AgentsView)
    await flushPromises()
    await button(wrapper, 'Nouveau PIN').trigger('click')
    await field(wrapper, 'Nouveau PIN').setValue('12')
    await wrapper.find('#reset-form').trigger('submit')
    expect(reset).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('4 à 6 chiffres')
  })

  it('resets a PIN', async () => {
    vi.spyOn(agentsApi, 'list').mockResolvedValue([RASOA])
    const reset = vi.spyOn(agentsApi, 'resetPin').mockResolvedValue({})
    const wrapper = mountWithApp(AgentsView)
    await flushPromises()
    await button(wrapper, 'Nouveau PIN').trigger('click')
    await field(wrapper, 'Nouveau PIN').setValue('8642')
    await field(wrapper, 'Confirmer le PIN').setValue('8642')
    await wrapper.find('#reset-form').trigger('submit')
    await flushPromises()
    expect(reset).toHaveBeenCalledWith('a1', '8642')
    expect(wrapper.text()).toContain('Nouveau PIN enregistré pour Rasoa Rasoanirina')
  })
})

/** @type {AccessRequest} */
const HERY = {
  id: 'r1',
  nom: 'Rakoto',
  prenom: 'Hery',
  email: 'hery@example.org',
  phone: '034 00 000 01',
  identifiant: 'hery.crenas',
  profil_demande: 'agent_csb',
  region_id: 1,
  region_nom: 'Analamanga',
  csb_id: 3,
  csb_nom: 'CRENAS Ambohitsoa',
  csb_type: 'crenas',
  fonction: 'Infirmier',
  message: 'Nouvel infirmier',
  statut: 'en_attente',
  date_creation: '2026-11-09T08:00:00Z',
}

const OPTIONS = {
  regions: [{ id: 1, nom: 'Analamanga' }],
  centres: [
    { id: 3, name: 'CRENAS Ambohitsoa', type_centre: 'crenas', region_id: 1 },
    { id: 5, name: 'CRENI Befelatanana', type_centre: 'creni', region_id: 1 },
  ],
}

describe('AccessRequestsView (admin)', () => {
  it('shows a pending request and approves it with a corrected centre', async () => {
    const list = vi.spyOn(accessRequestsApi, 'list').mockResolvedValue([HERY])
    vi.spyOn(accessRequestsApi, 'options').mockResolvedValue(OPTIONS)
    const approve = vi.spyOn(accessRequestsApi, 'approve').mockResolvedValue({ ...HERY, statut: 'approuvee' })
    const wrapper = mountWithApp(AccessRequestsView)
    await flushPromises()

    expect(list).toHaveBeenCalledWith('en_attente')
    expect(wrapper.text()).toContain('Hery Rakoto')
    expect(wrapper.text()).toContain('CRENAS Ambohitsoa (CRENAS)')
    expect(wrapper.find('a[href="tel:0340000001"]').exists()).toBe(true)

    await button(wrapper, 'Approuver').trigger('click')
    await field(wrapper, 'Centre de santé').setValue('5')
    await wrapper.find('#approve-form').trigger('submit')
    await flushPromises()

    expect(approve).toHaveBeenCalledWith('r1', { profil_demande: 'agent_csb', csb_id: 5, region_id: 1 })
    expect(wrapper.text()).not.toContain('Hery Rakoto')
    expect(wrapper.text()).toContain('Aucune demande en attente')
  })

  it('refuses with a reason', async () => {
    vi.spyOn(accessRequestsApi, 'list').mockResolvedValue([HERY])
    vi.spyOn(accessRequestsApi, 'options').mockResolvedValue(OPTIONS)
    const refuse = vi.spyOn(accessRequestsApi, 'refuse').mockResolvedValue({ ...HERY, statut: 'refusee' })
    const wrapper = mountWithApp(AccessRequestsView)
    await flushPromises()

    await button(wrapper, 'Refuser').trigger('click')
    await field(wrapper, 'Motif').setValue('Inconnu du centre')
    await wrapper.find('#refuse-form').trigger('submit')
    await flushPromises()
    expect(refuse).toHaveBeenCalledWith('r1', 'Inconnu du centre')
  })

  it('switches to the handled requests', async () => {
    const list = vi.spyOn(accessRequestsApi, 'list').mockResolvedValue([])
    vi.spyOn(accessRequestsApi, 'options').mockResolvedValue(OPTIONS)
    const wrapper = mountWithApp(AccessRequestsView)
    await flushPromises()
    await button(wrapper, 'Refusées').trigger('click')
    await flushPromises()
    expect(list).toHaveBeenLastCalledWith('refusee')
    expect(wrapper.text()).toContain('Aucune demande refusée')
  })
})
