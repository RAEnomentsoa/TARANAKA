<script setup>
import { nextTick, ref, useId, watch } from 'vue'
import { useI18n } from 'vue-i18n'

/**
 * Modal built on <dialog>: the browser traps focus, closes on Escape and
 * hides the rest of the page from screen readers. Focus returns to the
 * element that opened it.
 */
const props = defineProps({ open: { type: Boolean, required: true }, title: { type: String, required: true } })
const emit = defineEmits(['close'])

const { t } = useI18n()
/** @type {import('vue').Ref<HTMLDialogElement | null>} */
const dialog = ref(null)
const titleId = useId()
/** @type {HTMLElement | null} */
let opener = null

watch(
  () => props.open,
  async (open) => {
    await nextTick()
    const el = dialog.value
    if (!el) return
    if (open && !el.open) {
      opener = document.activeElement
      if (typeof el.showModal === 'function') el.showModal()
      else el.setAttribute('open', '')
    } else if (!open && el.open) {
      if (typeof el.close === 'function') el.close()
      else el.removeAttribute('open')
      opener?.focus()
    }
  },
  { immediate: true },
)

/** @param {Event} event */
function onCancel(event) {
  event.preventDefault()
  emit('close')
}
</script>

<template>
  <dialog ref="dialog" class="dialog" :aria-labelledby="titleId" @cancel="onCancel">
    <div v-if="open" class="dialog__panel">
      <header class="dialog__header">
        <h2 :id="titleId">{{ title }}</h2>
        <button type="button" class="dialog__close" :aria-label="t('common.close')" @click="emit('close')">
          <svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
            <path d="m5 5 10 10M15 5 5 15" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
          </svg>
        </button>
      </header>
      <div class="dialog__body"><slot /></div>
      <footer v-if="$slots.actions" class="dialog__actions"><slot name="actions" /></footer>
    </div>
  </dialog>
</template>

<style scoped>
.dialog {
  border: none;
  padding: 0;
  border-radius: var(--radius-lg);
  width: min(36rem, calc(100vw - 2rem));
  max-height: calc(100vh - 2rem);
  color: var(--ink);
  box-shadow: var(--shadow-float);
}

.dialog::backdrop {
  background: var(--backdrop);
}

.dialog__panel {
  display: flex;
  flex-direction: column;
}

.dialog__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-5) var(--space-5) 0;
  border-top: 4px solid var(--primary);
}

.dialog__close {
  flex: none;
  width: var(--target);
  height: var(--target);
  margin: calc(-1 * var(--space-3)) calc(-1 * var(--space-3)) 0 0;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  color: var(--ink-muted);
  cursor: pointer;
}

.dialog__close:hover {
  background: var(--sky-100);
}

.dialog__body {
  padding: var(--space-3) var(--space-5);
  overflow-y: auto;
}

.dialog__actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: var(--space-3);
  padding: var(--space-4) var(--space-5) var(--space-5);
}
</style>
