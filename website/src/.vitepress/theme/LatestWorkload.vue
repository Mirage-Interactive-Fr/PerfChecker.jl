<script setup lang="ts">
import {computed} from 'vue'
import {withBase} from 'vitepress'
import RecordedFigures from './RecordedFigures.vue'
const props=defineProps<{view:any;record:any;latestRows?:any[];latestSource?:string;profilesDirectory?:string;profileNote?:string;profileFeaturePrefix?:string}>()
const version=computed(()=>props.record?.plot?.options?.versions?.at(-1))
const rows=computed(()=>props.latestRows?.filter(row=>row.workload===props.view.workload)??
  props.record?.plot?.data?.filter((row:any)=>row.version===version.value)??[])
const collector=computed(()=>props.view.collector?.startsWith('chairmarks')?'Chairmarks':'BenchmarkTools')
const labels:Record<string,string>={'julia.wall.time':'Wall time','julia.gc.time':'GC time',
 'julia.gc.fraction':'GC fraction','julia.alloc.bytes':'Allocated bytes','julia.alloc.count':'Allocations'}
</script>
<template>
 <section class="latest-workload" aria-label="Latest version diagnostics">
  <p><strong>{{ version }}</strong> · recorded minima for this operation. A single release does not establish a change.</p>
  <div class="latest-values"><table><thead><tr><th>Collector</th><th>Metric</th><th>Minimum</th><th>Samples</th></tr></thead>
   <tbody><tr v-for="row in rows" :key="(row.collector??collector)+'/'+row.metric">
    <td>{{ row.collector??collector }}</td><td>{{ labels[row.metric]??row.metric }}</td><td>{{ row.value }} {{ row.unit }}</td><td>{{ row.samples }}</td>
   </tr></tbody></table></div>
  <p v-if="latestSource"><a :href="withBase(latestSource)" download>Download the separate latest-release collector sessions</a>. GC fraction retains its recorded definition; collector sessions are separate experiments.</p>
  <template v-if="profilesDirectory">
   <p v-if="profileNote">{{ profileNote }}</p>
   <RecordedFigures :directory="profilesDirectory" mode="latest" :feature-prefix="profileFeaturePrefix" />
  </template>
  <p v-else>No CPU, wall-time or allocation-stack diagnostic was recorded for this operation. The saved minima above do not identify its call paths.</p>
 </section>
</template>
<style scoped>
.latest-values{overflow-x:auto}table{font-size:.85rem}td,th{white-space:nowrap}
</style>
