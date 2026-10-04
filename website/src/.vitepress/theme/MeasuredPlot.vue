<script setup lang="ts">
import { withBase } from 'vitepress'
</script>

<template>
  <figure class="doc-screenshot">
    <iframe class="doc-interactive"
      :src="withBase('/examples/bibliography/export-timing.html')"
      title="Interactive WGLMakie distribution of measured Bibliography export timings"
      loading="lazy" sandbox="allow-scripts allow-same-origin" />
    <figcaption>Bibliography 575ec81 · Julia 1.13.0 · Windows · 1 worker thread · 12 September 2026. Fifty measured samples exported with PerfCheckerMakie and WGLMakie.</figcaption>
  </figure>
  <p><a :href="withBase('/examples/bibliography/export-timing.html')">Open the plot on its own</a> or
    <a :href="withBase('/examples/bibliography/timing-evidence.json')" download>download the measured data and source revisions</a>.</p>
</template>
