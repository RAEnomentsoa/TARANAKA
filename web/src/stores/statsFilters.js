import { defineStore } from 'pinia'
import { ref } from 'vue'

/** @typedef {'30d' | '90d' | '365d' | 'custom'} PeriodPreset */

/**
 * What the supervisor chose in the statistics filters.
 * @typedef {Object} StatsFilterValues
 * @property {PeriodPreset} preset
 * @property {string} from
 * @property {string} to
 * @property {number | null} region
 */

/** Keeps the supervisor's last filters while they move around the dashboard. */
export const useStatsFiltersStore = defineStore('statsFilters', () => {
  /** @type {import('vue').Ref<StatsFilterValues | null>} */
  const values = ref(null)
  return { values }
})
