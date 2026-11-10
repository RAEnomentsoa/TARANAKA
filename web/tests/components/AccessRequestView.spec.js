import { flushPromises } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { accessRequestsApi } from '@/api/accounts'
import { ApiError } from '@/api/errors'
import AccessRequestView from '@/views/auth/AccessRequestView.vue'
import { mountWithApp } from '../helpers'

const OPTIONS = {
  regions: [
    { id: 1, nom: 'Analamanga' },
    { id: 2, nom: 'Vakinankaratra' },
  ],
  centres: [
    { id: 3, name: 'CRENAS Ambohitsoa', type_centre: 'crenas', region_id: 1 },
    { id: 4, name: 'CRENAS Antsirabe', type_centre: 'crenas', region_id: 2 },
  ],
}

async function mountForm() {
  vi.spyOn(accessRequestsApi, 'options').mockResolvedValue(OPTIONS)
  const wrapper = mountWithApp(AccessRequestView, {
    router: undefined,
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  })
  await flushPromises()
  return wrapper
}

/**
 * @param {import('@vue/test-utils').VueWrapper} wrapper
 * @param {Record<string, string>} values label text → value
 */
async function fill(wrapper, values) {
  for (const [label, value] of Object.entries(values)) {
    const node = wrapper.findAll('label').find((l) => l.text().startsWith(label))
    if (!node) throw new Error(`No field "${label}"`)
    await wrapper.find(`#${node.attributes('for')}`).setValue(value)
  }
}

const IDENTITY = {
  Nom: 'Rakoto',
  Prénom: 'Hery',
  Téléphone: '034 00 000 01',
  Identifiant: 'hery.crenas',
  'Code PIN': '2468',
  'Confirmer le PIN': '2468',
}

afterEach(() => vi.restoreAllMocks())

describe('AccessRequestView', () => {
  it('does not offer the community agent profile', async () => {
    const wrapper = await mountForm()
    const values = wrapper.findAll('input[type="radio"]').map((r) => r.attributes('value'))
    expect(values).toEqual(['agent_csb', 'superviseur'])
    expect(wrapper.text()).toContain('votre superviseur')
  })

  it('never capitalises the username', async () => {
    const wrapper = await mountForm()
    const input = wrapper.find('input[autocomplete="username"]')
    expect(input.attributes('autocapitalize')).toBe('none')
    expect(input.attributes('autocorrect')).toBe('off')
  })

  it('checks the form before sending', async () => {
    const submit = vi.spyOn(accessRequestsApi, 'submit')
    const wrapper = await mountForm()
    await wrapper.find('input[value="agent_csb"]').setValue()
    await fill(wrapper, { ...IDENTITY, 'Confirmer le PIN': '9999' })
    await wrapper.find('form').trigger('submit')
    expect(submit).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('Les deux PIN ne sont pas identiques.')
    // A nurse must name their centre.
    expect(wrapper.text()).toContain('Ce champ est obligatoire.')
  })

  it('sends a nurse request with the centre, and confirms', async () => {
    const submit = vi.spyOn(accessRequestsApi, 'submit').mockResolvedValue(/** @type {any} */ ({ id: 'x', statut: 'en_attente' }))
    const wrapper = await mountForm()
    await wrapper.find('input[value="agent_csb"]').setValue()
    await fill(wrapper, { ...IDENTITY, Région: '1' })
    await fill(wrapper, { 'Centre de santé': '3' })
    // Only the centres of the chosen region are offered.
    const centreOptions = wrapper.findAll('option').map((o) => o.text())
    expect(centreOptions.some((t) => t.includes('Antsirabe'))).toBe(false)
    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(submit).toHaveBeenCalledWith(
      expect.objectContaining({
        profil_demande: 'agent_csb',
        csb_id: 3,
        region_id: 1,
        identifiant: 'hery.crenas',
        pin: '2468',
        email: '',
      }),
    )
    expect(wrapper.text()).toContain('Demande envoyée')
  })

  it('sends a national supervisor request without a centre', async () => {
    const submit = vi.spyOn(accessRequestsApi, 'submit').mockResolvedValue(/** @type {any} */ ({ id: 'x' }))
    const wrapper = await mountForm()
    await wrapper.find('input[value="superviseur"]').setValue()
    await fill(wrapper, IDENTITY)
    await wrapper.find('form').trigger('submit')
    await flushPromises()
    expect(submit).toHaveBeenCalledWith(expect.objectContaining({ profil_demande: 'superviseur', csb_id: null, region_id: null }))
  })

  it('shows the server message next to the field', async () => {
    vi.spyOn(accessRequestsApi, 'submit').mockRejectedValue(
      new ApiError({ kind: 'validation', status: 400, fieldErrors: { identifiant: ['Cet identifiant est déjà utilisé.'] } }),
    )
    const wrapper = await mountForm()
    await wrapper.find('input[value="superviseur"]').setValue()
    await fill(wrapper, IDENTITY)
    await wrapper.find('form').trigger('submit')
    await flushPromises()
    expect(wrapper.text()).toContain('Cet identifiant est déjà utilisé.')
    expect(wrapper.text()).not.toContain('Demande envoyée')
  })
})
