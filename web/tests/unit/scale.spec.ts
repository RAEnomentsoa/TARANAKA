import { createPinia, setActivePinia } from 'pinia'
import { describe, expect, it } from 'vitest'
import { useNotificationsStore } from '@/stores/notifications'
import { extent, linear, niceTicks } from '@/utils/scale'

describe('chart scales', () => {
  it('widens a single date by the given duration, not by 10 % of the timestamp', () => {
    const day = Date.UTC(2026, 9, 26)
    const pad = 15 * 86_400_000
    expect(extent([day], [], pad)).toEqual({ min: day - pad, max: day + pad })
  })

  it('includes threshold lines in the range', () => {
    expect(extent([-2.3, -2.6], [-3, -2])).toEqual({ min: -3, max: -2 })
  })

  it('rounds the domain out to readable ticks', () => {
    const { domain, ticks } = niceTicks({ min: 7.1, max: 7.9 }, 5)
    expect(domain).toEqual({ min: 7, max: 8 })
    expect(ticks).toEqual([7, 7.2, 7.4, 7.6, 7.8, 8])
  })

  it('maps a domain onto a range, inverted for the y axis', () => {
    const y = linear({ min: 0, max: 10 }, [200, 0])
    expect(y(0)).toBe(200)
    expect(y(5)).toBe(100)
  })
})

describe('notices', () => {
  it('keeps only the three latest on screen', () => {
    setActivePinia(createPinia())
    const store = useNotificationsStore()
    for (const n of [1, 2, 3, 4]) store.push(`message ${n}`, 'error')
    expect(store.notices.map((n) => n.message)).toEqual(['message 2', 'message 3', 'message 4'])
  })
})
