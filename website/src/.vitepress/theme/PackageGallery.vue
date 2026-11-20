<script setup lang="ts">
import { computed, onMounted, ref, watch, useId } from 'vue'
import { withBase } from 'vitepress'
import InteractiveRecordedPlot from './InteractiveRecordedPlot.vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
import {isLatestDiagnostic,isVersionComparison} from './recorded-view-policy.mjs'
const props = defineProps<{ packageName: string; directory: string }>()
const catalog = ref<any>(null), selected = ref(''), error = ref('')
const profileScope=ref('latest'),uid=useId()
const timing=computed(()=>catalog.value?.views.some((view:any)=>view.kind==='normalized_metrics'))
const hasProfileHistory=computed(()=>catalog.value?.views.some((view:any)=>view.documentation_scope==='history'))
const visibleViews = computed(()=>{
  const entries=catalog.value?.views??[]
  // Timing catalogues expose only the four-metric overlay. Profile catalogues
  // retain their own native families and never inherit a timing view.
  return entries.filter((view:any)=>view.documentation_visible&&(timing.value||view.documentation_scope===profileScope.value))
})
const view = computed(()=>visibleViews.value.find((v:any)=>v.id===selected.value))
const families = computed<string[]>(()=>[...new Set<string>(visibleViews.value.map((v:any)=>v.kind))])
function cancelFamilySelection() {}
watch(profileScope,()=>{selected.value=visibleViews.value[0]?.id??''})
function selectFamily(event:Event){
  const kind=(event.target as HTMLSelectElement).value
  const candidate=visibleViews.value.find((v:any)=>v.kind===kind&&v.html)
  if(candidate)selected.value=candidate.id
}
const environments = computed(()=>catalog.value?.resolved_environments?.filter((e:any)=>e.packages?.length)??[])
const dependency = (environment:any,name:string)=>environment.packages.find((p:any)=>p.name===name)?.version??'—'
onMounted(async()=>{
  try {
    const response=await fetch(withBase(props.directory+'/catalog.json'))
    if(!response.ok) throw new Error('The recorded catalogue could not be loaded.')
    const recorded=await response.json()
    const timing=recorded.views.some((view:any)=>view.kind==='normalized_metrics')
    await Promise.all(recorded.views.map(async(view:any)=>{
      if(timing&&view.kind!=='normalized_metrics')return
      const source=await fetch(withBase(props.directory+'/'+(view.plot??view.json)))
      if(!source.ok)throw Error('A recorded plot model could not be loaded.')
      const record=await source.json(),model=record.plot
      view.recorded_runtime=record.runtime??recorded.runtime
      view.documentation_visible=timing?isVersionComparison(model):
        (isLatestDiagnostic(model)||isVersionComparison(model))
      view.documentation_scope=isLatestDiagnostic(model)?'latest':isVersionComparison(model)?'history':undefined
    }))
    catalog.value=recorded
    selected.value=visibleViews.value.find((v:any)=>v.html&&v.kind==='normalized_metrics')?.id??visibleViews.value.find((v:any)=>v.html&&v.kind==='cpu_flamegraph')?.id??visibleViews.value.find((v:any)=>v.html)?.id??visibleViews.value[0]?.id
  } catch(e) { error.value=String(e) }
})
</script>
<template>
  <section :aria-label="packageName+' recorded plots'">
    <template v-if="catalog">
      <div v-if="!timing" role="tablist" :aria-label="packageName+' profile evidence'">
        <button v-if="hasProfileHistory" :id="uid+'-history'" role="tab" :aria-selected="profileScope==='history'" :aria-controls="uid+'-profiles'" @click="profileScope='history'">History</button>
        <button :id="uid+'-latest'" role="tab" :aria-selected="profileScope==='latest'" :aria-controls="uid+'-profiles'" @click="profileScope='latest'">Latest version</button>
      </div>
      <div :id="uid+'-profiles'" :role="!timing?'tabpanel':undefined" :aria-labelledby="!timing?uid+'-'+profileScope:undefined">
      <label>Explore the recorded measurements
        <select v-model="selected" @change="cancelFamilySelection"><option v-for="v in visibleViews" :key="v.id" :value="v.id">{{ v.title }} · {{ v.label }}</option></select>
      </label>
      <label v-if="families.length>1">Plot family
        <select :value="view?.kind" @change="selectFamily"><option v-for="family in families" :key="family" :value="family">{{ family.replaceAll('_',' ') }}</option></select>
      </label>
      <p>{{ catalog.runs.length }} completed checks · {{ catalog.versions.length }} tagged versions · selected capture: Julia {{ view?.recorded_runtime?.version??catalog.runtime.version }}</p>
      <template v-if="view">
        <NormalizedMeasurements v-if="view.kind==='normalized_metrics'" :key="view.id" :source="directory+'/'+view.json" :html="directory+'/'+view.html" :package-name="packageName" />
        <template v-else>
          <InteractiveRecordedPlot :key="view.id" :source="directory+'/'+view.json" :figure="view.svg ? directory+'/'+view.svg : undefined" :html="view.html ? directory+'/'+view.html : undefined" :title="view.title+' — '+view.label" :kind="view.kind" />
          <p><a :href="withBase(directory+'/'+view.json)" download>Plot data (JSON)</a><template v-if="view.terminal"> · <a :href="withBase(directory+'/'+view.terminal)">Unicode terminal plot</a></template><template v-if="view.svg"> · <a :href="withBase(directory+'/'+view.svg)">Full-size SVG</a></template><template v-if="view.evidence"> · <a :href="withBase(directory+'/'+view.evidence)" download>Native capture and provenance</a></template></p>
        </template>
      </template>
      <details v-if="environments.length">
        <summary>Resolved dependency versions for this campaign</summary>
        <p>These versions come from the measurement workers' manifests. Oxygen's declared compatibilities determine which dependency versions Julia can resolve.</p>
        <table><thead><tr><th>Target release</th><th>DataStructures</th><th>HTTP</th><th>JSON</th></tr></thead>
          <tbody><tr v-for="environment in environments" :key="environment.version"><td>{{ environment.version }}</td><td>{{ dependency(environment,'DataStructures') }}</td><td>{{ dependency(environment,'HTTP') }}</td><td>{{ dependency(environment,'JSON') }}</td></tr></tbody>
        </table>
        <a :href="withBase(directory+'/catalog.json')" download>Download all resolved dependency versions and environment hashes</a>
      </details>
      </div>
    </template>
    <p v-else>{{ error||'Loading the recorded plots…' }}</p>
  </section>
</template>
<style scoped>
select{display:block;width:100%;max-width:100%;margin:.6rem 0;padding:.6rem;border:1px solid var(--vp-c-divider);border-radius:6px;background:var(--vp-c-bg);color:var(--vp-c-text-1)}img{width:100%;background:white;border-radius:8px}label{font-weight:600}
</style>
