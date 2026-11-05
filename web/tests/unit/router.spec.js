import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { createMemoryHistory } from 'vue-router'
import { createAppRouter } from '@/router'
import { useAuthStore } from '@/stores/auth'
import { makeUser } from '../helpers'

/** @typedef {import('pinia').Pinia} Pinia */

describe('role-based routing', () => {
  /** @type {Pinia} */
  let pinia

  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
  })

  /**
   * @param {string} path
   * @param {string} [profile]
   */
  async function go(path, profile) {
    if (profile) useAuthStore(pinia).user = makeUser(profile)
    const router = createAppRouter(pinia, createMemoryHistory())
    await router.push(path)
    return router.currentRoute.value
  }

  it('sends anonymous visitors to the login, remembering the page', async () => {
    const route = await go('/referencements')
    expect(route.name).toBe('login')
    expect(route.query.redirect).toBe('/referencements')
  })

  it('opens the referral queue for nurses and doctors', async () => {
    expect((await go('/', 'agent_csb')).name).toBe('referrals')
    expect((await go('/conflits', 'agent_csb')).name).toBe('conflicts')
  })

  it('keeps nurses away from the supervisor statistics', async () => {
    expect((await go('/statistiques', 'agent_csb')).name).toBe('no-access')
  })

  it('sends supervisors to the statistics and keeps them away from patient files', async () => {
    expect((await go('/', 'superviseur')).name).toBe('stats')
    expect((await go('/referencements', 'superviseur')).name).toBe('no-access')
    expect((await go('/enfants/11111111-1111-4111-8111-111111111111', 'superviseur')).name).toBe('no-access')
  })

  it('gives administrators both sets of screens', async () => {
    expect((await go('/statistiques', 'admin')).name).toBe('stats')
    expect((await go('/referencements', 'admin')).name).toBe('referrals')
  })

  it('gives community agents no web screen', async () => {
    expect((await go('/', 'asc')).name).toBe('no-access')
  })

  it('sends a signed-in user away from the login page', async () => {
    expect((await go('/connexion', 'superviseur')).name).toBe('stats')
  })
})
