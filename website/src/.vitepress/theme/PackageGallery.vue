<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
import InteractiveRecordedPlot from './InteractiveRecordedPlot.vue'
const props = defineProps<{ packageName: string; directory: string }>()
const catalog = ref<any>(null), selected = ref(''), error = ref('')
const view = computed(()=>catalog.value?.views.find((v:any)=>v.id===selected.value))
const families = computed<string[]>(()=>[...new Set<string>(catalog.value?.views.map((v:any)=>v.kind)??[])])
const familyLoading = ref(false)
let familyRequest = 0, familyController: AbortController | undefined
function cancelFamilySelection(){ familyRequest++; familyController?.abort(); familyLoading.value=false }
async function selectFamily(event:Event){
  cancelFamilySelection()
  const request=familyRequest, kind=(event.target as HTMLSelectElement).value
  const candidates=catalog.value.views.filter((v:any)=>v.kind===kind&&v.html)
  if(!candidates.length)return
  if(kind!=='version_delta'){ selected.value=candidates[0].id; return }
  // Prefer a time comparison, then stop at the first model with an actual ratio.
  candidates.sort((a:any,b:any)=>Number(b.metric==='julia.wall.time')-Number(a.metric==='julia.wall.time'))
  familyController=new AbortController()
  const signal=familyController.signal
  familyLoading.value=true
  try{
    for(const candidate of candidates){
      const response=await fetch(withBase(props.directory+'/'+candidate.json),{signal})
      if(!response.ok)continue
      const record=await response.json()
      if(request!==familyRequest)return
      if(record.plot?.data?.some((row:any)=>Number.isFinite(row.relative_delta))){ selected.value=candidate.id; return }
    }
    if(request===familyRequest)selected.value=candidates[0].id
  }catch{ /* Keep the existing selection if a source cannot be loaded. */ }
  finally{ if(request===familyRequest)familyLoading.value=false }
}
onBeforeUnmount(cancelFamilySelection)
const environments = computed(()=>catalog.value?.resolved_environments?.filter((e:any)=>e.packages?.length)??[])
const dependency = (environment:any,name:string)=>environment.packages.find((p:any)=>p.name===name)?.version??'—'
onMounted(async()=>{
  try {
    const response=await fetch(withBase(props.directory+'/catalog.json'))
    if(!response.ok) throw new Error('The recorded catalogue could not be loaded.')
    catalog.value=await response.json()
    selected.value=catalog.value.views.find((v:any)=>v.html&&v.kind==='normalized_metrics')?.id??catalog.value.views.find((v:any)=>v.html&&v.kind==='cpu_flamegraph')?.id??catalog.value.views.find((v:any)=>v.html)?.id??catalog.value.views[0]?.id
  } catch(e) { error.value=String(e) }
})
</script>
<template>
  <section :aria-label="packageName+' recorded plots'">
    <template v-if="catalog">
      <label>Explore the recorded measurements
        <select v-model="selected" @change="cancelFamilySelection"><option v-for="v in catalog.views" :key="v.id" :value="v.id">{{ v.title }} · {{ v.label }}</option></select>
      </label>
      <label>Plot family
        <select :value="view?.kind" :disabled="familyLoading" @change="selectFamily"><option v-for="family in families" :key="family" :value="family">{{ family.replaceAll('_',' ') }}</option></select>
      </label>
      <p v-if="familyLoading" role="status">Finding a recorded comparison with a finite relative change…</p>
      <p>{{ catalog.runs.length }} completed checks · {{ catalog.versions.length }} tagged versions · Julia {{ catalog.runtime.version }}</p>
      <template v-if="view">
        <InteractiveRecordedPlot :key="view.id" :source="directory+'/'+view.json" :figure="directory+'/'+view.svg" :html="view.html ? directory+'/'+view.html : undefined" :title="view.title+' — '+view.label" :kind="view.kind" />
        <p><a :href="withBase(directory+'/'+view.json)" download>Plot data (JSON)</a> · <a :href="withBase(directory+'/'+view.terminal)">Unicode terminal plot</a> · <a :href="withBase(directory+'/'+view.svg)">Full-size SVG</a></p>
      </template>
      <details v-if="environments.length">
        <summary>Resolved dependency versions for this campaign</summary>
        <p>These versions come from the measurement workers' manifests. Oxygen's declared compatibilities determine which dependency versions Julia can resolve.</p>
        <table><thead><tr><th>Target release</th><th>DataStructures</th><th>HTTP</th><th>JSON</th></tr></thead>
          <tbody><tr v-for="environment in environments" :key="environment.version"><td>{{ environment.version }}</td><td>{{ dependency(environment,'DataStructures') }}</td><td>{{ dependency(environment,'HTTP') }}</td><td>{{ dependency(environment,'JSON') }}</td></tr></tbody>
        </table>
        <a :href="withBase(directory+'/catalog.json')" download>Download all resolved dependency versions and environment hashes</a>
      </details>
    </template>
    <p v-else>{{ error||'Loading the recorded plots…' }}</p>
  </section>
</template>
<style scoped>
select{display:block;width:100%;max-width:100%;margin:.6rem 0;padding:.6rem;border:1px solid var(--vp-c-divider);border-radius:6px;background:var(--vp-c-bg);color:var(--vp-c-text-1)}img{width:100%;background:white;border-radius:8px}label{font-weight:600}
</style>
