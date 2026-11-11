import { defineStore } from 'pinia'
import { ref } from 'vue'
import { referentielApi } from '@/api/referentiel'

/** @typedef {import('@/api/types').Facility} Facility */
/** @typedef {import('@/api/types').Region} Region */

/** Regions and facilities rarely change: loaded once per session. */
export const useReferentielStore = defineStore('referentiel', () => {
  /** @type {import('vue').Ref<Region[]>} */
  const regions = ref([])
  /** @type {import('vue').Ref<Facility[]>} */
  const facilities = ref([])
  /** @type {import('vue').Ref<import('@/api/types').Province[]>} */
  const provinces = ref([])
  /** @type {Promise<void> | null} */
  let loading = null

  /** @returns {Promise<void>} */
  function load() {
    loading ??= Promise.all([referentielApi.regions(), referentielApi.facilities(), referentielApi.provinces()])
      .then(([r, f, p]) => {
        regions.value = r
        facilities.value = f
        provinces.value = p
      })
      .catch((error) => {
        loading = null
        throw error
      })
    return loading
  }

  /**
   * @param {number | null | undefined} id
   * @returns {string | null}
   */
  function facilityName(id) {
    return facilities.value.find((f) => f.id === id)?.name ?? null
  }

  /**
   * @param {number | null} regionId
   * @returns {Facility[]}
   */
  function facilitiesOf(regionId) {
    return regionId === null ? facilities.value : facilities.value.filter((f) => f.region_id === regionId)
  }

  /**
   * After the admin changed the territory: fetch everything again.
   * @returns {Promise<void>}
   */
  function reload() {
    loading = null
    return load()
  }

  return { regions, facilities, provinces, load, reload, facilityName, facilitiesOf }
})
