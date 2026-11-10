import { describe, expect, it } from 'vitest'
import ArrivalChart from '@/components/stats/ArrivalChart.vue'
import MonthlyCasesChart from '@/components/stats/MonthlyCasesChart.vue'
import { HIDDEN } from '@/utils/privacy'
import { mountWithApp } from '../helpers'

/** @typedef {import('@/utils/privacy').ProtectedGroup} ProtectedGroup */

/** @param {number} value */
const shown = (value) => ({ hidden: false, value })

/**
 * @param {string} key
 * @param {Record<string, import('@/utils/privacy').Protected>} counts
 * @param {import('@/utils/privacy').Protected} [arrivalRate]
 * @returns {ProtectedGroup}
 */
function group(key, counts, arrivalRate = HIDDEN) {
  return {
    key,
    label: key,
    block: {
      counts: /** @type {any} */ ({ depistages: shown(40), ...counts }),
      arrivalRate,
      meanDelayHours: HIDDEN,
    },
  }
}

describe('MonthlyCasesChart', () => {
  const months = [
    group('09/2026', { cas_mas: shown(6), cas_mam: shown(8) }),
    group('10/2026', { cas_mas: shown(9), cas_mam: HIDDEN }),
    group('11/2026', { cas_mas: shown(7), cas_mam: shown(12) }),
  ]

  it('says in words how the last known month compares', () => {
    const wrapper = mountWithApp(MonthlyCasesChart, { props: { months } })
    // October has a hidden figure: November is compared with September.
    expect(wrapper.find('figcaption').text()).toBe("11/2026 : 19 cas, 5 de plus qu'en 09/2026.")
  })

  it('never draws a hidden figure to scale', () => {
    const wrapper = mountWithApp(MonthlyCasesChart, { props: { months } })
    const hidden = wrapper.findAll('path.seg--hidden')
    expect(hidden).toHaveLength(1)
    // Fixed 12px stub, whatever the real value.
    const heights = hidden[0]
      .attributes('d')
      .match(/V([\d.]+)/g)
      .map((v) => Number(v.slice(1)))
    expect(Math.abs(heights[0] - heights[1])).toBeLessThanOrEqual(12)
  })

  it('uses whole-number ticks and keeps every figure in the table view', async () => {
    const wrapper = mountWithApp(MonthlyCasesChart, { props: { months } })
    const ticks = wrapper.findAll('.grid text').map((n) => Number(n.text()))
    expect(ticks.every(Number.isInteger)).toBe(true)
    await wrapper.find('.table-toggle').trigger('click')
    const rows = wrapper.findAll('tbody tr')
    expect(rows).toHaveLength(3)
    expect(rows[1].text()).toContain('< 5')
  })

  it('gives each column a spoken label', () => {
    const wrapper = mountWithApp(MonthlyCasesChart, { props: { months } })
    expect(wrapper.findAll('rect.hit')[1].attributes('aria-label')).toBe('10/2026 : 9 MAS, < 5 MAM, 40 dépistages')
  })
})

describe('ArrivalChart', () => {
  it('puts the lowest arrival rate first, then hidden figures, then no referrals', () => {
    const groups = [
      group('Analamanga', { referencements: shown(20), referencements_arrives: shown(18) }, shown(90)),
      group('Itasy', { referencements: HIDDEN, referencements_arrives: HIDDEN }),
      group('Vakinankaratra', { referencements: shown(10), referencements_arrives: shown(5) }, shown(50)),
      group('Atsinanana', { referencements: shown(0), referencements_arrives: shown(0) }),
    ]
    const wrapper = mountWithApp(ArrivalChart, { props: { groups, caption: 'c', groupHeader: 'Région' } })
    const labels = wrapper.findAll('tbody th').map((th) => th.text())
    expect(labels).toEqual(['Vakinankaratra', 'Analamanga', 'Itasy', 'Atsinanana'])
    const rows = wrapper.findAll('tbody tr')
    expect(rows[0].text()).toContain('50 %')
    expect(rows[0].text()).toContain('5 sur 10')
    expect(rows[2].text()).toContain('< 5')
    expect(rows[2].find('.fill').exists()).toBe(false)
    expect(rows[3].text()).toContain('Aucun référencement')
  })
})
