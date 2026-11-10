<script setup>
import { useI18n } from 'vue-i18n'
import { useNotificationsStore } from '@/stores/notifications'

const store = useNotificationsStore()
const { t } = useI18n()
</script>

<template>
  <div class="tray" aria-live="polite" aria-atomic="false">
    <div v-for="notice in store.notices" :key="notice.id" class="notice" :class="`notice--${notice.tone}`">
      <svg class="notice__icon" viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
        <template v-if="notice.tone === 'success'">
          <circle cx="10" cy="10" r="9" fill="var(--success-on-dark)" />
          <path d="m6 10 3 3 5-6" stroke="var(--ink)" stroke-width="2" fill="none" stroke-linecap="round" />
        </template>
        <template v-else-if="notice.tone === 'error'">
          <path d="M10 1 19 18H1Z" fill="var(--white)" />
          <path d="M10 7v5M10 14.5v.5" stroke="var(--rouge-ink)" stroke-width="2" stroke-linecap="round" />
        </template>
        <template v-else>
          <circle cx="10" cy="10" r="9" fill="var(--sky-400)" />
          <path d="M10 9v5M10 6v.5" stroke="var(--ink)" stroke-width="2" stroke-linecap="round" />
        </template>
      </svg>
      <span class="notice__text">{{ notice.message }}</span>
      <button type="button" class="notice__close" :aria-label="t('common.close')" @click="store.dismiss(notice.id)">
        <svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true">
          <path d="m5 5 10 10M15 5 5 15" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
        </svg>
      </button>
    </div>
  </div>
</template>

<style scoped>
.tray {
  position: fixed;
  right: var(--space-4);
  bottom: var(--space-4);
  left: var(--space-4);
  z-index: 50;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: var(--space-2);
  pointer-events: none;
}

.notice {
  pointer-events: auto;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  max-width: 28rem;
  padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
  font-size: var(--text-sm);
  border-radius: var(--radius-md);
  background: var(--ink);
  color: var(--white);
  font-weight: 700;
  box-shadow: var(--shadow-float);
}

.notice__icon {
  flex: none;
}

.notice__text {
  flex: 1;
}

.notice--error {
  background: var(--rouge-ink);
}

.notice__close {
  width: var(--target);
  height: var(--target);
  border: none;
  background: none;
  color: inherit;
  cursor: pointer;
  border-radius: var(--radius-sm);
}
</style>
