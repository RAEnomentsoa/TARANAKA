import { mount, type ComponentMountingOptions } from '@vue/test-utils'
import { createPinia, setActivePinia, type Pinia } from 'pinia'
import type { Component } from 'vue'
import { createMemoryHistory, createRouter, type Router } from 'vue-router'
import { createAppI18n, type AppLocale } from '@/i18n'
import type { Referral, Utilisateur } from '@/api/types'

export function makeUser(code: string, extra: Partial<Utilisateur> = {}): Utilisateur {
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
export function makeReferral(extra: Partial<Referral> = {}): Referral {
  counter += 1
  return {
    id: `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`,
    code_unique: `R-0AA5-1104-${String(counter).padStart(2, '0')}`,
    origine: 'enfant',
    enfant_id: '11111111-1111-4111-8111-111111111111',
    grossesse_id: null,
    mesure_id: null,
    asc_id: '0aa5a6f7-ba14-4ff9-8303-37fef7fdd866',
    csb_id: 3,
    priorite: 'haute',
    motif: 'PB 112 mm',
    status: 'envoye',
    femme: null,
    version: 1,
    created_at: '2026-11-04T08:00:00Z',
    updated_at: '2026-11-04T08:00:00Z',
    device_id: 'phone-1',
    deleted_at: null,
    ...extra,
  }
}

/** Mount with the real i18n, a fresh Pinia and an in-memory router. */
export function mountWithApp<T extends Component>(
  component: T,
  options: ComponentMountingOptions<T> & { locale?: AppLocale; pinia?: Pinia; router?: Router } = {},
) {
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
  } as ComponentMountingOptions<T>)
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
