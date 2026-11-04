import { afterEach, vi } from 'vitest'

// jsdom has no layout: stand-ins for the few layout APIs the app calls.
window.scrollTo = () => undefined
if (!('requestAnimationFrame' in window)) {
  Object.assign(window, { requestAnimationFrame: (cb: FrameRequestCallback) => setTimeout(() => cb(0), 0) })
}

afterEach(() => {
  vi.restoreAllMocks()
  window.sessionStorage.clear()
  window.localStorage.clear()
})
