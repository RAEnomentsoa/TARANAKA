import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { createAppI18n } from '@/i18n'

/** @typedef {import('@vue/test-utils').ComponentMountingOptions} ComponentMountingOptions */
/** @typedef {import('pinia').Pinia} Pinia */
/** @typedef {import('vue').Component} Component */
/** @typedef {import('vue-router').Router} Router */
/** @typedef {import('@/i18n').AppLocale} AppLocale */
/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/api/types').Utilisateur} Utilisateur */

/**
 * @param {string} code
 * @param {Partial<Utilisateur>} [extra={}]
 * @returns {Utilisateur}
 */
export function makeUser(code, extra = {}) {
  return {
    id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
    nom: 'Rabe',
    prenom: 'Soa',
    profile: { code, libelle: code },
    region_id: 1,
    csb_id: code === 'agent_csb' ? 3 : null,
    ...extra,
  }
}

let counter = 0
/**
 * @param {Partial<Referral>} [extra={}]
 * @returns {Referral}
 */
export function makeReferral(extra = {}) {
  counter += 1
  /** @type {Referral} */
  const base = {
    id: `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`,
    code_unique: `R-0AA5-1104-${String(counter).padStart(2, '0')}`,
    origine: 'enfant',
    enfant_id: '11111111-1111-4111-8111-111111111111',
    grossesse_id: null,
    mesure_id: null,
    asc_id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
    asc: { nom: 'Rasoanirina', prenom: 'Rasoa', phone: '034 11 222 33' },
    csb_id: 3,
    priorite: 'haute',
    urgence: 'orange',
    motif: 'PB 112 mm',
    status: 'envoye',
    date_referencement: '2026-11-04T08:00:00Z',
    date_reception: null,
    date_prise_en_charge: null,
    date_suivi: null,
    date_sortie: null,
    issue_sortie: '',
    en_retard: false,
    femme: null,
    version: 1,
    created_at: '2026-11-04T08:00:00Z',
    updated_at: '2026-11-04T08:00:00Z',
    device_id: 'phone-1',
    deleted_at: null,
  }
  const merged = { ...base, ...extra }
  return {
    ...merged,
    // Keep the colour consistent with the priority unless a test sets it.
    urgence: extra.urgence ?? { urgente: 'rouge', haute: 'orange', normale: 'jaune' }[merged.priorite],
    date_referencement: extra.date_referencement ?? extra.created_at ?? base.date_referencement,
  }
}

/**
 * Mount with the real i18n, a fresh Pinia and an in-memory router.
 * @template T
 * @param {T} component
 * @param {ComponentMountingOptions<T> & { locale?: AppLocale, pinia?: Pinia, router?: Router }} [options={}]
 */
export function mountWithApp(component, options = {}) {
  const pinia = options.pinia ?? createPinia()
  setActivePinia(pinia)
  const router =
    options.router ??
    createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', name: 'home', component: { template: '<div />' } },
        { path: '/r/:id', name: 'referral', component: { template: '<div />' } },
        { path: '/c/:id', name: 'child', component: { template: '<div />' } },
        { path: '/s', name: 'search', component: { template: '<div />' } },
      ],
    })
  const i18n = createAppI18n(options.locale ?? 'fr')
  const rest = { ...options }
  delete rest.locale
  delete rest.pinia
  delete rest.router
  return mount(component, {
    ...rest,
    global: { ...(rest.global ?? {}), plugins: [pinia, i18n, router, ...(rest.global?.plugins ?? [])] },
  })
}

/**
 * @param {number} status
 * @param {unknown} body
 * @returns {Response}
 */
export function jsonResponse(status, body) {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
