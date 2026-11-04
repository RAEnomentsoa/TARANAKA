<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useNotificationsStore } from '@/stores/notifications'

const store = useNotificationsStore()
const { t } = useI18n()
</script>

<template>
  <div class="tray" aria-live="polite" aria-atomic="false">
    <div v-for="notice in store.notices" :key="notice.id" class="notice" :class="`notice--${notice.tone}`">
      <span>{{ notice.message }}</span>
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
  border-radius: var(--radius-md);
  background: var(--ink);
  color: var(--white);
  font-weight: 700;
  box-shadow: var(--shadow-float);
}

.notice--success {
  border-left: 6px solid var(--success-on-dark);
}

.notice--info {
  border-left: 6px solid var(--sky-400);
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
