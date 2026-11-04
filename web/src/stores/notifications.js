import { defineStore } from 'pinia'
import { ref } from 'vue'

/** @typedef {'success' | 'info' | 'error'} NoticeTone */

/**
 * @typedef {Object} Notice
 * @property {number} id
 * @property {NoticeTone} tone
 * @property {string} message
 */

const DISPLAY_MS = 6000
/** More than this would cover the page: the oldest notices go first. */
const MAX_VISIBLE = 3

/** Short confirmations ("Sortie enregistrée."), read out by screen readers. */
export const useNotificationsStore = defineStore('notifications', () => {
  /** @type {import('vue').Ref<Notice[]>} */
  const notices = ref([])
  let nextId = 1

  /** @param {number} id */
  function dismiss(id) {
    notices.value = notices.value.filter((n) => n.id !== id)
  }

  /**
   * @param {string} message
   * @param {NoticeTone} [tone='success']
   * @returns {number}
   */
  function push(message, tone = 'success') {
    const id = nextId++
    notices.value = [...notices.value, { id, tone, message }].slice(-MAX_VISIBLE)
    // Errors stay until dismissed: they need reading.
    if (tone !== 'error') setTimeout(() => dismiss(id), DISPLAY_MS)
    return id
  }

  return { notices, push, dismiss }
})
