<script setup>
import { useI18n } from 'vue-i18n'
import AppButton from './AppButton.vue'
import AppDialog from './AppDialog.vue'

defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, required: true },
  message: { type: String, required: true },
  confirmLabel: { type: String, default: undefined },
  danger: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
})
defineEmits(['confirm', 'cancel'])
const { t } = useI18n()
</script>

<template>
  <AppDialog :open="open" :title="title" @close="$emit('cancel')">
    <p>{{ message }}</p>
    <slot />
    <template #actions>
      <AppButton variant="ghost" :disabled="busy" @click="$emit('cancel')">{{ t('common.cancel') }}</AppButton>
      <AppButton :variant="danger ? 'danger' : 'primary'" :loading="busy" @click="$emit('confirm')">
        {{ confirmLabel ?? t('common.confirm') }}
      </AppButton>
    </template>
  </AppDialog>
</template>
