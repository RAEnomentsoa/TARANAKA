<script setup>
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import PageHeader from '@/components/ui/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
</script>

<template>
  <PageHeader :title="t('notFound.title')" :intro="t('notFound.body')" />
  <RouterLink :to="{ name: auth.homeRoute }">{{ t('access.backHome') }}</RouterLink>
</template>
