<script setup lang="ts">
import {onMounted,ref} from 'vue'
import {withBase} from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const root='/examples/bibliography/history/'
const catalog=ref<any>(null), failure=ref('')
const status=(workload:string,version:string)=>catalog.value?.availability.find((row:any)=>row.workload===workload&&row.version===version)?.status??'missing'
onMounted(async()=>{
  try{const response=await fetch(withBase(root+'catalog.json'));if(!response.ok)throw new Error();catalog.value=await response.json()}
  catch{failure.value='The recorded history could not be loaded.'}
})
</script>
<template>
  <section class="history-gallery" aria-label="Measured Bibliography version history">
    <PluginTabs>
      <PluginTabsTab label="BenchmarkTools">
        <NormalizedMeasurements :source="root+'normalized.json'" :html="root+'normalized.html'" package-name="Bibliography" />
        <p>Windows · Julia 1.13.0 · one worker thread · 100 samples per release.</p>
      </PluginTabsTab>
      <PluginTabsTab label="Chairmarks">
        <NormalizedMeasurements source="/examples/bibliography/chairmarks-history/normalized.json" html="/examples/bibliography/chairmarks-history/normalized.html" package-name="Bibliography · Chairmarks" />
        <p>Linux · Julia 1.13.1 · one worker thread · 100 samples per release. GC is a fraction, rather than BenchmarkTools' GC time. These are independent collector sessions, not a collector-speed comparison.</p>
      </PluginTabsTab>
    </PluginTabs>
    <p>Nine tagged releases. Four curves overlay each metric's minimum divided by its own minimum across the campaign. A metric that is zero throughout is shown at 1 by convention. Dependencies follow each tag; this is not an isolated source-change comparison.</p>
    <p v-if="failure" role="alert">{{ failure }}</p>
    <details v-if="catalog" class="history-availability"><summary>Which workloads exist in each version?</summary>
      <div class="history-table-scroll"><table><thead><tr><th>Workload</th><th v-for="version in catalog.versions" :key="version">{{ version }}</th></tr></thead><tbody><tr v-for="workload in ['import_bibtex','export_bibtex','web_render','read_and_filter']" :key="workload"><th>{{ workload }}</th><td v-for="version in catalog.versions" :key="version" :class="'history-'+status(workload,version)">{{ status(workload,version)==='pass'?'Measured':status(workload,version)==='unavailable'?'Not defined':'Failed' }}</td></tr></tbody></table></div>
    </details>
    <a :href="withBase(root+'overview.json')" download>Download absolute measurements and source revisions</a>
  </section>
</template>
<style scoped>
.history-plot{height:auto;aspect-ratio:11/7;min-height:300px}
.history-controls{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;margin:1.2rem 0}.history-controls label{font-weight:600}.history-controls select{margin-left:.6rem;border:1px solid var(--vp-c-divider);border-radius:6px;background:var(--vp-c-bg);padding:.45rem .65rem;color:var(--vp-c-text-1);font:inherit}.history-controls span{font-size:.85rem;color:var(--vp-c-text-2)}summary{cursor:pointer;font-weight:600;padding:.65rem 0}.history-table-scroll{overflow-x:auto}.history-availability table{font-size:.8rem;white-space:nowrap}.history-pass{color:var(--vp-c-brand-1)}.history-unavailable{color:var(--vp-c-text-3)}.history-error,.history-missing{color:var(--vp-c-danger-1)}
</style>
