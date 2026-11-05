import { useI18n } from 'vue-i18n'
import { elapsed, formatDate, formatDateTime } from '@/utils/dates'
import { formatNumber } from '@/utils/numbers'

/**
 * Formatting for templates. Units and durations are translated; numbers and
 * dates use the dd/mm/yyyy and "12,5" conventions shared by both languages.
 */
export function useFormatters() {
  const { t } = useI18n()
  return {
    date: (iso) => formatDate(iso),
    dateTime: (iso) => formatDateTime(iso),
    number: (value, digits = 1) => formatNumber(value, digits),
    /**
     * @param {string} fromIso
     * @param {Date} [now]
     * @returns {string}
     */
    waiting(fromIso, now) {
      const { unit, value } = elapsed(fromIso, now)
      return t(`duration.${unit}`, value)
    },
  }
}
