<script setup>
import { ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'

/** Header search: the code on the paper slip the family brings to the centre. */
const { t } = useI18n()
const router = useRouter()
const code = ref('')
const id = useId()

function submit() {
  const value = code.value.trim()
  if (!value) return
  void router.push({ name: 'search', query: { code: value } })
  code.value = ''
}
</script>

<template>
  <form class="search" role="search" @submit.prevent="submit">
    <label :for="id" class="visually-hidden">{{ t('search.label') }}</label>
    <input
      :id="id"
      v-model="code"
      class="search__input"
      type="search"
      autocomplete="off"
      autocapitalize="characters"
      spellcheck="false"
      :placeholder="t('search.placeholder')"
    />
    <button type="submit" class="search__button">
      <svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
        <circle cx="8.5" cy="8.5" r="5.5" fill="none" stroke="currentColor" stroke-width="2.2" />
        <path d="m13 13 4.5 4.5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
      </svg>
      <span class="search__label">{{ t('search.submit') }}</span>
    </button>
  </form>
</template>

<style scoped>
.search {
  display: flex;
  min-width: 0;
  flex: 1;
  max-width: 26rem;
}

.search__input {
  flex: 1;
  min-width: 0;
  min-height: var(--target);
  padding: 0 var(--space-3);
  border: 2px solid var(--field-border);
  border-right: none;
  border-radius: var(--radius-sm) 0 0 var(--radius-sm);
  font-family: var(--font-code);
  letter-spacing: 0.04em;
  text-transform: uppercase;
  background: var(--white);
}

.search__input::placeholder {
  color: var(--ink-muted);
  text-transform: none;
}

.search__button {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: var(--target);
  padding: 0 var(--space-4);
  border: 2px solid var(--primary);
  border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
  background: var(--primary);
  color: var(--white);
  font-weight: 700;
  cursor: pointer;
}

@media (max-width: 36rem) {
  .search__label {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
  }
}
</style>
