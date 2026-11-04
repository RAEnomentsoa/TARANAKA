import { createRouter, createWebHistory, type RouteRecordRaw, type Router, type RouterHistory } from 'vue-router'
import type { Pinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import type { Permission } from '@/utils/roles'

declare module 'vue-router' {
  interface RouteMeta {
    /** Reachable without being signed in. */
    public?: boolean
    /** Permission needed to open the page (utils/roles.ts). */
    permission?: Permission
    /** i18n key of the page title. */
    titleKey?: string
  }
}

export const routes: RouteRecordRaw[] = [
  {
    path: '/connexion',
    name: 'login',
    component: () => import('@/views/auth/LoginView.vue'),
    meta: { public: true, titleKey: 'login.title' },
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

export function installGuards(router: Router, pinia: Pinia): void {
  router.beforeEach(async (to) => {
    const auth = useAuthStore(pinia)
    await auth.restore()

    if (to.meta.public) {
      return to.name === 'login' && auth.isAuthenticated ? { name: auth.homeRoute } : true
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

export function createAppRouter(pinia: Pinia, history: RouterHistory = createWebHistory()): Router {
  const router = createRouter({
    history,
    routes,
    scrollBehavior: (_to, _from, saved) => saved ?? { top: 0 },
  })
  installGuards(router, pinia)
  return router
}
