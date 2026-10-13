<script setup lang="ts">
import { withBase } from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
</script>

<template>
  <figure class="doc-screenshot">
    <NormalizedMeasurements source="/examples/bibliography/export-normalized.json"
      html="/examples/bibliography/export-normalized.html" package-name="Bibliography · one source revision" />
    <figcaption>Bibliography 575ec81 · Julia 1.13.0 · Windows · one worker thread · fifty samples. Four minima share one ratio axis; this single revision cannot establish a version comparison.</figcaption>
  </figure>
  <p><a :href="withBase('/examples/bibliography/export-normalized.html')">Open the plot on its own</a> or
    <a :href="withBase('/examples/bibliography/timing-evidence.json')" download>download the measured data and source revisions</a>.</p>
</template>
