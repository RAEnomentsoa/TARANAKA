<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

/** @typedef {import('@/api/types').AgentContact} AgentContact */

/**
 * A health worker's name and a tap-to-call phone link, so the nurse can call
 * the community agent back (patient not arrived, conflict to check…).
 */
const props = defineProps({
  /** @type {import('vue').PropType<AgentContact | null>} */
  contact: { type: Object, default: null },
})

const { t } = useI18n()
const name = computed(() => (props.contact ? `${props.contact.prenom} ${props.contact.nom}`.trim() : ''))
/** tel: links take digits and a leading +, without spaces. */
const telHref = computed(() => (props.contact?.phone ? `tel:${props.contact.phone.replace(/[^\d+]/g, '')}` : null))
</script>

<template>
  <span v-if="contact" class="contact">
    <span class="contact__name">{{ name }}</span>
    <a v-if="telHref" :href="telHref" class="contact__phone" :aria-label="t('contact.call', { name, phone: contact.phone })">
      <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
        <path
          d="M4.2 1.5 6 4.3c.3.5.2 1.1-.2 1.5l-.9.9c.7 1.5 1.9 2.7 3.4 3.4l.9-.9c.4-.4 1-.5 1.5-.2l2.8 1.8c.5.3.7.9.5 1.4l-.6 1.3c-.3.7-1 1.1-1.8 1A11 11 0 0 1 1.5 3.4c-.1-.8.3-1.5 1-1.8l1.3-.6c.5-.2 1.1 0 1.4.5Z"
          fill="currentColor"
        />
      </svg>
      {{ contact.phone }}
    </a>
    <span v-else class="muted">{{ t('contact.noPhone') }}</span>
  </span>
  <span v-else class="muted">{{ t('common.unknown') }}</span>
</template>

<style scoped>
.contact {
  display: inline-flex;
  flex-direction: column;
  gap: var(--space-1);
}

.contact__name {
  font-weight: 700;
}

.contact__phone {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: var(--target-min);
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
</style>
