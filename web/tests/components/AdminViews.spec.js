import { flushPromises } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { accountsApi } from '@/api/accounts'
import { ApiError } from '@/api/errors'
import { referentielApi, territoryApi } from '@/api/referentiel'
import { useAuthStore } from '@/stores/auth'
import { can } from '@/utils/roles'
import AccountsView from '@/views/admin/AccountsView.vue'
import TerritoryView from '@/views/admin/TerritoryView.vue'
import { makeUser, mountWithApp } from '../helpers'

/** @typedef {import('@/api/types').AgentAccount} Account */

const ADMIN_ID = '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866'

/**
 * @param {Partial<Account>} extra
 * @returns {Account}
 */
function makeAccount(extra = {}) {
  return {
    id: '99999999-9999-4999-8999-999999999999',
    identifiant: 'inf.crenas',
    nom: 'Rakoto',
    prenom: 'Hery',
    email: '',
    phone: '034 00 000 01',
    profile: { code: 'agent_csb', libelle: 'agent_csb' },
    region_id: 1,
    csb_id: 3,
    is_active: true,
    date_creation: '2026-11-01T08:00:00Z',
    ...extra,
  }
}

function mockReferentiel() {
  vi.spyOn(referentielApi, 'provinces').mockResolvedValue([{ id: 1, nom: 'Antananarivo' }])
  vi.spyOn(referentielApi, 'regions').mockResolvedValue([
    { id: 1, nom: 'Analamanga', province_id: 1 },
    { id: 2, nom: 'Itasy', province_id: 1 },
  ])
  vi.spyOn(referentielApi, 'facilities').mockResolvedValue([
    { id: 3, name: 'CRENAS Ankadifotsy', type_centre: 'crenas', region_id: 1, tel: '020' },
  ])
}

/** @param {import('@vue/test-utils').VueWrapper} wrapper @param {string} label */
function button(wrapper, label) {
  return wrapper.findAll('button').find((b) => b.text() === label)
}

describe('admin permissions', () => {
  it('only the admin manages accounts and the territory', () => {
    for (const permission of /** @type {const} */ (['accounts:manage', 'territory:manage'])) {
      expect(can(makeUser('admin'), permission)).toBe(true)
      expect(can(makeUser('superviseur'), permission)).toBe(false)
      expect(can(makeUser('agent_csb'), permission)).toBe(false)
    }
  })
})

describe('AccountsView', () => {
  it('lists every profile with its centre or region', async () => {
    mockReferentiel()
    vi.spyOn(accountsApi, 'list').mockResolvedValue([
      makeAccount(),
      makeAccount({ id: 'b', identifiant: 'sup', nom: 'Rasoa', profile: { code: 'superviseur', libelle: '' }, csb_id: null, region_id: 2 }),
    ])
    const wrapper = mountWithApp(AccountsView, { attachTo: document.body })
    useAuthStore().user = makeUser('admin')
    await flushPromises()

    const rows = wrapper.findAll('tbody tr')
    expect(rows).toHaveLength(2)
    expect(rows[0].text()).toContain('Infirmier / médecin')
    expect(rows[0].text()).toContain('CRENAS Ankadifotsy')
    expect(rows[1].text()).toContain('Superviseur')
    expect(rows[1].text()).toContain('Itasy')
    wrapper.unmount()
  })

  it('sends the filters to the server', async () => {
    mockReferentiel()
    const list = vi.spyOn(accountsApi, 'list').mockResolvedValue([])
    const wrapper = mountWithApp(AccountsView)
    await flushPromises()
    await wrapper.find('select').setValue('asc')
    await flushPromises()
    expect(list).toHaveBeenLastCalledWith({ profil: 'asc', region: undefined, actif: undefined, q: undefined })
  })

  it('deactivates after confirmation', async () => {
    mockReferentiel()
    const account = makeAccount()
    vi.spyOn(accountsApi, 'list').mockResolvedValue([account])
    const update = vi.spyOn(accountsApi, 'update').mockResolvedValue({ ...account, is_active: false })
    const wrapper = mountWithApp(AccountsView, { attachTo: document.body })
    useAuthStore().user = makeUser('admin')
    await flushPromises()

    await button(wrapper, 'Désactiver').trigger('click')
    await flushPromises()
    const dialog = wrapper.findAll('dialog').find((d) => d.text().includes('ne pourra plus se connecter'))
    await dialog.findAll('button').find((b) => b.text() === 'Désactiver').trigger('click')
    await flushPromises()

    expect(update).toHaveBeenCalledWith(account.id, { is_active: false })
    expect(wrapper.find('tbody tr').text()).toContain('Désactivé')
    wrapper.unmount()
  })

  it('never offers to deactivate your own account', async () => {
    mockReferentiel()
    vi.spyOn(accountsApi, 'list').mockResolvedValue([
      makeAccount({ id: ADMIN_ID, profile: { code: 'admin', libelle: '' }, csb_id: null }),
    ])
    const wrapper = mountWithApp(AccountsView)
    useAuthStore().user = makeUser('admin')
    await flushPromises()
    expect(wrapper.find('tbody tr').text()).toContain('(vous)')
    expect(button(wrapper, 'Désactiver')).toBeUndefined()
  })
})

describe('TerritoryView', () => {
  it('lists the regions with their province and centres', async () => {
    mockReferentiel()
    const wrapper = mountWithApp(TerritoryView)
    await flushPromises()
    const items = wrapper.findAll('.list__item').map((i) => i.text())
    expect(items[0]).toContain('Analamanga')
    expect(items[0]).toContain('Antananarivo')
    expect(items[0]).toContain('1 centre')
    expect(items[1]).toContain('aucun centre')
  })

  it('adds a region and reloads the territory', async () => {
    mockReferentiel()
    const create = vi.spyOn(territoryApi, 'create').mockResolvedValue({ id: 9, nom: 'Bongolava', province_id: 1 })
    const wrapper = mountWithApp(TerritoryView, { attachTo: document.body })
    await flushPromises()

    await button(wrapper, 'Ajouter une région').trigger('click')
    await flushPromises()
    const form = wrapper.find('#territory-form')
    await form.find('input').setValue('Bongolava')
    await form.find('select').setValue('1')
    await form.trigger('submit')
    await flushPromises()

    expect(create).toHaveBeenCalledWith('regions', { nom: 'Bongolava', province_id: 1 })
    // Loaded once on open, once after the save.
    expect(referentielApi.regions).toHaveBeenCalledTimes(2)
    wrapper.unmount()
  })

  it("shows the server's reason when a row is still used", async () => {
    mockReferentiel()
    vi.spyOn(territoryApi, 'remove').mockRejectedValue(
      new ApiError({ kind: 'validation', status: 400, detail: 'Cette région est encore utilisée.' }),
    )
    const wrapper = mountWithApp(TerritoryView, { attachTo: document.body })
    await flushPromises()

    await wrapper.find('.list__item').findAll('button').find((b) => b.text() === 'Supprimer').trigger('click')
    await flushPromises()
    const dialog = wrapper.findAll('dialog').find((d) => d.text().includes('définitive'))
    await dialog.findAll('button').find((b) => b.text() === 'Supprimer').trigger('click')
    await flushPromises()

    const { useNotificationsStore } = await import('@/stores/notifications')
    const messages = useNotificationsStore().notices.map((n) => n.message)
    expect(messages).toContain('Cette région est encore utilisée.')
    wrapper.unmount()
  })
})
