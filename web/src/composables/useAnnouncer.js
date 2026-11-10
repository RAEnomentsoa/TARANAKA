import { ref } from 'vue'

/** One shared polite live region for messages that are not visible notices. */
const message = ref('')

export function useAnnouncer() {
  /** @param {string} text */
  function announce(text) {
    // Clear first so the same text twice is read twice.
    message.value = ''
    requestAnimationFrame(() => {
      message.value = text
    })
  }
  return { message, announce }
}
