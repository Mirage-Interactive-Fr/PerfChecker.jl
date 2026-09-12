<script setup lang="ts">
import { withBase } from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const figures = [
  { id: 'time', alt: 'Median export time across nine Bibliography tags, from 13.15 to 15.45 microseconds.' },
  { id: 'gc', alt: 'GC time is zero in every one of the 900 recorded export samples.' },
  { id: 'memory', alt: 'Julia allocated bytes per export across nine tags, from 4480 to 8352 bytes.' },
  { id: 'allocations', alt: 'Allocation counts across nine tags: 94, 101, 91, 60, 71, 71, 74, 74 and 73.' },
]
</script>

<template>
  <section class="home-measurements" aria-labelledby="home-measurements-title">
    <div class="measurement-eyebrow">A recorded Bibliography experiment</div>
    <h2 id="home-measurements-title">One workload, four overlaid measurements</h2>
    <p>Export the same bibliography across nine tagged versions. Compare all four
      measurements on one axis, each normalized by its own minimum.</p>
    <NormalizedMeasurements />
    <details class="absolute-measurements"><summary>Read the absolute measurements separately</summary>
    <div class="measurement-grid">
      <a v-for="figure in figures" :key="figure.id" class="measurement-panel"
         :href="withBase(`/examples/bibliography/figures/overview-${figure.id}.svg`)"
         :aria-label="`Open full-size plot: ${figure.alt}`">
        <img :src="withBase(`/examples/bibliography/figures/overview-${figure.id}.svg`)"
             :alt="figure.alt" width="550" height="360" loading="lazy" />
      </a>
    </div>
    </details>
    <p class="measurement-context">100 samples per version · Windows · Julia 1.13.0 · one worker thread.
      GC time is zero in these samples; that does not mean the package never triggers GC.
      Allocations measure Julia allocation activity, not retained process memory.
      The dependency stack changes with each tag; no correctness oracle or regression budget was configured.</p>
    <div class="measurement-links">
      <a :href="withBase('/interfaces/visualization')">Explore the interactive plots →</a>
      <a :href="withBase('/examples/bibliography/history/overview.json')" download>Download measurements and revisions</a>
    </div>
  </section>
</template>

<style scoped>
.home-measurements { margin: 2.5rem 0; }
.measurement-eyebrow { color: var(--vp-c-brand-1); font-size: .8rem; font-weight: 650; letter-spacing: .04em; }
.home-measurements h2 { border: 0; margin: .5rem 0 1rem; padding: 0; font-size: 1.85rem; line-height: 1.25; }
.measurement-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; margin: 1.4rem 0; }
.measurement-panel { border: 1px solid var(--vp-c-divider); border-radius: 14px; overflow: hidden; background: white; padding: .5rem; }
.measurement-panel img { display: block; width: 100%; height: auto; }
.measurement-panel:hover { border-color: var(--vp-c-brand-1); }
.measurement-panel:focus-visible { outline: 3px solid var(--vp-c-brand-1); outline-offset: 3px; }
.measurement-context { color: var(--vp-c-text-2); font-size: .85rem; line-height: 1.65; }
.measurement-links { display: flex; flex-wrap: wrap; gap: .7rem 1.6rem; font-size: .9rem; }
@media (max-width: 639px) { .measurement-grid { grid-template-columns: minmax(0, 1fr); } }
</style>
