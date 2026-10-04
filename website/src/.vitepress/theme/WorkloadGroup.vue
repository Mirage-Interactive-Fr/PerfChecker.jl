<script setup lang="ts">
import {computed, ref, useId} from 'vue'
import {withBase} from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const props=defineProps<{directory:string;group:any;observations:(id:string)=>string}>()
const selected=ref(0), uid=useId()
const operationNames:Record<string,string>={build:'Construction',lookup:'Lookup',drain:'Drain',traverse:'Traversal',connectivity:'Connectivity',prefixsum:'Prefix sums',http:'Request'}
const options=computed(()=>props.group.cases.flatMap((view:any)=>{
 const op=view.workload.split('_').at(-1)
 const name=operationNames[op]??(view.collector?.startsWith('chairmarks')?'Chairmarks':'BenchmarkTools')
 return [{view,label:props.group.cases.length>1?name:'All releases',json:view.json,svg:view.svg,patch:false},
 ...(view.patch_windows??[]).map((patch:any)=>({view,...patch,label:(props.group.cases.length>1?name+' · ':'')+patch.label,patch:true}))]
}))
const active=computed(()=>options.value[selected.value])
const explanation=computed(()=>{
 const op=active.value.view.workload.split('_').at(-1)
 if(op==='build')return 'Measure construction from the prepared input. The resulting container is checked after timing.'
 if(op==='lookup')return 'Build the container before timing, then look up the prepared keys. Construction is excluded.'
 if(op==='drain')return 'Start with a freshly built container and measure removal of its contents. Construction is excluded.'
 if(op==='traverse')return 'Start with a prepared container and measure traversal of its contents. Construction is excluded.'
 if(op==='connectivity')return 'Prepare the unions before timing, then measure the connectivity and group-count checks.'
 if(op==='prefixsum')return 'Prepare the tree before timing, then query the prefix sums.'
 return 'Measure this workload with '+(active.value.view.collector?.startsWith('chairmarks')?'Chairmarks':'BenchmarkTools')+'. Inspect a point to read the recorded value and its unit.'
})
function key(event:KeyboardEvent,index:number){
 const next=event.key==='Home'?0:event.key==='End'?options.value.length-1:event.key==='ArrowRight'?(index+1)%options.value.length:event.key==='ArrowLeft'?(index+options.value.length-1)%options.value.length:null
 if(next===null)return;event.preventDefault();selected.value=next
 ;(event.currentTarget as HTMLElement).parentElement?.querySelectorAll<HTMLButtonElement>('button')[next]?.focus()
}
</script>
<template>
 <div class="workload-group">
  <div v-if="options.length>1" role="tablist" :aria-label="group.name+' operations and release ranges'">
   <button v-for="(option,i) in options" :id="uid+'-tab-'+i" :key="option.json" role="tab" :aria-selected="selected===i" :aria-controls="uid+'-panel'" :tabindex="selected===i?0:-1" @click="selected=i" @keydown="key($event,i)">{{ option.label }}</button>
  </div>
  <div :id="uid+'-panel'" :role="options.length>1?'tabpanel':undefined" :aria-labelledby="options.length>1?uid+'-tab-'+selected:undefined">
   <h4>{{ active.view.workload.replaceAll('_',' ') }} · {{ active.view.collector?.startsWith('chairmarks')?'Chairmarks':'BenchmarkTools' }}</h4>
   <p>{{ explanation }}</p>
   <p v-if="active.patch">This view focuses on {{ active.label }}. Ratios keep the reference minimum from the complete history.</p>
   <NormalizedMeasurements compact :key="active.json" :source="directory+'/'+active.json" :figure="directory+'/'+active.svg" :package-name="active.view.package" />
   <p class="observation">{{ observations(active.view.id) }}{{ active.patch?' This observation refers to the full history.':'' }}</p>
   <a :href="withBase(directory+'/'+active.view.terminal)">Unicode plot of the complete history</a>
  </div>
 </div>
</template>
<style scoped>
[role=tablist]{display:flex;flex-wrap:wrap;gap:.4rem;border-bottom:1px solid var(--vp-c-divider)}
button{padding:.6rem .85rem;cursor:pointer;border-bottom:3px solid transparent}
button[aria-selected=true]{border-color:var(--vp-c-brand-1);color:var(--vp-c-brand-1);font-weight:600}
button:focus-visible{outline:2px solid var(--vp-c-brand-1);outline-offset:2px}
.observation{color:var(--vp-c-text-2)}
</style>
