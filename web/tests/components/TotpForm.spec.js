import { describe, expect, it, vi } from 'vitest'
import TotpForm from '@/components/auth/TotpForm.vue'
import { mountWithApp } from '../helpers'

describe('TotpForm', () => {
  it('keeps digits only and submits a 6-digit code', async () => {
    const wrapper = mountWithApp(TotpForm, { props: { busy: false, enrolment: false, otpauthUri: null } })
    const input = wrapper.find('input')

    expect(input.attributes('autocomplete')).toBe('one-time-code')
    expect(input.attributes('inputmode')).toBe('numeric')

    await input.setValue('123 456')
    await wrapper.find('form').trigger('submit')

    expect(wrapper.emitted('submit')?.[0]).toEqual(['123456'])
  })

  it('explains a wrong format and links the message to the field', async () => {
    const wrapper = mountWithApp(TotpForm, { props: { busy: false, enrolment: false, otpauthUri: null } })
    await wrapper.find('input').setValue('12')
    await wrapper.find('form').trigger('submit')

    expect(wrapper.emitted('submit')).toBeUndefined()
    const input = wrapper.find('input')
    expect(input.attributes('aria-invalid')).toBe('true')
    const errorId = input
      .attributes('aria-describedby')
      .split(' ')
      .find((id) => id.endsWith('-error'))
    expect(wrapper.find(`[id="${errorId}"]`).text()).toContain('6 chiffres')
  })

  it('shows the QR code and the manual key on first use', async () => {
    const wrapper = mountWithApp(TotpForm, {
      props: {
        busy: false,
        enrolment: true,
        otpauthUri: 'otpauth://totp/TARANAKA:soa?secret=JBSWY3DPEHPK3PXP&issuer=TARANAKA',
      },
    })
    expect(wrapper.text()).toContain('JBSW Y3DP EHPK 3PXP')
    await vi.waitFor(() => expect(wrapper.find('img').exists()).toBe(true), { timeout: 3000 })

    const img = wrapper.find('img')
    expect(img.attributes('src')).toMatch(/^data:image\/png;base64,/)
    expect(img.attributes('alt')).toBeTruthy()
  })
})
