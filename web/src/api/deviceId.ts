/**
 * The backend records an X-Device-Id with every change (audit log and
 * conflict detection). The dashboard sends a stable id per browser.
 */
const KEY = 'taranaka.deviceId'
let cached: string | null = null

export function newUuid(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  // Fallback for old browsers: RFC 4122 version 4 from getRandomValues.
  const bytes = new Uint8Array(16)
  crypto.getRandomValues(bytes)
  bytes[6] = (bytes[6]! & 0x0f) | 0x40
  bytes[8] = (bytes[8]! & 0x3f) | 0x80
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export function deviceId(): string {
  if (cached) return cached
  try {
    cached = window.localStorage.getItem(KEY)
    if (!cached) {
      cached = `web-${newUuid()}`
      window.localStorage.setItem(KEY, cached)
    }
  } catch {
    cached = `web-${newUuid()}`
  }
  return cached
}
