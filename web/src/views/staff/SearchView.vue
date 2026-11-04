<script setup lang="ts">
import { reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { referralsApi } from '@/api/referrals'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useReferralsStore } from '@/stores/referrals'

/** Search by referral code: a match opens the referral directly. */
const props = defineProps<{ code: string }>()
const { t } = useI18n()
const router = useRouter()
const store = useReferralsStore()

const form = reactive({ code: props.code })
const fieldError = ref<string | null>(null)
const searching = ref(false)
const error = ref<unknown>(null)
const notFound = ref<string | null>(null)

async function search(code: string): Promise<void> {
  error.value = null
  notFound.value = null
  if (!code.trim()) return
  searching.value = true
  try {
    const referral = await referralsApi.findByCode(code)
    if (referral) {
      store.remember([referral])
      await router.replace({ name: 'referral', params: { id: referral.id } })
    } else {
      notFound.value = code.trim().toUpperCase()
    }
  } catch (caught) {
    error.value = caught
  } finally {
    searching.value = false
  }
}

function submit(): void {
  fieldError.value = form.code.trim() ? null : t('search.required')
  if (fieldError.value) return
  if (form.code === props.code) void search(form.code)
  else void router.replace({ name: 'search', query: { code: form.code.trim() } })
}

watch(
  () => props.code,
  (code) => {
    form.code = code
    void search(code)
  },
  { immediate: true },
)
</script>

<template>
  <PageHeader :title="t('search.title')" :intro="t('search.hint')" />
  <form class="search-form" role="search" novalidate @submit.prevent="submit">
    <AppField v-slot="{ id, describedBy, invalid }" :label="t('search.label')" :error="fieldError" required>
      <input
        :id="id"
        v-model="form.code"
        class="search-form__input"
        type="search"
        autocomplete="off"
        autocapitalize="characters"
        spellcheck="false"
        :placeholder="t('search.placeholder')"
        :aria-describedby="describedBy"
        :aria-invalid="invalid"
      />
    </AppField>
    <AppButton type="submit" :loading="searching">{{ t('search.submit') }}</AppButton>
  </form>

  <div class="search-result" aria-live="polite">
    <LoadingState v-if="searching" :label="t('search.searching', { code: form.code.trim() })" />
    <ErrorState v-else-if="error" :error="error" retryable @retry="search(form.code)" />
    <InlineAlert v-else-if="notFound" tone="warning">{{ t('search.notFound', { code: notFound }) }}</InlineAlert>
  </div>
</template>

<style scoped>
.search-form {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--space-3);
  max-width: 36rem;
}

.search-form > :first-child {
  flex: 1 1 16rem;
}

.search-form__input {
  font-family: var(--font-code);
  font-size: var(--text-md);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.search-result {
  margin-top: var(--space-5);
}
</style>
