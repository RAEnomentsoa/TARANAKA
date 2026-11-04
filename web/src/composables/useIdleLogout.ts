import { onBeforeUnmount, onMounted } from 'vue'

const EVENTS = ['pointerdown', 'keydown', 'scroll', 'touchstart'] as const

/**
 * Signs the user out after a period without any interaction: dashboards are
 * often left open on a shared computer in the health centre.
 */
export function useIdleLogout(minutes: number, onIdle: () => void): void {
  let timer: ReturnType<typeof setTimeout> | undefined

  function reset(): void {
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
