import { defineStore } from 'pinia'
import { ref } from 'vue'
import { referentielApi } from '@/api/referentiel'
import type { Facility, Region } from '@/api/types'

/** Regions and facilities rarely change: loaded once per session. */
export const useReferentielStore = defineStore('referentiel', () => {
  const regions = ref<Region[]>([])
  const facilities = ref<Facility[]>([])
  let loading: Promise<void> | null = null

  function load(): Promise<void> {
    loading ??= Promise.all([referentielApi.regions(), referentielApi.facilities()])
      .then(([r, f]) => {
        regions.value = r
        facilities.value = f
      })
      .catch((error) => {
        loading = null
        throw error
      })
    return loading
  }

  function facilityName(id: number | null | undefined): string | null {
    return facilities.value.find((f) => f.id === id)?.name ?? null
  }

  function facilitiesOf(regionId: number | null): Facility[] {
    return regionId === null ? facilities.value : facilities.value.filter((f) => f.region_id === regionId)
  }

  return { regions, facilities, load, facilityName, facilitiesOf }
})
