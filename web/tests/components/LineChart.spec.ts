import { describe, expect, it } from 'vitest'
import LineChart from '@/components/charts/LineChart.vue'
import { mountWithApp } from '../helpers'

const props = {
  title: 'Poids selon l’âge',
  xLabel: 'Âge (mois)',
  yLabel: 'kg',
  points: [
    { x: 6, y: 6.8 },
    { x: 7, y: 7.1, flagged: true },
    { x: 8, y: 7.0 },
  ],
  formatX: (x: number) => String(x),
  formatY: (y: number) => y.toFixed(1),
  thresholds: [{ value: 6, label: 'MAS', tone: 'rouge' as const }],
}

describe('LineChart', () => {
  it('draws one focusable, labelled point per measurement', () => {
    const wrapper = mountWithApp(LineChart, { props })
    const points = wrapper.findAll('.chart__point')
    expect(points).toHaveLength(3)
    expect(points[0]!.attributes('tabindex')).toBe('0')
    expect(points[1]!.attributes('aria-label')).toContain('Mesure à vérifier')
    expect(wrapper.find('.chart__threshold text').text()).toBe('MAS')
  })

  it('gives screen readers a text summary', () => {
    const wrapper = mountWithApp(LineChart, { props })
    expect(wrapper.find('.visually-hidden').text()).toContain('3 mesures')
  })

  it('shows a tooltip on focus and a table on demand', async () => {
    const wrapper = mountWithApp(LineChart, { props })
    await wrapper.findAll('.chart__point')[2]!.trigger('focus')
    expect(wrapper.find('.chart__tooltip').text()).toContain('7.0')

    const toggle = wrapper.find('.chart__toggle')
    expect(toggle.attributes('aria-expanded')).toBe('false')
    await toggle.trigger('click')
    expect(wrapper.findAll('tbody tr')).toHaveLength(3)
  })

  it('says so when there is nothing to draw', () => {
    const wrapper = mountWithApp(LineChart, { props: { ...props, points: [] } })
    expect(wrapper.find('svg').exists()).toBe(false)
    expect(wrapper.text()).toContain('pas assez de mesures')
  })
})
