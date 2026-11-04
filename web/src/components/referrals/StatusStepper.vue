<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ReferralStatus } from '@/api/types'
import { STATUS_ORDER } from '@/utils/triage'

/** The referral's life cycle as an ordered list (spec section 7). */
const props = defineProps<{ status: ReferralStatus }>()
const { t } = useI18n()
const currentIndex = computed(() => STATUS_ORDER.indexOf(props.status))

function state(index: number): 'done' | 'current' | 'todo' {
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
      :class="`stepper__step--${state(index)}`"
      :aria-current="state(index) === 'current' ? 'step' : undefined"
    >
      <span class="stepper__dot" aria-hidden="true">
        <svg v-if="state(index) === 'done'" viewBox="0 0 16 16" width="14" height="14">
          <path d="m3.5 8.5 3 3 6-7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
        </svg>
      </span>
      <span class="stepper__label">{{ t(`status.${step}`) }}</span>
      <span class="visually-hidden">({{ t(`referral.step${state(index) === 'done' ? 'Done' : state(index) === 'current' ? 'Current' : 'Todo'}`) }})</span>
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
  counter-reset: step;
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
  z-index: 0;
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
  z-index: 1;
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
  box-shadow: 0 0 0 4px var(--sky-100);
}

.stepper__step--current {
  color: var(--ink);
  font-weight: 700;
}

@media (max-width: 36rem) {
  .stepper {
    grid-template-columns: 1fr;
    gap: var(--space-2);
  }

  .stepper__step {
    flex-direction: row;
    text-align: left;
  }

  .stepper__step::before {
    display: none;
  }
}
</style>
