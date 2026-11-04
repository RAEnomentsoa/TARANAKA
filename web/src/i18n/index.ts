import { createI18n } from 'vue-i18n'
import fr from './locales/fr.json'
import mg from './locales/mg.json'

export type MessageSchema = typeof fr
export const SUPPORTED_LOCALES = ['mg', 'fr'] as const
export type AppLocale = (typeof SUPPORTED_LOCALES)[number]

const STORAGE_KEY = 'taranaka.locale'

export function isSupportedLocale(value: unknown): value is AppLocale {
  return typeof value === 'string' && (SUPPORTED_LOCALES as readonly string[]).includes(value)
}

export function initialLocale(): AppLocale {
  try {
    const saved = window.localStorage.getItem(STORAGE_KEY)
    if (isSupportedLocale(saved)) return saved
  } catch {
    // Storage disabled: use the browser language.
  }
  const browser = typeof navigator !== 'undefined' ? navigator.language.slice(0, 2) : 'fr'
  return isSupportedLocale(browser) ? browser : 'fr'
}

export function createAppI18n(locale: AppLocale = initialLocale()) {
  return createI18n<[MessageSchema], AppLocale, false>({
    legacy: false,
    locale,
    fallbackLocale: 'fr',
    messages: { fr, mg },
    // A missing key must show up in development, not silently fall back.
    missingWarn: import.meta.env.DEV,
    fallbackWarn: import.meta.env.DEV,
  })
}

export function persistLocale(locale: AppLocale): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, locale)
  } catch {
    // Not remembered: the choice still applies until the page closes.
  }
  document.documentElement.lang = locale
}
