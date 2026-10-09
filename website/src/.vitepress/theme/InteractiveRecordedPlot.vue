<script setup lang="ts">
import {computed,ref,useId,watch} from 'vue'
import {withBase} from 'vitepress'
const props=defineProps<{source:string;figure:string;title:string;html?:string;kind?:string;timeUnit?:string}>()
const record=ref<any>(null),error=ref('')
const scrollHint=useId(),scrollId=useId(),positionId=useId()
const viewport=ref<HTMLDivElement|null>(null),graphPosition=ref(0),overflows=ref(false)
function updatePosition(){
 const element=viewport.value
 if(!element)return
 const maximum=Math.max(0,element.scrollWidth-element.clientWidth)
 overflows.value=maximum>1
 graphPosition.value=element.scrollLeft<=1?0:element.scrollLeft>=maximum-1?100:element.scrollLeft/maximum*100
}
function setPosition(event:Event){
 const element=viewport.value
 if(!element)return
 element.scrollLeft=(element.scrollWidth-element.clientWidth)*Number((event.target as HTMLInputElement).value)/100
 updatePosition()
}
function moveGraph(direction:number){
 const element=viewport.value
 if(!element)return
 element.scrollBy({left:direction*element.clientWidth*.85,behavior:'auto'})
 updatePosition()
}
watch(viewport,(element,_,cleanup)=>{
 if(!element)return
 const observer=new ResizeObserver(updatePosition)
 observer.observe(element)
 cleanup(()=>observer.disconnect())
 element.scrollLeft=0
 updatePosition()
},{flush:'post'})
watch(()=>props.html,()=>{
 if(viewport.value)viewport.value.scrollLeft=0
 graphPosition.value=0
 updatePosition()
},{flush:'post'})
const rows=computed<any[]>(()=>record.value?.plot?.data??record.value?.records??[])
const describe=(row:any)=>Object.entries(row).map(([key,value])=>`${key.replaceAll('_',' ')}: ${value===null?'unavailable':typeof value==='object'?JSON.stringify(value):value}`).join(' · ')
watch(()=>props.source,async(source,_,cleanup)=>{
 if(typeof window==='undefined')return
 const controller=new AbortController();cleanup(()=>controller.abort());record.value=null;error.value=''
 try{const response=await fetch(withBase(source),{signal:controller.signal});if(!response.ok)throw Error('Cannot load recorded measurements.');record.value=await response.json()}
 catch(e){if(!controller.signal.aborted)error.value=String(e)}
},{immediate:true})
</script>
<template>
 <section class="recorded-plot" :aria-label="title">
  <template v-if="html">
   <p :id="scrollHint" class="hint">On narrow screens, use Graph position or the Left and Right buttons to see the complete graph. You can also focus the graph area and use the arrow keys.</p>
   <div v-if="overflows" class="graph-position" role="group" :aria-label="title+' graph position'">
    <label :for="positionId">Graph position</label>
    <div class="position-controls">
     <button type="button" :aria-controls="scrollId" :disabled="graphPosition<=0" @click="moveGraph(-1)">Left</button>
     <input :id="positionId" type="range" min="0" max="100" step="1" :value="graphPosition" :aria-controls="scrollId" :aria-valuetext="Math.round(graphPosition)+'% from the left'" @input="setPosition" />
     <button type="button" :aria-controls="scrollId" :disabled="graphPosition>=100" @click="moveGraph(1)">Right</button>
    </div>
   </div>
   <div :id="scrollId" ref="viewport" class="native-scroll" role="region" :aria-label="title+' scrollable graph'" :aria-describedby="scrollHint" tabindex="0" @scroll="updatePosition">
    <iframe :key="html" :src="withBase(html)" :title="title" loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads" />
   </div>
   <p><a :href="withBase(html)">Open the interactive plot on its own</a></p>
   <details><summary>Static view</summary><img :src="withBase(figure)" :alt="title" loading="lazy" /></details>
  </template>
  <template v-else>
   <img :src="withBase(figure)" :alt="title" loading="lazy" />
   <p class="hint">This recorded plot is available as a static figure.</p>
  </template>
  <p v-if="error" role="alert">{{ error }} The figure remains available.</p>
  <details v-if="record"><summary>Recorded values ({{ rows.length }})</summary><div class="table-scroll"><table><thead><tr><th>Record</th><th>Saved fields</th></tr></thead><tbody><tr v-for="(row,i) in rows" :key="i"><td>{{ i+1 }}</td><td>{{ describe(row) }}</td></tr></tbody></table></div></details>
 </section>
</template>
<style scoped>
.recorded-plot{border:1px solid var(--vp-c-divider);border-radius:8px;padding:.8rem;margin:.8rem 0;min-width:0}
.native-scroll{max-width:100%;overflow-x:auto;overscroll-behavior-x:contain}
.native-scroll:focus-visible{outline:2px solid var(--vp-c-brand-1);outline-offset:3px}
.graph-position{margin:.6rem 0}.graph-position label{font-size:.85rem;font-weight:600}
.position-controls{display:flex;gap:.6rem;align-items:center}.position-controls input{flex:1;min-width:0;height:44px;accent-color:var(--vp-c-brand-1)}
.position-controls button{min-width:52px;min-height:44px;padding:.35rem .6rem;border:1px solid var(--vp-c-divider);border-radius:5px;background:var(--vp-c-bg);color:var(--vp-c-text-1)}
.position-controls button:disabled{opacity:.5}.position-controls button:focus-visible,.position-controls input:focus-visible{outline:2px solid var(--vp-c-brand-1);outline-offset:3px}
iframe{display:block;width:100%;min-width:1100px;height:650px;border:0;background:#f7f9fc}img{display:block;width:100%;height:auto}
.table-scroll{overflow:auto;max-height:420px}td{overflow-wrap:anywhere}.hint{font-size:.85rem}
</style>
