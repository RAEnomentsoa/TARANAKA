<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import { http } from '@/api/http'
import { SUPPORTED_LOCALES, persistLocale } from '@/i18n'
import FlagIcon from './FlagIcon.vue'

/** @typedef {import('@/i18n').AppLocale} AppLocale */

/**
 * Language picker: a flag button that opens a short menu. Arrow keys move,
 * Enter or Space chooses, Escape closes and gives the focus back.
 */
const { t, locale } = useI18n()
const open = ref(false)
const menuId = useId()
/** @type {import('vue').Ref<HTMLElement | null>} */
const root = ref(null)
/** @type {import('vue').Ref<HTMLButtonElement | null>} */
const trigger = ref(null)
/** @type {import('vue').Ref<HTMLButtonElement[]>} */
const items = ref([])

/** @param {number} index */
function focusItem(index) {
  const count = items.value.length
  items.value[(index + count) % count]?.focus()
}

async function show() {
  open.value = true
  await nextTick()
  focusItem(Math.max(0, SUPPORTED_LOCALES.indexOf(/** @type {AppLocale} */ (locale.value))))
}

/** @param {boolean} [refocus=true] */
function hide(refocus = true) {
  if (!open.value) return
  open.value = false
  if (refocus) trigger.value?.focus()
}

/** @param {AppLocale} next */
function choose(next) {
  locale.value = next
  http.language = next
  persistLocale(next)
  hide()
}

/** @param {KeyboardEvent} event */
function onTriggerKey(event) {
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault()
    void show()
  }
}

/** @param {KeyboardEvent} event */
function onMenuKey(event) {
  const current = items.value.indexOf(/** @type {HTMLButtonElement} */ (document.activeElement))
  if (event.key === 'ArrowDown') focusItem(current + 1)
  else if (event.key === 'ArrowUp') focusItem(current - 1)
  else if (event.key === 'Home') focusItem(0)
  else if (event.key === 'End') focusItem(-1)
  else if (event.key === 'Escape') hide()
  else if (event.key === 'Tab') hide(false)
  else return
  event.preventDefault()
}

/** @param {PointerEvent} event */
function onOutside(event) {
  if (root.value && !root.value.contains(/** @type {Node} */ (event.target))) hide(false)
}

onMounted(() => document.addEventListener('pointerdown', onOutside))
onBeforeUnmount(() => document.removeEventListener('pointerdown', onOutside))
</script>

<template>
  <div ref="root" class="lang">
    <button
      ref="trigger"
      type="button"
      class="lang__trigger"
      aria-haspopup="menu"
      :aria-expanded="open"
      :aria-controls="menuId"
      @click="open ? hide() : show()"
      @keydown="onTriggerKey"
    >
      <FlagIcon :code="locale" />
      <span class="lang__code" aria-hidden="true">{{ locale.toUpperCase() }}</span>
      <span class="visually-hidden">{{ t('language.label') }} : {{ t(`language.${locale}`) }}</span>
      <svg class="lang__chevron" viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
        <path d="m2.5 4.5 3.5 3.5 3.5-3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </button>

    <Transition name="lang-menu">
      <ul v-show="open" :id="menuId" class="lang__menu" role="menu" :aria-label="t('language.label')" @keydown="onMenuKey">
        <li v-for="code in SUPPORTED_LOCALES" :key="code" role="none">
          <button
            ref="items"
            type="button"
            role="menuitemradio"
            class="lang__item"
            :lang="code"
            :aria-checked="locale === code"
            tabindex="-1"
            @click="choose(code)"
          >
            <FlagIcon :code="code" />
            <span class="lang__name">{{ t(`language.${code}`) }}</span>
            <svg v-if="locale === code" class="lang__check" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
              <path d="m3 8.5 3.2 3L13 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </button>
        </li>
      </ul>
    </Transition>
  </div>
</template>

<style scoped>
.lang {
  position: relative;
  display: inline-flex;
}

.lang__trigger {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: var(--target);
  padding: 0 var(--space-3);
  border: 1px solid var(--line);
  border-radius: 999px;
  background: var(--white);
  color: var(--ink);
  font-weight: 700;
  font-size: var(--text-sm);
  letter-spacing: 0.04em;
  cursor: pointer;
  transition:
    background-color var(--duration) var(--easing),
    border-color var(--duration) var(--easing);
}

.lang__trigger:hover,
.lang__trigger[aria-expanded='true'] {
  background: var(--hover);
  border-color: var(--primary);
}

.lang__chevron {
  color: var(--ink-muted);
  transition: transform var(--duration) var(--easing);
}

.lang__trigger[aria-expanded='true'] .lang__chevron {
  transform: rotate(180deg);
}

.lang__menu {
  position: absolute;
  top: calc(100% + var(--space-1));
  right: 0;
  z-index: 40;
  min-width: 11rem;
  margin: 0;
  padding: var(--space-1);
  list-style: none;
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  box-shadow: 0 8px 24px rgb(0 0 0 / 0.12);
}

.lang__item {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  width: 100%;
  min-height: var(--target);
  padding: 0 var(--space-3);
  border: none;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--ink);
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.lang__item:hover,
.lang__item:focus-visible {
  background: var(--hover);
}

.lang__item[aria-checked='true'] {
  color: var(--primary);
  font-weight: 700;
}

.lang__name {
  flex: 1;
}

.lang__check {
  color: var(--primary);
}

.lang-menu-enter-active,
.lang-menu-leave-active {
  transition:
    opacity var(--duration) var(--easing),
    transform var(--duration) var(--easing);
}

.lang-menu-enter-from,
.lang-menu-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}

@media (prefers-reduced-motion: reduce) {
  .lang-menu-enter-active,
  .lang-menu-leave-active,
  .lang__chevron {
    transition: none;
  }
}
</style>
