import { describe, expect, it } from 'vitest'
import ProtectedValue from '@/components/stats/ProtectedValue.vue'
import ReferralCode from '@/components/ui/ReferralCode.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import UrgencyBadge from '@/components/ui/UrgencyBadge.vue'
import { mountWithApp } from '../helpers'

describe('badges', () => {
  it('names the urgency in words, not only in colour', () => {
    const wrapper = mountWithApp(UrgencyBadge, { props: { urgency: 'rouge' } })
    expect(wrapper.text()).toContain('Rouge')
    expect(wrapper.find('svg').attributes('aria-hidden')).toBe('true')
    expect(wrapper.classes()).toContain('urgency--rouge')
  })

  it('translates urgency and status into Malagasy', () => {
    expect(mountWithApp(UrgencyBadge, { props: { urgency: 'jaune' }, locale: 'mg' }).text()).toContain('Mavo')
    expect(mountWithApp(StatusBadge, { props: { status: 'recu' }, locale: 'mg' }).text()).toContain('Tonga ny marary')
  })

  it('reads the referral code as one label', () => {
    const wrapper = mountWithApp(ReferralCode, { props: { code: 'R-0AA5-1104-03' } })
    expect(wrapper.attributes('aria-label')).toBe('R-0AA5-1104-03')
    expect(wrapper.findAll('.code__group').map((g) => g.text())).toEqual(['R', '0AA5', '1104', '03'])
  })

  it('shows "< 5" with a spoken explanation for a hidden figure', () => {
    const hidden = mountWithApp(ProtectedValue, { props: { value: { hidden: true } } })
    expect(hidden.text()).toContain('< 5')
    expect(hidden.find('.visually-hidden').text()).toContain('moins de 5 cas')

    const shown = mountWithApp(ProtectedValue, { props: { value: { hidden: false, value: 42 } } })
    expect(shown.text()).toBe('42')
  })
})
