<script setup>
import { useI18n } from 'vue-i18n'
import { http } from '@/api/http'
import { SUPPORTED_LOCALES, persistLocale } from '@/i18n'

/** @typedef {import('@/i18n').AppLocale} AppLocale */

const { t, locale } = useI18n()

/** @param {AppLocale} next */
function choose(next) {
  locale.value = next
  http.language = next
  persistLocale(next)
}
</script>

<template>
  <div class="lang" role="group" :aria-label="t('language.label')">
    <button
      v-for="code in SUPPORTED_LOCALES"
      :key="code"
      type="button"
      class="lang__option"
      :lang="code"
      :aria-pressed="locale === code"
      @click="choose(code)"
    >
      {{ t(`language.${code}`) }}
    </button>
  </div>
</template>

<style scoped>
.lang {
  display: inline-flex;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  overflow: hidden;
}

.lang__option {
  min-height: var(--target);
  padding: 0 var(--space-3);
  border: none;
  background: var(--white);
  color: var(--ink-muted);
  font-weight: 700;
  cursor: pointer;
}

.lang__option[aria-pressed='true'] {
  background: var(--sky-100);
  color: var(--primary);
}
</style>
