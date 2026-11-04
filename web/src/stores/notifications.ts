import { defineStore } from 'pinia'
import { ref } from 'vue'

export type NoticeTone = 'success' | 'info' | 'error'

export interface Notice {
  id: number
  tone: NoticeTone
  message: string
}

const DISPLAY_MS = 6000
/** More than this would cover the page: the oldest notices go first. */
const MAX_VISIBLE = 3

/** Short confirmations ("Sortie enregistrée."), read out by screen readers. */
export const useNotificationsStore = defineStore('notifications', () => {
  const notices = ref<Notice[]>([])
  let nextId = 1

  function dismiss(id: number): void {
    notices.value = notices.value.filter((n) => n.id !== id)
  }

  function push(message: string, tone: NoticeTone = 'success'): number {
    const id = nextId++
    notices.value = [...notices.value, { id, tone, message }].slice(-MAX_VISIBLE)
    // Errors stay until dismissed: they need reading.
    if (tone !== 'error') setTimeout(() => dismiss(id), DISPLAY_MS)
    return id
  }

  return { notices, push, dismiss }
})
