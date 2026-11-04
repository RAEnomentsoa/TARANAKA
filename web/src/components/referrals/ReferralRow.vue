<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import type { Referral } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import ReferralCode from '@/components/ui/ReferralCode.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import UrgencyBadge from '@/components/ui/UrgencyBadge.vue'
import { useFormatters } from '@/composables/useFormatters'
import { urgencyOf } from '@/utils/triage'

const props = defineProps<{ referral: Referral; now: Date; canUpdate: boolean; busy: boolean }>()
defineEmits<{ arrived: [referral: Referral] }>()

const { t } = useI18n()
const fmt = useFormatters()
const urgency = computed(() => urgencyOf(props.referral))
const referredAt = computed(() => props.referral.date_referencement ?? props.referral.created_at)
const patient = computed(() =>
  props.referral.origine === 'grossesse' && props.referral.femme
    ? t('queue.patientMother', props.referral.femme)
    : t(`origin.${props.referral.origine}`),
)
</script>

<template>
  <li class="row" :class="`row--${urgency}`">
    <div class="row__urgency"><UrgencyBadge :urgency="urgency" /></div>
    <div class="row__main">
      <RouterLink :to="{ name: 'referral', params: { id: referral.id } }" class="row__link">
        <span class="visually-hidden">{{ t('queue.open', { code: referral.code_unique }) }}</span>
        <ReferralCode :code="referral.code_unique" aria-hidden="true" />
      </RouterLink>
      <span class="row__patient">{{ patient }}</span>
    </div>
    <p class="row__reason">
      <span class="visually-hidden">{{ t('queue.columns.reason') }} : </span>{{ referral.motif }}
    </p>
    <p class="row__waiting">
      <span class="visually-hidden">{{ t('queue.columns.waiting') }} : </span>
      <time :datetime="referredAt" :title="fmt.dateTime(referredAt)">{{ fmt.waiting(referredAt, now) }}</time>
      <span v-if="referral.en_retard" class="row__late" :title="t('referral.late')">
        <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">
          <circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="2" />
          <path d="M8 4.5V8l2.5 1.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
        </svg>
        {{ t('referral.lateShort') }}
      </span>
    </p>
    <div class="row__status"><StatusBadge :status="referral.status" /></div>
    <div class="row__action">
      <AppButton
        v-if="canUpdate && referral.status === 'envoye'"
        variant="secondary"
        :loading="busy"
        @click="$emit('arrived', referral)"
      >
        {{ t('queue.arrived') }}
      </AppButton>
    </div>
  </li>
</template>

<style scoped>
.row {
  display: grid;
  grid-template-columns: 9rem minmax(11rem, 1.2fr) minmax(10rem, 2fr) 7rem 9rem 11rem;
  align-items: center;
  gap: var(--space-3) var(--space-4);
  padding: var(--space-3) var(--space-4);
  background: var(--white);
  border-left: 8px solid var(--sky-200);
}

.row + .row {
  border-top: 1px solid var(--sky-200);
}

.row--rouge {
  border-left-color: var(--rouge-bar);
}

.row--orange {
  border-left-color: var(--orange-bar);
}

.row--jaune {
  border-left-color: var(--jaune-bar);
}

.row__main {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.row__link {
  display: inline-flex;
  align-items: center;
  min-height: var(--target-min);
  font-weight: 700;
  color: var(--primary);
}

.row__patient {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.row__reason {
  margin: 0;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.row__waiting {
  margin: 0;
  font-weight: 700;
}

.row__late {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  font-size: var(--text-sm);
  color: var(--rouge-ink);
}

.row__action {
  justify-self: end;
}

@media (max-width: 70rem) {
  .row {
    grid-template-columns: auto 1fr auto;
    grid-template-areas:
      'urgency main waiting'
      'reason reason reason'
      'status status action';
  }

  .row__urgency {
    grid-area: urgency;
  }

  .row__main {
    grid-area: main;
  }

  .row__waiting {
    grid-area: waiting;
    text-align: right;
  }

  .row__reason {
    grid-area: reason;
  }

  .row__status {
    grid-area: status;
  }

  .row__action {
    grid-area: action;
  }
}

@media (max-width: 30rem) {
  .row {
    grid-template-columns: 1fr auto;
    grid-template-areas:
      'urgency waiting'
      'main main'
      'reason reason'
      'status action';
  }
}
</style>
