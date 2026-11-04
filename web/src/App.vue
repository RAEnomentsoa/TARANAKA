<script setup>
import { onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterView, useRouter } from 'vue-router'
import { http } from '@/api/http'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores/notifications'

const auth = useAuthStore()
const router = useRouter()
const notifications = useNotificationsStore()
const { t } = useI18n()

// Every token refused by the server: back to the login, keeping the page.
const stop = http.onSessionExpired(() => {
  auth.expire()
  notifications.push(t('errors.session_expired'), 'info')
  const current = router.currentRoute.value
  if (current.name !== 'login') void router.push({ name: 'login', query: { redirect: current.fullPath } })
})
onBeforeUnmount(stop)
</script>

<template>
  <RouterView />
</template>
