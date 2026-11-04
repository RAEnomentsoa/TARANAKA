<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useFormatters } from '@/composables/useFormatters'
import { STATUS_ORDER } from '@/utils/triage'

/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/api/types').ReferralStatus} ReferralStatus */

/**
 * The referral's life cycle (spec section 7), each reached step with its
 * date. A discharge may skip steps (D7): a step without a date in a closed
 * referral is shown as skipped, not as done.
 */
const props = defineProps({
  /** @type {import('vue').PropType<Referral>} */
  referral: { type: Object, required: true },
})
const { t } = useI18n()
const fmt = useFormatters()
const currentIndex = computed(() => STATUS_ORDER.indexOf(props.referral.status))

/** @type {Record<ReferralStatus, keyof Referral>} */
const DATE_OF = {
  envoye: 'date_referencement',
  recu: 'date_reception',
  pris_en_charge: 'date_prise_en_charge',
  en_suivi: 'date_suivi',
  sortie: 'date_sortie',
}

/** @typedef {'done' | 'current' | 'todo' | 'skipped'} StepState */
/** @type {Record<StepState, string>} */
const STATE_LABEL = {
  done: 'referral.stepDone',
  current: 'referral.stepCurrent',
  todo: 'referral.stepTodo',
  skipped: 'referral.stepSkipped',
}

/**
 * @param {ReferralStatus} step
 * @returns {string | null}
 */
function dateOf(step) {
  const value = props.referral[DATE_OF[step]]
  return typeof value === 'string' ? value : null
}

/**
 * @param {ReferralStatus} step
 * @param {number} index
 * @returns {StepState}
 */
function state(step, index) {
  if (props.referral.status === 'sortie') return step === 'sortie' || dateOf(step) ? 'done' : 'skipped'
  if (index < currentIndex.value) return 'done'
  if (index === currentIndex.value) return 'current'
  return 'todo'
}
</script>

<template>
  <ol class="stepper" :aria-label="t('referral.progress')">
    <li
      v-for="(step, index) in STATUS_ORDER"
      :key="step"
      class="stepper__step"
      :class="`stepper__step--${state(step, index)}`"
      :aria-current="state(step, index) === 'current' ? 'step' : undefined"
    >
      <span class="stepper__dot" aria-hidden="true">
        <svg v-if="state(step, index) === 'done'" viewBox="0 0 16 16" width="14" height="14">
          <path d="m3.5 8.5 3 3 6-7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
        </svg>
      </span>
      <span class="stepper__label">{{ t(`status.${step}`) }}</span>
      <span class="visually-hidden">({{ t(STATE_LABEL[state(step, index)]) }})</span>
      <time v-if="dateOf(step) && state(step, index) !== 'todo'" class="stepper__date" :datetime="dateOf(step)">
        {{ fmt.dateTime(dateOf(step)) }}
      </time>
    </li>
  </ol>
</template>

<style scoped>
.stepper {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
}

.stepper__step {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--space-2);
  text-align: center;
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.stepper__step::before {
  content: '';
  position: absolute;
  top: 0.875rem;
  right: 50%;
  width: 100%;
  height: 4px;
  background: var(--sky-200);
}

.stepper__step:first-child::before {
  display: none;
}

.stepper__step--done::before,
.stepper__step--current::before {
  background: var(--primary);
}

.stepper__dot {
  position: relative;
  display: grid;
  place-items: center;
  width: 1.75rem;
  height: 1.75rem;
  border-radius: 50%;
  border: 3px solid var(--sky-200);
  background: var(--white);
  color: var(--white);
}

.stepper__step--done .stepper__dot {
  background: var(--primary);
  border-color: var(--primary);
}

.stepper__step--current .stepper__dot {
  border-color: var(--primary);
  outline: 4px solid var(--sky-100);
}

.stepper__step--current {
  color: var(--ink);
  font-weight: 700;
}

.stepper__step--skipped .stepper__dot {
  border-style: dashed;
}

.stepper__step--skipped .stepper__label {
  font-style: italic;
}

.stepper__date {
  /* Date and time wrap onto two lines so neighbouring steps never touch. */
  max-width: 6rem;
  font-size: var(--text-sm);
  font-weight: 400;
  color: var(--ink-muted);
}

@media (max-width: 36rem) {
  .stepper {
    grid-template-columns: 1fr;
    gap: var(--space-2);
  }

  .stepper__step {
    flex-direction: row;
    flex-wrap: wrap;
    text-align: left;
  }

  .stepper__date {
    max-width: none;
  }

  .stepper__step::before {
    display: none;
  }
}
</style>
