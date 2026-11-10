<script setup>
import logo from '@/assets/logo_v1.png'

/*
 * Small brand mark (top bar, request page). logo_v1 is a detailed
 * illustration with its own wordmark: at 40px only the family drawing stays
 * legible, so the mark shows that part and the wordmark is left to the text
 * beside it. The full logo is on the login page.
 */
</script>

<template>
  <span class="brand-mark" aria-hidden="true">
    <img class="brand-mark__img" :src="logo" width="500" height="500" alt="" />
  </span>
</template>

<style scoped>
.brand-mark {
  position: relative;
  display: inline-block;
  flex-shrink: 0;
  width: 2.5rem;
  height: 2.5rem;
  overflow: hidden;
  border-radius: 50%;
  background: var(--white);
  box-shadow: 0 0 0 1px var(--line);
}

/* 150 %: the 2.5rem window shows the drawing (top two thirds, centred). */
.brand-mark__img {
  position: absolute;
  top: 0;
  left: -0.625rem;
  width: 3.75rem;
  height: 3.75rem;
  max-width: none;
}
</style>
