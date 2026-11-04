import { ref, shallowRef, type Ref, type ShallowRef } from 'vue'

export interface AsyncState<T> {
  data: ShallowRef<T | null>
  error: Ref<unknown>
  loading: Ref<boolean>
  run: () => Promise<T | null>
}

/**
 * Loading / error / data for one request. A newer call wins: the answer of
 * an older one that finishes late is dropped.
 */
export function useAsync<T>(loader: () => Promise<T>): AsyncState<T> {
  const data = shallowRef<T | null>(null)
  const error = ref<unknown>(null)
  const loading = ref(false)
  let generation = 0

  async function run(): Promise<T | null> {
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
