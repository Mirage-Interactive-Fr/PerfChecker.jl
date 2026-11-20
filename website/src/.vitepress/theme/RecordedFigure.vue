<script setup lang="ts">
import { withBase } from 'vitepress'
import { computed, ref, useId } from 'vue'
import InteractiveRecordedPlot from './InteractiveRecordedPlot.vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const props=defineProps<{ directory: string; view: any }>()
const operation=ref(''), collector=ref('BenchmarkTools')
const uid=useId()
const operations=computed<string[]>(()=>[...new Set<string>((props.view.normalized_views??[]).map((v:any)=>v.operation))])
const activeOperation=computed(()=>operations.value.includes(operation.value)?operation.value:operations.value[0])
const collectors=computed<string[]>(()=>[...new Set<string>((props.view.normalized_views??[]).filter((v:any)=>v.operation===activeOperation.value).map((v:any)=>v.collector))])
const active=computed(()=>(props.view.normalized_views??[]).find((v:any)=>v.operation===activeOperation.value&&v.collector===collector.value)??(props.view.normalized_views??[]).find((v:any)=>v.operation===activeOperation.value))
function collectorKey(event:KeyboardEvent,index:number){
  const next=event.key==='Home'?0:event.key==='End'?collectors.value.length-1:event.key==='ArrowRight'?(index+1)%collectors.value.length:event.key==='ArrowLeft'?(index+collectors.value.length-1)%collectors.value.length:null
  if(next===null)return
  event.preventDefault();collector.value=collectors.value[next]
  ;(event.currentTarget as HTMLElement).parentElement?.querySelectorAll<HTMLButtonElement>('button')[next]?.focus()
}
</script>
<template>
  <figure>
    <h4>{{ view.title }} · {{ view.label }}</h4>
    <template v-if="view.normalized_views?.length">
      <label>Operation <select :value="activeOperation" @change="operation=($event.target as HTMLSelectElement).value"><option v-for="item in operations" :key="item" :value="item">{{ item }}</option></select></label>
      <div role="tablist" aria-label="Timing collector"><button v-for="(item,index) in collectors" :id="uid+'-tab-'+index" :key="item" role="tab" :aria-selected="active?.collector===item" :aria-controls="uid+'-panel'" :tabindex="active?.collector===item?0:-1" @click="collector=item" @keydown="collectorKey($event,index)">{{ item }}</button></div>
      <div v-if="active" :id="uid+'-panel'" role="tabpanel" :aria-labelledby="uid+'-tab-'+collectors.indexOf(active.collector)">
        <NormalizedMeasurements :key="active.id" :source="directory+'/'+active.plot" :html="directory+'/'+active.html" :package-name="view.title+' · '+active.collector" />
      </div>
      <figcaption>One release, four recorded minima. Every metric uses its own reference; GC share retains its original collector definition. This is not a collector speed comparison. <a :href="withBase(directory+'/'+view.json)" download>Download the original measurements</a></figcaption>
    </template>
    <template v-else>
      <InteractiveRecordedPlot :source="directory+'/'+(view.plot ?? view.json)" :figure="view.svg ? directory+'/'+view.svg : undefined" :html="view.html ? directory+'/'+view.html : undefined" :title="view.title+' '+view.label" :kind="view.kind" />
      <figcaption><span v-if="view.capture_note">{{ view.capture_note }} </span><a :href="withBase(directory+'/'+view.json)">Recorded data</a><template v-if="view.terminal"> · <a :href="withBase(directory+'/'+view.terminal)">Unicode view</a></template><template v-if="view.svg"> · <a :href="withBase(directory+'/'+view.svg)">Full-size figure</a></template><template v-if="view.evidence"> · <a :href="withBase(directory+'/'+view.evidence)" download>Native capture and provenance</a></template></figcaption>
      <details v-if="view.capture_conditions"><summary>Capture conditions</summary><dl><template v-for="(value,label) in view.capture_conditions" :key="label"><dt>{{ label }}</dt><dd>{{ value }}</dd></template></dl></details>
    </template>
  </figure>
</template>
<style scoped>figure{margin:1rem 0 2rem}img{width:100%;background:white;border-radius:8px}</style>
