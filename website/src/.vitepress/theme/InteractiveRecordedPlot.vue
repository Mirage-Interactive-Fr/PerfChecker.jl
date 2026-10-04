<script setup lang="ts">
import {computed,ref,watch} from 'vue'
import {withBase} from 'vitepress'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const props=defineProps<{source:string;figure:string;title:string;kind?:string;timeUnit?:string}>()
const record=ref<any>(null),error=ref(''),selected=ref<any>(null),zoom=ref(1),metric=ref('')
const palette=['#087e8b','#b46a22','#7655ad','#3372b7','#b34566','#578233','#795548']
const plot=computed(()=>record.value?.plot)
const kind=computed(()=>plot.value?.kind??props.kind??'collector_comparison')
const allRows=computed<any[]>(()=>plot.value?.data??record.value?.records??[])
const metrics=computed<string[]>(()=>[...new Set(allRows.value.map(r=>r.metric).filter(Boolean))])
const rows=computed(()=>kind.value==='collector_comparison'?allRows.value.filter(r=>r.metric===metric.value):allRows.value)
const flame=computed(()=>kind.value.endsWith('flamegraph'))
const pie=computed(()=>kind.value==='allocation_pie')
const heatmap=computed(()=>kind.value==='allocation_heatmap')
const heatLabels=computed(()=>[...new Set(rows.value.map(r=>r.label))])
const bars=computed(()=>kind.value.startsWith('allocation_')||kind.value==='collector_comparison')
const delta=computed(()=>kind.value==='version_delta')
const tradeoff=computed(()=>kind.value==='time_allocation_tradeoff')
const unit=computed(()=>delta.value?'%':tradeoff.value?(props.timeUnit??'recorded time units'):plot.value?.options?.unit??rows.value[0]?.unit??'')
const label=(r:any)=>r.label??r.file??(r.workload?r.workload+' · '+r.collector:r.candidate_version?`${r.baseline_version} → ${r.candidate_version}`:r.version??'')
const value=(r:any)=>delta.value?(r.relative_delta==null?null:r.relative_delta*100):tradeoff.value?r.time:r.bytes??r.value
const visible=computed(()=>rows.value.filter(r=>Number.isFinite(value(r))))
const versions=computed(()=>[...new Set(rows.value.map(r=>r.version??r.candidate_version))])
const extent=computed(()=>{const vs=visible.value.map(value);return [Math.min(0,...vs),Math.max(1,...vs)]})
const y=(n:number)=>300-(n-extent.value[0])/(extent.value[1]-extent.value[0])*250
const x=(r:any,i:number)=>tradeoff.value?70+r.bytes/Math.max(1,...rows.value.map(r=>r.bytes))*650:70+(versions.value.indexOf(r.version??r.candidate_version)+.5)*650/Math.max(1,versions.value.length)+(kind.value==='distribution'?((i*17)%13-6)*1.2:0)
const color=(r:any,i:number)=>palette[(kind.value==='collector_comparison'?(r.collector==='Chairmarks'?1:0):i)%palette.length]
const describe=(r:any)=>Object.entries(r).map(([key,value])=>`${key.replaceAll('_',' ')}: ${value===null?'unavailable':Array.isArray(value)?value.map(v=>typeof v==='object'?JSON.stringify(v):v).join(' → '):typeof value==='object'?JSON.stringify(value):value}`).join(' · ')
const number=(value:number)=>Number(value.toPrecision(6)).toLocaleString('en-US',{maximumSignificantDigits:6})
const reading=(r:any)=>[
 label(r),
 tradeoff.value?`${number(r.time)} ${unit.value}; ${number(r.bytes)} allocated bytes`:value(r)===null?'relative change unavailable':`${number(value(r))} ${unit.value}`,
 r.percentage!=null?`${number(r.percentage)}% of captured weight`:'',
 r.version?`version ${r.version}`:'',
 r.path?.length?'Call path: '+r.path.join(' → '):'',
 r.samples?`${r.samples} samples`:'',
 r.aggregation??r.statistic??''
].filter(Boolean).join(' · ')
const barHeight=computed(()=>Math.max(220,rows.value.length*26+40))
const depth=computed(()=>Math.max(1,...rows.value.map(r=>r.depth??1)))
const flameHeight=computed(()=>depth.value*24+40)
const wedges=computed(()=>{let angle=-Math.PI/2;const total=rows.value.reduce((n,r)=>n+r.bytes,0);return rows.value.map((r,i)=>{
 const end=angle+(total?r.bytes/total:0)*Math.PI*2
 const path=`M 190 175 L ${190+140*Math.cos(angle)} ${175+140*Math.sin(angle)} A 140 140 0 ${end-angle>Math.PI?1:0} 1 ${190+140*Math.cos(end)} ${175+140*Math.sin(end)} Z`
 angle=end;return {r,path,color:color(r,i)}
})})
watch(()=>props.source,async(source,_,cleanup)=>{
 if(typeof window==='undefined')return
 const c=new AbortController();cleanup(()=>c.abort());record.value=null;selected.value=null;zoom.value=1;error.value=''
 try{const response=await fetch(withBase(source),{signal:c.signal});if(!response.ok)throw Error('Cannot load recorded measurements.');record.value=await response.json();metric.value=metrics.value[0]??''}
 catch(e){if(!c.signal.aborted)error.value=String(e)}
},{immediate:true})
</script>
<template>
 <NormalizedMeasurements v-if="kind==='normalized_metrics'" :source="source" :figure="figure" :package-name="plot?.options?.package??title" />
 <section v-else class="interactive-recorded" :aria-label="title">
  <p v-if="error" role="alert">{{ error }}</p>
  <template v-if="record">
   <div class="controls">
    <label v-if="kind==='collector_comparison'">Measurement <select v-model="metric" @change="selected=null"><option v-for="m in metrics" :key="m">{{ m }}</option></select></label>
    <button type="button" @click="zoom=Math.min(4,zoom+.5)">Zoom in</button>
    <button type="button" @click="zoom=Math.max(1,zoom-.5)">Zoom out</button>
    <button type="button" @click="zoom=1">Fit graph</button>
   </div>
   <p class="hint">Hover, click or focus a mark to read its values. Zoom enlarges the figure; scroll to inspect it.</p>
   <div class="plot-scroll">
    <svg v-if="flame" :viewBox="`0 0 760 ${flameHeight}`" :style="{width:zoom*100+'%'}" role="img" :aria-label="title">
     <text x="20" y="16">{{ plot.options.value_label }} · width includes child calls</text>
     <g v-for="(r,i) in rows" :key="i">
      <rect class="mark" :x="20+r.x0*720" :y="25+(depth-r.depth)*24" :width="Math.max(.8,(r.x1-r.x0)*720)" height="23" :fill="color(r,i)" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r"><title>{{ describe(r) }}</title></rect>
      <text v-if="(r.x1-r.x0)*720>100" :x="24+r.x0*720" :y="41+(depth-r.depth)*24" class="frame-label">{{ r.label.slice(0,Math.floor((r.x1-r.x0)*90)) }}</text>
     </g>
    </svg>
    <svg v-else-if="pie" viewBox="0 0 760 355" :style="{width:zoom*100+'%'}" role="img" :aria-label="title">
     <g v-for="({r,path,color},i) in wedges" :key="i">
      <path v-if="wedges.length>1" class="mark" :d="path" :fill="color" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r"><title>{{ describe(r) }}</title></path>
      <circle v-else class="mark" cx="190" cy="175" r="140" :fill="color" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r" />
      <text x="355" :y="30+i*26">{{ r.percentage?.toFixed(1) }}% · {{ label(r).slice(0,49) }}</text>
     </g>
    </svg>
    <svg v-else-if="heatmap" :viewBox="`0 0 760 ${heatLabels.length*26+70}`" :style="{width:zoom*100+'%'}" role="img" :aria-label="title">
     <text x="315" y="16">Allocated bytes · darker cells indicate more bytes</text>
     <text v-for="(name,i) in heatLabels" :key="name" x="302" :y="40+i*26" text-anchor="end">{{ name.slice(-43) }}</text>
     <rect v-for="(r,i) in rows" :key="i" class="mark" :x="315+versions.indexOf(r.version)*410/versions.length" :y="24+heatLabels.indexOf(r.label)*26" :width="410/versions.length-1" height="25" :fill="`rgba(8,126,139,${.12+.88*r.bytes/extent[1]})`" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r"><title>{{ describe(r) }}</title></rect>
     <text v-for="(v,i) in versions" :key="v" :x="315+(i+.5)*410/versions.length" :y="heatLabels.length*26+44" text-anchor="middle">{{ v }}</text>
    </svg>
    <svg v-else-if="bars" :viewBox="`0 0 760 ${barHeight}`" :style="{width:zoom*100+'%'}" role="img" :aria-label="title">
     <text x="315" y="16">{{ unit }} · linear scale · {{ extent[1].toPrecision(4) }} at right edge</text>
     <g v-for="(r,i) in rows" :key="i">
      <text x="302" :y="39+i*26" text-anchor="end">{{ label(r).slice(-43) }}</text>
      <rect class="mark" x="315" :y="24+i*26" :width="Math.max(1,value(r)/extent[1]*410)" height="20" :fill="color(r,i)" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r"><title>{{ describe(r) }}</title></rect>
     </g>
    </svg>
    <svg v-else viewBox="0 0 760 410" :style="{width:zoom*100+'%'}" role="img" :aria-label="title">
     <g v-for="n in [extent[0],(extent[0]+extent[1])/2,extent[1]]" :key="n"><line x1="65" x2="730" :y1="y(n)" :y2="y(n)" class="grid"/><text x="60" :y="y(n)+4" text-anchor="end">{{ n.toPrecision(3) }}</text></g>
     <text x="70" y="20">{{ delta?'Relative change':plot?.options?.metric??(tradeoff?'Elapsed time':'Value') }} ({{ unit }})</text>
     <polyline v-if="kind==='version_series'" :points="visible.map((r,i)=>`${x(r,i)},${y(value(r))}`).join(' ')" fill="none" stroke="#087e8b" stroke-width="2" />
     <circle v-for="(r,i) in visible" :key="i" class="mark" :cx="x(r,i)" :cy="y(value(r))" r="5" :fill="color(r,versions.indexOf(r.version??r.candidate_version))" tabindex="0" :aria-label="describe(r)" @mouseenter="selected=r" @focus="selected=r" @click="selected=r"><title>{{ describe(r) }}</title></circle>
     <template v-if="!tradeoff"><text v-for="(v,i) in versions" :key="v" :transform="`translate(${70+(i+.5)*650/versions.length},322) rotate(-45)`" text-anchor="end">{{ v }}</text></template>
     <template v-else><text x="70" y="320">0</text><text x="720" y="320" text-anchor="end">{{ Math.max(...rows.map(r=>r.bytes)) }}</text></template>
     <text x="395" y="398" text-anchor="middle">{{ tradeoff?'Allocated bytes (By)':delta?'Candidate version (baseline in point details)':'Package version' }}</text>
    </svg>
   </div>
   <p v-if="delta&&visible.length<rows.length">{{ rows.length-visible.length }} relative changes are undefined. Their original values remain in the table below.</p>
   <p class="reading" aria-live="polite">{{ selected?reading(selected):'Select a mark to inspect the saved observation.' }}</p>
   <details><summary>Recorded values ({{ rows.length }})</summary><div class="table-scroll"><table><thead><tr><th>Record</th><th>Saved fields</th></tr></thead><tbody><tr v-for="(r,i) in rows" :key="i"><td>{{ i+1 }}</td><td>{{ describe(r) }}</td></tr></tbody></table></div></details>
  </template>
  <img v-else :src="withBase(figure)" :alt="title" loading="lazy" />
 </section>
</template>
<style scoped>
.interactive-recorded{border:1px solid var(--vp-c-divider);border-radius:8px;padding:.8rem;margin:.8rem 0}
.controls{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center}button,select{border:1px solid var(--vp-c-divider);border-radius:5px;padding:.3rem .6rem;cursor:pointer;background:var(--vp-c-bg);color:var(--vp-c-text-1)}
.plot-scroll,.table-scroll{overflow:auto;max-height:650px}svg{display:block;min-width:600px}svg text{font:11px system-ui;fill:var(--vp-c-text-1)}.grid{stroke:var(--vp-c-divider)}
.mark{cursor:pointer;stroke:var(--vp-c-bg);stroke-width:.7}.mark:hover,.mark:focus{stroke:var(--vp-c-text-1);stroke-width:2;outline:none}.frame-label{pointer-events:none;fill:white;font-size:10px}
.reading{overflow-wrap:anywhere;background:var(--vp-c-bg-soft);padding:.6rem;min-height:3em}.reading,.hint{font-size:.85rem}img{width:100%}
</style>
