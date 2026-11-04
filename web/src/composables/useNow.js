import { onBeforeUnmount, onMounted, ref } from 'vue'

/**
 * The current time, refreshed every minute for "waiting for 3 h" labels.
 * @param {*} [intervalMs=60_000]
 */
export function useNow(intervalMs = 60_000) {
  const now = ref(new Date())
  /** @type {ReturnType<typeof setInterval> | undefined} */
  let timer
  onMounted(() => {
    timer = setInterval(() => (now.value = new Date()), intervalMs)
  })
  onBeforeUnmount(() => clearInterval(timer))
  return now
}
