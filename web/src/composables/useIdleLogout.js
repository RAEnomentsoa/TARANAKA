import { onBeforeUnmount, onMounted } from 'vue'

const EVENTS = ['pointerdown', 'keydown', 'scroll', 'touchstart']

/**
 * Signs the user out after a period without any interaction: dashboards are
 * often left open on a shared computer in the health centre.
 * @param {number} minutes
 * @param {() => void} onIdle
 */
export function useIdleLogout(minutes, onIdle) {
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timer

  function reset() {
    clearTimeout(timer)
    timer = setTimeout(onIdle, minutes * 60_000)
  }

  onMounted(() => {
    EVENTS.forEach((name) => window.addEventListener(name, reset, { passive: true }))
    reset()
  })

  onBeforeUnmount(() => {
    clearTimeout(timer)
    EVENTS.forEach((name) => window.removeEventListener(name, reset))
  })
}
