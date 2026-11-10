import { flushPromises } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import { http } from '@/api/http'
import LanguageSwitch from '@/components/ui/LanguageSwitch.vue'
import { mountWithApp } from '../helpers'

describe('LanguageSwitch', () => {
  it('shows the current flag and opens a menu of the three languages', async () => {
    const wrapper = mountWithApp(LanguageSwitch, { attachTo: document.body })
    const trigger = wrapper.find('.lang__trigger')
    expect(trigger.text()).toContain('FR')
    expect(trigger.attributes('aria-expanded')).toBe('false')

    await trigger.trigger('click')
    await flushPromises()
    expect(trigger.attributes('aria-expanded')).toBe('true')
    const items = wrapper.findAll('[role="menuitemradio"]')
    expect(items.map((i) => i.text())).toEqual(['Malagasy', 'Français', 'English'])
    expect(items[1].attributes('aria-checked')).toBe('true')
    // The focus goes to the current language.
    expect(document.activeElement).toBe(items[1].element)
    wrapper.unmount()
  })

  it('switches the language and closes', async () => {
    const wrapper = mountWithApp(LanguageSwitch, { attachTo: document.body })
    await wrapper.find('.lang__trigger').trigger('click')
    await flushPromises()
    await wrapper.findAll('[role="menuitemradio"]')[0].trigger('click')
    await flushPromises()

    expect(wrapper.find('.lang__trigger').text()).toContain('MG')
    expect(wrapper.find('.lang__trigger').attributes('aria-expanded')).toBe('false')
    expect(http.language).toBe('mg')
    expect(document.activeElement).toBe(wrapper.find('.lang__trigger').element)
    wrapper.unmount()
  })

  it('closes on Escape and gives the focus back', async () => {
    const wrapper = mountWithApp(LanguageSwitch, { attachTo: document.body })
    await wrapper.find('.lang__trigger').trigger('click')
    await flushPromises()
    await wrapper.find('[role="menu"]').trigger('keydown', { key: 'Escape' })
    expect(wrapper.find('.lang__trigger').attributes('aria-expanded')).toBe('false')
    expect(document.activeElement).toBe(wrapper.find('.lang__trigger').element)
    wrapper.unmount()
  })
})
