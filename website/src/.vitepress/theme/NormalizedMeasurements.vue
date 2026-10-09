<script setup lang="ts">
import {computed} from 'vue'
import {withBase} from 'vitepress'
import InteractiveRecordedPlot from './InteractiveRecordedPlot.vue'
const props=withDefaults(defineProps<{source?:string;figure?:string;html?:string;packageName?:string;compact?:boolean}>(),{
 source:'/examples/bibliography/history/normalized.json',figure:'/examples/bibliography/figures/normalized.svg',packageName:'Bibliography'
})
const nativeHtml=computed(()=>props.html??(props.source==='/examples/bibliography/history/normalized.json'?'/examples/bibliography/history/normalized.html':undefined))
</script>
<template>
 <section :aria-label="`Overlaid ${packageName} measurements normalized by minimum`">
  <InteractiveRecordedPlot :source="source" :figure="figure" :html="nativeHtml" :title="`${packageName} normalized measurements`" />
  <p v-if="!compact" class="normalization-note">Each curve has its own minimum at <strong>1</strong>. A value of <strong>1.5</strong> means 50% more than that minimum. The minima can belong to different versions. Equal zeros are displayed at 1 by convention; a nonzero value divided by zero has no finite ratio and is left unplotted. Inspect the raw values before interpreting GC.</p>
  <a :href="withBase(source)" download>Download the plotted values</a>
  · <a :href="withBase(figure)">Open the full-size plot</a>
 </section>
</template>
<style scoped>
.normalization-note{font-size:.85rem;line-height:1.6}
</style>
