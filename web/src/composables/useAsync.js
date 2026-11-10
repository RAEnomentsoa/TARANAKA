import { ref, shallowRef } from 'vue'

/** @typedef {import('vue').Ref} Ref */
/** @typedef {import('vue').ShallowRef} ShallowRef */

/**
 * @typedef {Object} AsyncState
 * @property {ShallowRef<T | null>} data
 * @property {Ref<unknown>} error
 * @property {Ref<boolean>} loading
 * @property {() => Promise<T | null>} run
 */

/**
 * Loading / error / data for one request. A newer call wins: the answer of
 * an older one that finishes late is dropped.
 * @template T
 * @param {() => Promise<T>} loader
 * @returns {AsyncState<T>}
 */
export function useAsync(loader) {
  /** @type {import('vue').ShallowRef<T | null>} */
  const data = shallowRef(null)
  /** @type {import('vue').Ref<unknown>} */
  const error = ref(null)
  const loading = ref(false)
  let generation = 0

  /** @returns {Promise<T | null>} */
  async function run() {
    const current = ++generation
    loading.value = true
    error.value = null
    try {
      const result = await loader()
      if (current === generation) data.value = result
      return result
    } catch (caught) {
      if (current === generation) error.value = caught
      return null
    } finally {
      if (current === generation) loading.value = false
    }
  }

  return { data, error, loading, run }
}
