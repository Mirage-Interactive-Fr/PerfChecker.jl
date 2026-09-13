<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
const props = withDefaults(defineProps<{ source?: string; figure?: string; packageName?: string }>(), {
  source: '/examples/bibliography/history/normalized.json',
  figure: '/examples/bibliography/figures/normalized.svg', packageName: 'Bibliography'
})
const plot = ref<any>(null), selected = ref<any>(null)
const releaseDates = ref<Record<string,string>>({})
const hidden = ref<string[]>([])
const colors = ['#087e8b', '#b46a22', '#7655ad', '#3372b7']
const order = ['julia.wall.time', 'julia.gc.time', 'julia.alloc.bytes', 'julia.alloc.count']
const names:Record<string,string> = {'julia.wall.time':'Elapsed time', 'julia.gc.time':'GC time', 'julia.alloc.bytes':'Allocated bytes', 'julia.alloc.count':'Allocation count'}
const metrics = computed(()=>order.filter(metric=>plot.value?.data.some((row:any)=>row.metric===metric)))
const rows = (metric:string)=>plot.value.data.filter((row:any)=>row.metric===metric)
const maximum = computed(()=>Math.max(1, ...(plot.value?.data??[]).filter((row:any)=>!hidden.value.includes(row.metric)).map((row:any)=>row.ratio??0))*1.15)
const x = (version:string)=>60+plot.value.options.versions.indexOf(version)*660/Math.max(1,plot.value.options.versions.length-1)
const y = (ratio:number)=>280-ratio/maximum.value*245
const path = (metric:string)=>{
  let connected=false
  return rows(metric).map((row:any)=>{
    if(row.ratio===null){connected=false;return ''}
    const command=connected?'L':'M';connected=true;return `${command}${x(row.version)},${y(row.ratio)}`
  }).join(' ')
}
const describe = (row:any)=>`${row.version}${releaseDates.value[row.version]?' ('+releaseDates.value[row.version]+')':''} · ${names[row.metric]}: ${row.value} ${row.unit} · ${row.ratio===null?'ratio unavailable':row.ratio.toFixed(3)+'× minimum'}${row.normalization_status==='both_zero'?' (zero throughout; shown at 1 as unchanged)':''}`
const toggle = (metric:string)=>hidden.value=hidden.value.includes(metric)?hidden.value.filter(item=>item!==metric):[...hidden.value,metric]
onMounted(async()=>{try{const response=await fetch(withBase(props.source));if(response.ok){const record=await response.json();plot.value=record.plot;releaseDates.value=record.release_dates??{}}}catch{/* Static measured figure remains available. */}})
</script>

<template>
  <section class="normalized-measurements" :aria-label="`Overlaid ${packageName} measurements normalized by minimum`">
    <template v-if="plot">
      <div class="metric-toggles" role="group" aria-label="Visible measurements">
        <button v-for="(metric,i) in metrics" :key="metric" type="button" :aria-pressed="!hidden.includes(metric)" @click="toggle(metric)">
          <span :style="{color:colors[i]}" aria-hidden="true">●</span> {{ names[metric] }}
        </button>
      </div>
      <div class="normalized-scroll">
        <svg viewBox="0 0 760 380" role="img" aria-label="Four overlaid curves; the minimum of each measurement is one">
          <g v-for="tick in [0,1,maximum]" :key="tick">
            <line x1="60" x2="725" :y1="y(tick)" :y2="y(tick)" :class="tick===1?'reference':'grid'" />
            <text x="50" :y="y(tick)+4" text-anchor="end">{{ tick.toFixed(tick>1?1:0) }}×</text>
          </g>
          <g v-for="(metric,i) in metrics" :key="metric" :style="{display:hidden.includes(metric)?'none':undefined}">
            <path :d="path(metric)" fill="none" :stroke="colors[i]" stroke-width="2.5" />
            <template v-for="row in rows(metric)" :key="row.version">
              <circle v-if="row.ratio!==null" :cx="x(row.version)" :cy="y(row.ratio)" r="4" :fill="colors[i]" tabindex="0" :aria-label="describe(row)" @mouseenter="selected=row" @focus="selected=row" @click="selected=row"><title>{{ describe(row) }}</title></circle>
            </template>
          </g>
          <g v-for="version in plot.options.versions" :key="version" :transform="`translate(${x(version)},298) rotate(-45)`">
            <text text-anchor="end">{{ version }}</text>
            <text v-if="releaseDates[version]" y="14" text-anchor="end" class="release-date">{{ releaseDates[version] }}</text>
          </g>
          <text x="390" y="375" text-anchor="middle">{{ packageName }} version{{ Object.keys(releaseDates).length?' · release dates; equally spaced versions':'' }}</text>
          <text x="60" y="17">Minimum sample per version / minimum across versions</text>
        </svg>
      </div>
      <p class="point-reading" aria-live="polite">{{ selected?describe(selected):'Hover or focus a point to read its raw value. Toggle a measure to isolate its curve.' }}</p>
    </template>
    <img v-else :src="withBase(figure)" :alt="`${packageName} metrics overlaid across versions, each normalized by its minimum.`" />
    <p class="normalization-note">Each curve has its own minimum at <strong>1</strong>. A value of <strong>1.5</strong> means 50% more than that minimum. The minima can belong to different versions. Equal zeros are displayed at 1 by convention; a nonzero value divided by zero has no finite ratio and is left unplotted. Inspect the raw values before interpreting GC.</p>
    <a :href="withBase(source)" download>Download the plotted values</a>
    · <a :href="withBase(figure)">Open the full-size plot</a>
  </section>
</template>

<style scoped>
.normalized-measurements { border:1px solid var(--vp-c-divider);border-radius:14px;padding:1rem;margin:1.4rem 0; }
.metric-toggles { display:flex;flex-wrap:wrap;gap:.5rem; }
.metric-toggles button { border:1px solid var(--vp-c-divider);border-radius:8px;padding:.35rem .7rem;font-size:.85rem;cursor:pointer; }
.metric-toggles button[aria-pressed="false"] { opacity:.5;text-decoration:line-through; }
.normalized-scroll { overflow-x:auto; }
svg { display:block;width:100%;min-width:600px; }
svg text { fill:var(--vp-c-text-2);font:12px system-ui,sans-serif; }
.release-date { font-size:10px; }
.grid { stroke:var(--vp-c-divider); }
.reference { stroke:var(--vp-c-text-2);stroke-dasharray:5 4; }
circle:focus { outline:2px solid var(--vp-c-text-1); }
.point-reading,.normalization-note { font-size:.85rem;line-height:1.6; }
.point-reading { min-height:3em;background:var(--vp-c-bg-soft);padding:.5rem; }
</style>
