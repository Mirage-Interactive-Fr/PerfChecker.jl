<script setup lang="ts">
import { withBase } from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
defineProps<{ source: string; figure: string; title: string; kind?: string; html?: string; timeUnit?: string }>()
</script>

<template>
  <NormalizedMeasurements v-if="kind === 'normalized_metrics'" :source="source"
    :figure="figure" :html="html" :package-name="title" />
  <section v-else class="recorded-export" :aria-label="title">
    <iframe v-if="html" :key="html" :src="withBase(html)" :title="title"
      loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads" />
    <a v-else :href="withBase(figure)"><img :src="withBase(figure)" :alt="title" loading="lazy" /></a>
    <p v-if="html"><a :href="withBase(html)">Open the same interactive export</a></p>
    <p v-else>Static export from the saved measurements. <a :href="withBase(figure)">Open the full-size figure</a>.</p>
    <a :href="withBase(source)" download>Download the serialized plot</a>
  </section>
</template>

<style scoped>
.recorded-export{min-width:0;border:1px solid var(--vp-c-divider);border-radius:8px;padding:.75rem;margin:.8rem 0}
iframe{display:block;width:100%;height:640px;border:0;background:white}
img{display:block;max-width:100%;height:auto;background:white}
p,a{overflow-wrap:anywhere}
@media(max-width:600px){iframe{height:700px}.recorded-export{padding:.35rem}}
</style>
