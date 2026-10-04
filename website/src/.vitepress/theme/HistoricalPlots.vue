<script setup lang="ts">
import {computed,onMounted,ref,watch} from 'vue'
import {withBase} from 'vitepress'
const root='/examples/bibliography/history/'
const catalog=ref<any>(null), selected=ref(''), evidence=ref<any>(null), failure=ref('')
const view=computed(()=>catalog.value?.views.find((item:any)=>item.id===selected.value))
const readingGuide:Record<string,string>={
  'normalized':'The four curves share one ratio axis. For each metric, divide the minimum recorded sample at each version by the smallest such value across versions. Each metric has its own best value at 1; these optima can belong to different versions. GC is zero throughout this run and is displayed at 1 as unchanged, by convention. Individual plots remain available in their original units.',
  'export-time':'Each point is the median elapsed time for exporting the same prepared bibliography. The vertical axis is in nanoseconds (1,000 ns = 1 µs). Input construction is outside this timing. Inspect the sample distribution before treating a small difference as a regression.',
  'export-memory':'Each point summarizes the Julia-managed bytes allocated while exporting. Bytes measure allocation activity, not the size of the BibTeX output or the process’s live RAM. A decrease can indicate fewer temporary objects; use an allocation profile to locate them.',
  'import-time':'Each point is the median elapsed time for importing the same BibTeX fixture. This workload includes reading its input, so the result reflects both I/O and parsing. The dependency revisions change with the tagged stack; the curve does not isolate a single source change.',
  'export-samples':'Each point is one recorded export timing. Multiple points per version reveal variation hidden by a median. The table below summarizes each group. A few slow observations may reflect GC or scheduling; this plot alone does not identify their cause.',
  'export-delta':'Each value compares the candidate median with the 0.1.0 median: (candidate − baseline) / baseline. Negative percentages mean less elapsed time for this workload. The comparison is diagnostic: no CI acceptance budget or correctness oracle was configured.'
}
const rows=computed(()=>{
  if(!evidence.value || ['version_delta','normalized_metrics'].includes(view.value?.kind)) return []
  const groups=new Map<string,number[]>()
  for(const point of evidence.value.plot.data){
    const values=groups.get(point.version)??[];values.push(point.value);groups.set(point.version,values)
  }
  return catalog.value.versions.filter((version:string)=>groups.has(version)).map((version:string)=>{
    const values=groups.get(version)!.sort((a,b)=>a-b), middle=Math.floor(values.length/2)
    return {version,value:values.length%2?values[middle]:(values[middle-1]+values[middle])/2}
  })
})
const format=(value:number)=>new Intl.NumberFormat('en',{maximumFractionDigits:3}).format(value)
const status=(workload:string,version:string)=>catalog.value?.availability.find((row:any)=>row.workload===workload&&row.version===version)?.status??'missing'
onMounted(async()=>{
  try{const response=await fetch(withBase(root+'catalog.json'));if(!response.ok)throw new Error();catalog.value=await response.json();selected.value=catalog.value.views[0].id}
  catch{failure.value='The recorded history could not be loaded.'}
})
watch(view,async(current,_,onCleanup)=>{
  if(!current)return
  let active=true;onCleanup(()=>{active=false});evidence.value=null
  try{const response=await fetch(withBase(root+current.evidence));if(!response.ok)throw new Error();const data=await response.json();if(active)evidence.value=data}
  catch{if(active)failure.value='The measured values could not be loaded.'}
})
</script>

<template>
  <section class="history-gallery" aria-label="Measured Bibliography version history">
    <p v-if="failure" role="alert">{{ failure }}</p>
    <template v-else-if="catalog">
      <div class="history-controls">
        <label>View <select v-model="selected" aria-label="Historical view"><option v-for="item in catalog.views" :key="item.id" :value="item.id">{{ item.label }}</option></select></label>
        <span>{{ catalog.versions.length }} tagged versions · {{ catalog.versions[0] }}–{{ catalog.versions.at(-1) }}</span>
      </div>
      <p class="history-reading-guide">{{ readingGuide[selected] }}</p>
      <figure v-if="view" class="doc-screenshot">
        <iframe :key="view.id" class="doc-interactive history-plot" :src="withBase(root+view.html)" :title="`Measured Bibliography history: ${view.label}`" sandbox="allow-scripts allow-same-origin" />
        <figcaption>Same BibTeX input across the tagged versions. Julia {{ catalog.runtime.version }} · Windows · {{ catalog.runtime.threads }} worker thread. Source and dependency revisions are retained with the measurements.</figcaption>
      </figure>
      <p v-if="view?.kind==='normalized_metrics'">Toggle a measurement to isolate its curve; hover or focus a point to inspect its raw value and ratio. Each curve has its own minimum at 1.</p>
      <p v-else-if="view?.kind!=='version_delta'">Move the point selector inside the graph to inspect a version or sample. Lower values mean less time or fewer allocated bytes.</p>
      <p v-else>Read the signed change and the baseline alongside the graph. A measured decrease does not by itself establish a CI pass.</p>
      <details v-if="evidence" class="history-values">
        <summary>Read the measured values</summary>
        <table v-if="view?.kind==='normalized_metrics'"><thead><tr><th>Metric</th><th>Version</th><th>Minimum sample</th><th>Ratio</th></tr></thead><tbody><tr v-for="row in evidence.plot.data" :key="row.metric+row.version"><td>{{ row.metric }}</td><th>{{ row.version }}</th><td>{{ format(row.value) }} {{ row.unit }}</td><td>{{ row.ratio===null?'unavailable':format(row.ratio) }} <span v-if="row.normalization_status==='both_zero'">(equal zeros)</span></td></tr></tbody></table>
        <table v-else-if="rows.length"><thead><tr><th>Version</th><th>Median ({{ evidence.plot.options.unit }})</th></tr></thead><tbody><tr v-for="row in rows" :key="row.version"><th>{{ row.version }}</th><td>{{ format(row.value) }}</td></tr></tbody></table>
        <table v-else><thead><tr><th>Baseline</th><th>Version</th><th>Change</th></tr></thead><tbody><tr v-for="row in evidence.plot.data" :key="row.candidate_version"><td>{{ row.baseline_version }}</td><td>{{ row.candidate_version }}</td><td>{{ row.relative_delta==null?'Not comparable':format(row.relative_delta*100)+'%' }}</td></tr></tbody></table>
      </details>
      <p v-if="view"><a :href="withBase(root+view.html)">Open this graph</a> · <a :href="withBase(root+view.evidence)" download>Download its measurements and source revisions</a></p>
      <details class="history-availability"><summary>Check which workloads exist in each version</summary>
        <div class="history-table-scroll"><table><thead><tr><th>Workload</th><th v-for="version in catalog.versions" :key="version">{{ version }}</th></tr></thead><tbody><tr v-for="workload in ['import_bibtex','export_bibtex','web_render','read_and_filter']" :key="workload"><th>{{ workload }}</th><td v-for="version in catalog.versions" :key="version" :class="`history-${status(workload,version)}`">{{ status(workload,version)==='pass'?'Measured':status(workload,version)==='unavailable'?'Not defined':'Failed' }}</td></tr></tbody></table></div>
      </details>
    </template>
    <p v-else>Loading the recorded version history…</p>
  </section>
</template>

<style scoped>
.history-plot{height:auto;aspect-ratio:11/7;min-height:300px}
.history-controls{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;margin:1.2rem 0}.history-controls label{font-weight:600}.history-controls select{margin-left:.6rem;border:1px solid var(--vp-c-divider);border-radius:6px;background:var(--vp-c-bg);padding:.45rem .65rem;color:var(--vp-c-text-1);font:inherit}.history-controls span{font-size:.85rem;color:var(--vp-c-text-2)}summary{cursor:pointer;font-weight:600;padding:.65rem 0}.history-table-scroll{overflow-x:auto}.history-availability table{font-size:.8rem;white-space:nowrap}.history-pass{color:var(--vp-c-brand-1)}.history-unavailable{color:var(--vp-c-text-3)}.history-error,.history-missing{color:var(--vp-c-danger-1)}
</style>
