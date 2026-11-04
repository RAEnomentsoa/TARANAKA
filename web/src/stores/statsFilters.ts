import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { StatsFilterValues } from '@/components/stats/StatsFilters.vue'

/** Keeps the supervisor's last filters while they move around the dashboard. */
export const useStatsFiltersStore = defineStore('statsFilters', () => {
  const values = ref<StatsFilterValues | null>(null)
  return { values }
})
