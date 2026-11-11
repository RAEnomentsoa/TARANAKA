<script setup>
/**
 * Sidebar icons: 24×24 line drawings in the text colour, so they follow the
 * active and hover states. Decorative: the label is always written next to
 * them.
 */
defineProps({
  name: { type: String, required: true },
})

/**
 * @typedef {Object} Icon
 * @property {string[]} paths One per stroke.
 * @property {[number, number, number][]} [circles] cx, cy, r.
 */

/** @type {Record<string, Icon>} */
const ICONS = {
  // Arrow into a tray: incoming referrals.
  referrals: { paths: ['M12 3v11', 'm7.5 9.5 4.5 4.5 4.5-4.5', 'M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4'] },
  // Mother and child.
  beneficiaries: {
    circles: [[9, 7, 3], [17.5, 10, 2]],
    paths: ['M3.5 20v-1.5a5.5 5.5 0 0 1 11 0V20', 'M15.5 20v-1a3.5 3.5 0 0 1 5-3.2'],
  },
  // Two arrows crossing: versions to reconcile.
  conflicts: { paths: ['M4 7h12', 'm13 4 3 3-3 3', 'M20 17H8', 'm11 14-3 3 3 3'] },
  // Bar chart.
  stats: { paths: ['M4 20h16', 'M7 20v-6', 'M12 20V8', 'M17 20V10'] },
  // Person with a badge: community agents.
  agents: { circles: [[12, 7.5, 3.5]], paths: ['M5 20v-1a7 7 0 0 1 14 0v1', 'M12 14.5v2.5'] },
  // Group of people: every account.
  accounts: {
    circles: [[9, 8, 3]],
    paths: ['M3 20v-1a6 6 0 0 1 12 0v1', 'M16 5.2a3 3 0 0 1 0 5.6', 'M18 14.2a6 6 0 0 1 3 4.8v1'],
  },
  // Map pin: provinces, regions, centres.
  territory: {
    circles: [[12, 9.5, 2.2]],
    paths: ['M12 21s-7-6.1-7-11.5a7 7 0 0 1 14 0C19 14.9 12 21 12 21z'],
  },
  // Envelope: requests to review.
  'access-requests': { paths: ['M3 6h18v12H3z', 'm3 6 9 7 9-7'] },
}
</script>

<template>
  <svg
    class="nav-icon"
    viewBox="0 0 24 24"
    width="20"
    height="20"
    fill="none"
    stroke="currentColor"
    stroke-width="1.9"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <circle v-for="([cx, cy, r], index) in ICONS[name]?.circles ?? []" :key="`c${index}`" :cx="cx" :cy="cy" :r="r" />
    <path v-for="(d, index) in ICONS[name]?.paths ?? []" :key="`p${index}`" :d="d" />
  </svg>
</template>

<style scoped>
.nav-icon {
  flex: none;
}
</style>
