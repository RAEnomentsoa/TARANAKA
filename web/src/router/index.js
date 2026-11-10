import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('vue-router').RouteRecordRaw} RouteRecordRaw */
/** @typedef {import('vue-router').Router} Router */
/** @typedef {import('vue-router').RouterHistory} RouterHistory */
/** @typedef {import('pinia').Pinia} Pinia */
/** @typedef {import('@/utils/roles').Permission} Permission */

/*
 * Route meta used by the guard:
 * - public: reachable without being signed in;
 * - permission: permission needed to open the page (utils/roles.js);
 * - titleKey: i18n key of the page title.
 */

/** @type {RouteRecordRaw[]} */
export const routes = [
  {
    path: '/connexion',
    name: 'login',
    component: () => import('@/views/auth/LoginView.vue'),
    meta: { public: true, titleKey: 'login.title' },
  },
  {
    path: '/demande-acces',
    name: 'access-request',
    component: () => import('@/views/auth/AccessRequestView.vue'),
    meta: { public: true, titleKey: 'accessRequest.title' },
  },
  {
    path: '/',
    component: () => import('@/components/layout/AppShell.vue'),
    children: [
      { path: '', name: 'home', redirect: () => ({ name: 'referrals' }) },
      {
        path: 'referencements',
        name: 'referrals',
        component: () => import('@/views/staff/ReferralQueueView.vue'),
        meta: { permission: 'referrals:read', titleKey: 'queue.title' },
      },
      {
        path: 'referencements/:id',
        name: 'referral',
        component: () => import('@/views/staff/ReferralDetailView.vue'),
        props: true,
        meta: { permission: 'referrals:read', titleKey: 'referral.code' },
      },
      {
        path: 'recherche',
        name: 'search',
        component: () => import('@/views/staff/SearchView.vue'),
        props: (route) => ({ code: typeof route.query.code === 'string' ? route.query.code : '' }),
        meta: { permission: 'referrals:read', titleKey: 'search.title' },
      },
      {
        path: 'enfants/:id',
        name: 'child',
        component: () => import('@/views/staff/ChildRecordView.vue'),
        props: true,
        meta: { permission: 'children:read', titleKey: 'child.title' },
      },
      {
        path: 'conflits',
        name: 'conflicts',
        component: () => import('@/views/staff/ConflictQueueView.vue'),
        meta: { permission: 'conflicts:resolve', titleKey: 'conflicts.title' },
      },
      {
        path: 'statistiques',
        name: 'stats',
        component: () => import('@/views/supervisor/StatsView.vue'),
        meta: { permission: 'stats:read', titleKey: 'stats.title' },
      },
      {
        path: 'agents',
        name: 'agents',
        component: () => import('@/views/supervisor/AgentsView.vue'),
        meta: { permission: 'agents:manage', titleKey: 'agents.title' },
      },
      {
        path: 'demandes-acces',
        name: 'access-requests',
        component: () => import('@/views/admin/AccessRequestsView.vue'),
        meta: { permission: 'access-requests:review', titleKey: 'accessRequests.title' },
      },
      {
        path: 'acces-refuse',
        name: 'no-access',
        component: () => import('@/views/NoAccessView.vue'),
        meta: { titleKey: 'access.title' },
      },
      {
        path: ':pathMatch(.*)*',
        name: 'not-found',
        component: () => import('@/views/NotFoundView.vue'),
        meta: { titleKey: 'notFound.title' },
      },
    ],
  },
]

/**
 * @param {Router} router
 * @param {Pinia} pinia
 */
export function installGuards(router, pinia) {
  router.beforeEach(async (to) => {
    const auth = useAuthStore(pinia)
    await auth.restore()

    if (to.meta.public) {
      const loginPage = to.name === 'login' || to.name === 'access-request'
      return loginPage && auth.isAuthenticated ? { name: auth.homeRoute } : true
    }
    if (!auth.isAuthenticated) {
      return { name: 'login', query: to.fullPath !== '/' ? { redirect: to.fullPath } : {} }
    }
    if (to.meta.permission && !auth.can(to.meta.permission)) {
      // "/" leads to the referral queue; a supervisor goes to the statistics instead.
      const fromHome = to.redirectedFrom?.name === 'home' && auth.homeRoute !== to.name
      return { name: fromHome ? auth.homeRoute : 'no-access' }
    }
    return true
  })
}

/**
 * @param {Pinia} pinia
 * @param {RouterHistory} [history=createWebHistory()]
 * @returns {Router}
 */
export function createAppRouter(pinia, history = createWebHistory()) {
  const router = createRouter({
    history,
    routes,
    scrollBehavior: (_to, _from, saved) => saved ?? { top: 0 },
  })
  installGuards(router, pinia)
  return router
}
