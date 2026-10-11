<script setup lang="ts">
import { withBase, useData } from 'vitepress'
import { computed } from 'vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const { site } = useData()
const plotsPage = computed(() => withBase(`/interfaces/visualization${site.value.cleanUrls ? '' : '.html'}`))
const medians = [
  { version: '0.1.0', time: 13.15, bytes: 4480, allocations: 94 },
  { version: '0.2.0', time: 12.65, bytes: 4784, allocations: 101 },
  { version: '0.2.5', time: 13, bytes: 8128, allocations: 91 },
  { version: '0.2.10', time: 16.9, bytes: 7264, allocations: 60 },
  { version: '0.2.15', time: 14.35, bytes: 7712, allocations: 71 },
  { version: '0.2.20', time: 15.6, bytes: 7712, allocations: 71 },
  { version: '0.3.0', time: 16.05, bytes: 8064, allocations: 74 },
  { version: '0.3.1', time: 16.1, bytes: 8064, allocations: 74 },
  { version: '0.4.0', time: 15.45, bytes: 8352, allocations: 73 },
]
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
    <details class="absolute-measurements"><summary>Read the absolute medians separately</summary>
    <p>These are medians per export, rather than the minima used in the plot above.
      GC time is zero in all 900 samples. Allocated bytes measure Julia allocation
      activity, not retained heap size or resident process memory.</p>
    <div class="measurement-table">
      <table><thead><tr><th scope="col">Release</th><th scope="col">Time (µs)</th><th scope="col">Allocated bytes (B)</th><th scope="col">Allocation count</th></tr></thead>
        <tbody><tr v-for="row in medians" :key="row.version"><th scope="row">{{ row.version }}</th><td>{{ row.time }}</td><td>{{ row.bytes }}</td><td>{{ row.allocations }}</td></tr></tbody>
      </table>
    </div>
    <p><a :href="withBase('/examples/bibliography/history/export-time.html')">Inspect the native timing medians</a> ·
      <a :href="withBase('/examples/bibliography/history/export-memory.html')">Inspect the native allocated-byte medians</a> ·
      <a :href="withBase('/examples/bibliography/history/export-samples.html')">Inspect all 900 timing samples</a></p>
    </details>
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
