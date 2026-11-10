<script setup>
import { useI18n } from 'vue-i18n'

/**
 * Skeleton of the content being loaded, in the shape of what will appear,
 * so the page doesn't jump when the data arrives. Screen readers hear the
 * label only; the blocks are hidden from them.
 */
defineProps({
  label: { type: String, default: undefined },
  /** 'lines' | 'list' | 'detail' | 'stats' */
  variant: { type: String, default: 'lines' },
  /** Number of rows (list) or lines (lines). */
  rows: { type: Number, default: 3 },
})
const { t } = useI18n()

// Varied widths read as text; equal widths read as a table.
const WIDTHS = ['92%', '78%', '85%', '64%', '88%', '70%']
</script>

<template>
  <div class="loading" :class="`loading--${variant}`" role="status" aria-live="polite">
    <span class="visually-hidden">{{ label ?? t('app.loading') }}</span>

    <ol v-if="variant === 'list'" class="sk-list" aria-hidden="true">
      <li v-for="n in rows" :key="n" class="sk-row">
        <span class="skeleton sk-pill" />
        <span class="sk-col">
          <span class="skeleton sk-line" style="width: 7rem" />
          <span class="skeleton sk-line sk-line--sm" style="width: 5rem" />
        </span>
        <span class="skeleton sk-line sk-row__reason" :style="{ width: WIDTHS[n % WIDTHS.length] }" />
        <span class="skeleton sk-line sk-row__meta" style="width: 4rem" />
        <span class="skeleton sk-pill sk-row__meta" />
        <span class="skeleton sk-button sk-row__meta" />
      </li>
    </ol>

    <div v-else-if="variant === 'detail'" class="sk-detail" aria-hidden="true">
      <div class="sk-head">
        <span class="skeleton sk-line sk-line--sm" style="width: 6rem" />
        <span class="skeleton sk-title" />
        <span class="sk-inline">
          <span class="skeleton sk-pill" />
          <span class="skeleton sk-line" style="width: 8rem" />
        </span>
      </div>
      <div class="sk-detail__grid">
        <div class="sk-detail__main">
          <div v-for="n in 2" :key="n" class="sk-panel">
            <span class="skeleton sk-line sk-line--lg" style="width: 10rem" />
            <span v-for="w in WIDTHS.slice(0, 3)" :key="w" class="skeleton sk-line" :style="{ width: w }" />
          </div>
        </div>
        <div class="sk-panel">
          <span class="skeleton sk-line sk-line--lg" style="width: 8rem" />
          <span class="skeleton sk-button sk-button--block" />
          <span class="skeleton sk-button sk-button--block" />
        </div>
      </div>
    </div>

    <div v-else-if="variant === 'stats'" class="sk-stats" aria-hidden="true">
      <div class="sk-tiles">
        <div v-for="n in 4" :key="n" class="sk-panel sk-tile">
          <span class="skeleton sk-line sk-line--sm" style="width: 60%" />
          <span class="skeleton sk-number" />
        </div>
      </div>
      <div class="sk-panel">
        <span class="skeleton sk-line sk-line--lg" style="width: 12rem" />
        <span v-for="(w, i) in WIDTHS.slice(0, 5)" :key="i" class="sk-bar">
          <span class="skeleton sk-line" style="width: 7rem" />
          <span class="skeleton sk-line" :style="{ width: w, maxWidth: '60%' }" />
        </span>
      </div>
    </div>

    <div v-else class="sk-lines" aria-hidden="true">
      <span v-for="n in rows" :key="n" class="skeleton sk-line" :style="{ width: WIDTHS[(n - 1) % WIDTHS.length] }" />
    </div>
  </div>
</template>

<style scoped>
.loading {
  padding: var(--space-2) 0;
}

.sk-line {
  height: 0.875rem;
}

.sk-line--sm {
  height: 0.75rem;
}

.sk-line--lg {
  height: 1.125rem;
  margin-bottom: var(--space-2);
}

.sk-title {
  width: 14rem;
  max-width: 80%;
  height: 2rem;
}

.sk-number {
  width: 4rem;
  height: 1.75rem;
}

.sk-pill {
  width: 5.5rem;
  height: 1.75rem;
  border-radius: var(--radius-pill);
}

.sk-button {
  width: 8rem;
  height: var(--target);
}

.sk-button--block {
  width: 100%;
}

.sk-lines,
.sk-col,
.sk-panel,
.sk-head {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.sk-inline {
  display: flex;
  gap: var(--space-3);
  align-items: center;
}

.sk-panel,
.sk-head {
  padding: var(--space-5);
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
}

/* Same columns as ReferralRow, so nothing moves when the rows arrive. */
.sk-list {
  list-style: none;
  margin: 0;
  padding: 0;
  background: var(--white);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  overflow: hidden;
}

.sk-row {
  display: grid;
  grid-template-columns: 9rem minmax(11rem, 1.2fr) minmax(10rem, 2fr) 7rem 9rem 11rem;
  align-items: center;
  gap: var(--space-3) var(--space-4);
  padding: var(--space-4);
}

.sk-row + .sk-row {
  border-top: 1px solid var(--line);
}

.sk-row .sk-button {
  justify-self: end;
}

.sk-detail {
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
}

.sk-detail__grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 20rem;
  gap: var(--space-5);
  align-items: start;
}

.sk-detail__main {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.sk-stats {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.sk-tiles {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
  gap: var(--space-3);
}

.sk-tile {
  padding: var(--space-4);
}

.sk-bar {
  display: flex;
  gap: var(--space-4);
  align-items: center;
}

@media (max-width: 70rem) {
  .sk-row {
    grid-template-columns: auto 1fr auto;
  }

  .sk-row__reason {
    grid-column: 1 / -1;
  }

  .sk-row__meta:not(.sk-button) {
    display: none;
  }

  .sk-detail__grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
