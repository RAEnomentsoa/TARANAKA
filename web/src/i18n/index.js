import { createI18n } from 'vue-i18n'
import fr from './locales/fr.json'
import mg from './locales/mg.json'

/** @typedef {typeof fr} MessageSchema */
export const SUPPORTED_LOCALES = ['mg', 'fr']
/** @typedef {(typeof SUPPORTED_LOCALES)[number]} AppLocale */

const STORAGE_KEY = 'taranaka.locale'

/**
 * @param {unknown} value
 * @returns {value is AppLocale}
 */
export function isSupportedLocale(value) {
  return typeof value === 'string' && SUPPORTED_LOCALES.includes(value)
}

/** @returns {AppLocale} */
export function initialLocale() {
  try {
    const saved = window.localStorage.getItem(STORAGE_KEY)
    if (isSupportedLocale(saved)) return saved
  } catch {
    // Storage disabled: use the browser language.
  }
  const browser = typeof navigator !== 'undefined' ? navigator.language.slice(0, 2) : 'fr'
  return isSupportedLocale(browser) ? browser : 'fr'
}

/** @param {AppLocale} [locale=initialLocale()] */
export function createAppI18n(locale = initialLocale()) {
  return createI18n({
    legacy: false,
    locale,
    fallbackLocale: 'fr',
    messages: { fr, mg },
    // A missing key must show up in development, not silently fall back.
    missingWarn: import.meta.env.DEV,
    fallbackWarn: import.meta.env.DEV,
  })
}

/** @param {AppLocale} locale */
export function persistLocale(locale) {
  try {
    window.localStorage.setItem(STORAGE_KEY, locale)
  } catch {
    // Not remembered: the choice still applies until the page closes.
  }
  document.documentElement.lang = locale
}
