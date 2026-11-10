<script setup>
import { useId } from 'vue'

/**
 * Flag of a language, drawn in SVG: Windows does not render flag emoji
 * (it shows the two letters instead). Decorative: the language name is
 * always written next to it.
 */
defineProps({
  /** @type {import('vue').PropType<import('@/i18n').AppLocale>} */
  code: { type: String, required: true },
})

// The Union Jack clips its diagonals; ids must be unique per instance.
const clip = useId()
</script>

<template>
  <span class="flag" aria-hidden="true">
    <svg v-if="code === 'mg'" viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice">
      <rect width="3" height="2" fill="#fff" />
      <rect x="1" width="2" height="1" fill="#fc3d32" />
      <rect x="1" y="1" width="2" height="1" fill="#007e3a" />
    </svg>
    <svg v-else-if="code === 'fr'" viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice">
      <rect width="1" height="2" fill="#002654" />
      <rect x="1" width="1" height="2" fill="#fff" />
      <rect x="2" width="1" height="2" fill="#ce1126" />
    </svg>
    <svg v-else viewBox="0 0 60 30" preserveAspectRatio="xMidYMid slice">
      <clipPath :id="clip">
        <path d="M30,15 h30 v15 z v15 h-30 z h-30 v-15 z v-15 h30 z" />
      </clipPath>
      <rect width="60" height="30" fill="#012169" />
      <path d="M0,0 L60,30 M60,0 L0,30" stroke="#fff" stroke-width="6" />
      <path d="M0,0 L60,30 M60,0 L0,30" :clip-path="`url(#${clip})`" stroke="#c8102e" stroke-width="4" />
      <path d="M30,0 v30 M0,15 h60" stroke="#fff" stroke-width="10" />
      <path d="M30,0 v30 M0,15 h60" stroke="#c8102e" stroke-width="6" />
    </svg>
  </span>
</template>

<style scoped>
.flag {
  display: inline-flex;
  flex: none;
  width: 1.5rem;
  height: 1rem;
  border-radius: 3px;
  overflow: hidden;
  /* A light edge, so the white of a flag doesn't melt into the page. */
  box-shadow: 0 0 0 1px rgb(0 0 0 / 0.14);
}

.flag svg {
  width: 100%;
  height: 100%;
  display: block;
}
</style>
