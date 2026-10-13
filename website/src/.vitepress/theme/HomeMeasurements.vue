<script setup lang="ts">
import { withBase, useData } from 'vitepress'
import { computed } from 'vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const { site } = useData()
const plotsPage = computed(() => withBase(`/interfaces/visualization${site.value.cleanUrls ? '' : '.html'}`))
</script>

<template>
  <section class="home-measurements" aria-labelledby="home-measurements-title">
    <div class="measurement-eyebrow">Example</div>
    <h2 id="home-measurements-title">Bibliography export across nine releases</h2>
    <p>These curves show the time, GC time, allocated bytes and allocation count
      for exporting the same bibliography. For each metric, the minimum sample
      at each release is divided by the smallest minimum across the nine releases.
      Each curve has its own best value at 1. GC is zero throughout this campaign
      and is shown at 1 as unchanged, by convention.</p>
    <NormalizedMeasurements />
    <p class="measurement-context">100 samples per version · Windows · Julia 1.13.0 · one worker thread.
      The dependency versions follow each tag. None of these samples triggered GC.
      The run collected timings and allocations without a correctness check or CI regression limit.</p>
    <div class="measurement-links">
      <a :href="plotsPage">Explore the interactive plots →</a>
      <a :href="withBase('/examples/bibliography/history/overview.json')" download>Download measurements and revisions</a>
    </div>
  </section>
</template>

<style scoped>
.home-measurements { margin: 2.5rem 0; }
.measurement-eyebrow { color: var(--vp-c-brand-1); font-size: .8rem; font-weight: 650; letter-spacing: .04em; }
.home-measurements h2 { border: 0; margin: .5rem 0 1rem; padding: 0; font-size: 1.85rem; line-height: 1.25; }
.measurement-table { overflow-x: auto; }
.measurement-context { color: var(--vp-c-text-2); font-size: .85rem; line-height: 1.65; }
.measurement-links { display: flex; flex-wrap: wrap; gap: .7rem 1.6rem; font-size: .9rem; }
</style>
