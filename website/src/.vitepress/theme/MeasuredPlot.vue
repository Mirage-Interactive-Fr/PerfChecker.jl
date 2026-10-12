<script setup lang="ts">
import { withBase } from 'vitepress'
import InteractiveRecordedPlot from './InteractiveRecordedPlot.vue'
</script>

<template>
  <figure class="doc-screenshot">
    <InteractiveRecordedPlot source="/examples/bibliography/timing-evidence.json"
      html="/examples/bibliography/export-timing.html" kind="distribution"
      title="Interactive WGLMakie distribution of measured Bibliography export timings" />
    <figcaption>Bibliography 575ec81 · Julia 1.13.0 · Windows · 1 worker thread · 12 September 2026. Fifty measured samples exported with PerfCheckerMakie and WGLMakie.</figcaption>
  </figure>
  <p><a :href="withBase('/examples/bibliography/export-timing.html')">Open the plot on its own</a> or
    <a :href="withBase('/examples/bibliography/timing-evidence.json')" download>download the measured data and source revisions</a>.</p>
</template>
