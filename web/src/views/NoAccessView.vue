<script setup>
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import PageHeader from '@/components/ui/PageHeader.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
</script>

<template>
  <PageHeader :title="t('access.title')" />
  <InlineAlert tone="warning">
    <p>{{ auth.roles.length ? t('access.forbidden') : t('access.body') }}</p>
  </InlineAlert>
  <p v-if="auth.homeRoute !== 'no-access'" class="back">
    <RouterLink :to="{ name: auth.homeRoute }">{{ t('access.backHome') }}</RouterLink>
  </p>
</template>

<style scoped>
.back {
  margin-top: var(--space-4);
}
</style>
