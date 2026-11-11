<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router'
import { useAnnouncer } from '@/composables/useAnnouncer'
import { useIdleLogout } from '@/composables/useIdleLogout'
import { config } from '@/config'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'
import LanguageSwitch from '@/components/ui/LanguageSwitch.vue'
import NoticeTray from '@/components/ui/NoticeTray.vue'
import OfflineBanner from '@/components/ui/OfflineBanner.vue'
import BrandMark from './BrandMark.vue'
import CodeSearch from './CodeSearch.vue'
import NavIcon from './NavIcon.vue'

/** @typedef {import('@/utils/roles').Permission} Permission */

const { t } = useI18n()
const auth = useAuthStore()
const notifications = useNotificationsStore()
const route = useRoute()
const router = useRouter()
const { message: announcement, announce } = useAnnouncer()
const menuOpen = ref(false)

/**
 * @typedef {Object} NavItem
 * @property {string} name
 * @property {string} labelKey
 * @property {Permission} permission
 */

/** @type {NavItem[]} */
const NAV = [
  { name: 'referrals', labelKey: 'nav.referrals', permission: 'referrals:read' },
  { name: 'beneficiaries', labelKey: 'nav.beneficiaries', permission: 'beneficiaries:read' },
  { name: 'conflicts', labelKey: 'nav.conflicts', permission: 'conflicts:resolve' },
  { name: 'stats', labelKey: 'nav.stats', permission: 'stats:read' },
  { name: 'agents', labelKey: 'nav.agents', permission: 'agents:manage' },
  { name: 'accounts', labelKey: 'nav.accounts', permission: 'accounts:manage' },
  { name: 'territory', labelKey: 'nav.territory', permission: 'territory:manage' },
  { name: 'access-requests', labelKey: 'nav.accessRequests', permission: 'access-requests:review' },
]

const items = computed(() => NAV.filter((item) => auth.can(item.permission)))
const canSearch = computed(() => auth.can('referrals:read'))
const roleLabel = computed(() => (auth.user ? t(`roles.${auth.user.profile.code}`) : ''))

// After each navigation: close the menu, move focus to the page title and
// announce it, as a full page load would for a screen reader user.
watch(
  () => route.fullPath,
  async () => {
    menuOpen.value = false
    await nextTick()
    const title = document.querySelector('[data-page-title]')
    title?.focus({ preventScroll: true })
    if (title?.textContent) announce(t('app.pageLoaded', { title: title.textContent }))
  },
)

/** @returns {Promise<void>} */
async function logout() {
  await auth.logout()
  await router.push({ name: 'login' })
}

useIdleLogout(config.idleTimeoutMinutes, async () => {
  await logout()
  notifications.push(t('user.idleLogout', { minutes: config.idleTimeoutMinutes }), 'info')
})
</script>

<template>
  <div class="shell">
    <a class="skip-link" href="#main">{{ t('app.skipToContent') }}</a>

    <header class="topbar">
      <RouterLink :to="{ name: auth.homeRoute }" class="brand">
        <BrandMark />
        <span class="brand__text">
          <span class="brand__name">{{ t('app.name') }}</span>
          <span class="brand__tagline">{{ t('app.tagline') }}</span>
        </span>
      </RouterLink>

      <CodeSearch v-if="canSearch" class="topbar__search" />

      <div class="topbar__tools">
        <LanguageSwitch />
        <button
          type="button"
          class="menu-toggle"
          :aria-expanded="menuOpen"
          aria-controls="main-nav"
          @click="menuOpen = !menuOpen"
        >
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
            <path
              :d="menuOpen ? 'm6 6 12 12M18 6 6 18' : 'M4 7h16M4 12h16M4 17h16'"
              stroke="currentColor"
              stroke-width="2.4"
              stroke-linecap="round"
            />
          </svg>
          <span class="visually-hidden">{{ menuOpen ? t('nav.closeMenu') : t('nav.openMenu') }}</span>
        </button>
      </div>
    </header>

    <div class="layout">
      <nav id="main-nav" class="sidenav" :class="{ 'sidenav--open': menuOpen }" :aria-label="t('nav.label')">
        <ul class="sidenav__list">
          <li v-for="item in items" :key="item.name">
            <RouterLink :to="{ name: item.name }" class="sidenav__link" active-class="sidenav__link--active">
              <NavIcon :name="item.name" />
              {{ t(item.labelKey) }}
            </RouterLink>
          </li>
        </ul>
        <div class="sidenav__user">
          <p class="sidenav__name">{{ t('user.signedInAs', { name: auth.displayName }) }}</p>
          <p class="sidenav__role muted">{{ roleLabel }}</p>
          <button type="button" class="sidenav__logout" @click="logout">{{ t('user.logout') }}</button>
        </div>
      </nav>

      <main id="main" class="main" tabindex="-1">
        <OfflineBanner />
        <div :key="route.path" class="page-enter">
          <RouterView />
        </div>
      </main>
    </div>

    <p class="visually-hidden" aria-live="polite">{{ announcement }}</p>
    <NoticeTray />
  </div>
</template>

<style scoped>
.shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.skip-link {
  position: absolute;
  left: var(--space-4);
  top: -10rem;
  z-index: 100;
  padding: var(--space-3) var(--space-4);
  background: var(--primary);
  color: var(--white);
  font-weight: 700;
  border-radius: var(--radius-sm);
}

.skip-link:focus {
  top: var(--space-2);
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  gap: var(--space-4);
  padding: var(--space-2) var(--space-5);
  background: var(--white);
  border-bottom: 1px solid var(--line);
}

.brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--target);
  color: var(--ink);
  text-decoration: none;
  flex: none;
}

.brand__text {
  display: flex;
  flex-direction: column;
  line-height: 1.15;
}

.brand__name {
  font-weight: 700;
  font-size: var(--text-md);
  letter-spacing: 0.06em;
}

.brand__tagline {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.topbar__search {
  margin-left: auto;
}

.topbar__tools {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-left: auto;
}

.topbar__search + .topbar__tools {
  margin-left: 0;
}

.menu-toggle {
  display: none;
  width: var(--target);
  height: var(--target);
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--white);
  color: var(--primary);
  cursor: pointer;
}

.layout {
  flex: 1;
  display: grid;
  grid-template-columns: var(--nav-width) minmax(0, 1fr);
}

.sidenav {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: var(--space-5);
  padding: var(--space-5) var(--space-3);
  background: var(--white);
  border-right: 1px solid var(--line);
}

.sidenav__list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  position: sticky;
  top: 6rem;
}

.sidenav__link {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--target);
  padding: var(--space-2) var(--space-4);
  border-radius: var(--radius-sm);
  color: var(--ink);
  font-weight: 700;
  text-decoration: none;
  transition: background-color var(--duration) var(--easing);
}

.sidenav__link:hover {
  background: var(--hover);
  color: var(--primary);
}

.sidenav__link--active {
  background: var(--sky-100);
  color: var(--primary);
}

.sidenav__user {
  padding: var(--space-4);
  background: var(--sky-50);
  border-radius: var(--radius-md);
}

.sidenav__name {
  margin: 0;
  font-weight: 700;
}

.sidenav__role {
  margin: 0 0 var(--space-3);
  font-size: var(--text-sm);
}

.sidenav__logout {
  min-height: var(--target);
  padding: 0 var(--space-4);
  border: 1px solid var(--primary);
  border-radius: var(--radius-sm);
  background: var(--white);
  color: var(--primary);
  font-weight: 700;
  cursor: pointer;
  transition: background-color var(--duration) var(--easing);
}

.sidenav__logout:hover {
  background: var(--sky-100);
}

.main {
  width: 100%;
  max-width: var(--content-max);
  padding: var(--space-6) var(--space-6) var(--space-7);
}

.main:focus {
  outline: none;
}

@media (max-width: 60rem) {
  .layout {
    grid-template-columns: minmax(0, 1fr);
  }

  .menu-toggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  /* Small screens: the menu opens in the page flow, under the top bar. */
  .sidenav {
    display: none;
    border-right: none;
    border-bottom: 1px solid var(--line);
  }

  .sidenav--open {
    display: flex;
  }

  .sidenav__list {
    position: static;
  }

  .main {
    padding: var(--space-5) var(--space-4) var(--space-7);
  }

  .brand__tagline {
    display: none;
  }
}

@media (max-width: 36rem) {
  .topbar {
    flex-wrap: wrap;
    padding: var(--space-2) var(--space-4);
    gap: var(--space-2);
  }

  .topbar__search {
    order: 3;
    flex-basis: 100%;
    max-width: none;
  }
}
</style>
