<script setup lang="ts">
import { computed, h, onMounted, ref, resolveComponent } from 'vue'
import { withBase } from 'vitepress'
import RecordedFigure from './RecordedFigure.vue'
import {isLatestDiagnostic,isVersionComparison} from './recorded-view-policy.mjs'
const props = withDefaults(defineProps<{ directory: string; mode?: 'latest'|'history'; featurePrefix?:string }>(), {mode:'latest'})
const views = ref<any[]>([]), error = ref('')
const selected=ref('')
const normalizedCollection=computed(()=>views.value.length>0&&views.value.every(view=>view.normalized_views?.length))
const active=computed(()=>views.value.find(view=>view.id===selected.value)??views.value[0])
const kinds = [
  ['allocation_pie', 'Allocation share'], ['allocation_files', 'By file'],
  ['allocation_lines', 'By line'], ['allocation_heatmap', 'Allocation history'],
  ['allocation_flamegraph', 'Allocation stacks'], ['cpu_flamegraph', 'CPU stacks'],
  ['wall_flamegraph', 'Wall-time stacks'], ['version_series', 'Totals']
]
const groups = computed(() => {
  const used = new Set<string>()
  const result = kinds.map(([kind,label]) => {
    const entries = views.value.filter(view => view.kind === kind)
    entries.forEach(view => used.add(view.id))
    return {label, entries}
  }).filter(group => group.entries.length)
  const remaining = views.value.filter(view => !used.has(view.id))
  if (remaining.length) result.push({label:'Other figures', entries:remaining})
  return result
})
// Pass direct tab VNodes: the installed plugin discovers labels from its slots.
const RenderTabs = () => {
  const Tabs = resolveComponent('PluginTabs'), Tab = resolveComponent('PluginTabsTab')
  return h(Tabs, {}, {default: () => groups.value.map(group =>
    h(Tab, {key:group.label, label:group.label}, {default: () => group.entries.map(view =>
      h(RecordedFigure, {key:view.id, directory:props.directory, view}))}))})
}
onMounted(async () => {
  try {
    const response = await fetch(withBase(props.directory+'/catalog.json'))
    if (!response.ok) throw Error('The recorded figures could not be loaded.')
    const catalog = await response.json()
    const inspected = await Promise.all(catalog.views.map(async (view:any) => {
      const response = await fetch(withBase(props.directory+'/'+(view.plot??view.json)))
      if (!response.ok) throw Error('A recorded profile model could not be loaded.')
      return {view, model:(await response.json()).plot}
    }))
    views.value = inspected.filter(({model}) => props.mode==='latest'
      ? isLatestDiagnostic(model) : isVersionComparison(model))
      .filter(({view}) => !props.featurePrefix || view.feature?.startsWith(props.featurePrefix))
      .filter(({view}) => !view.feature?.endsWith('_alloc') || view.feature?.endsWith('_profile_alloc'))
      .map(({view}) => view)
  } catch (e) { error.value = String(e) }
})
</script>
<template>
  <section class="recorded-figures" aria-label="Recorded profile figures">
    <p v-if="error" role="alert">{{ error }}</p>
    <template v-if="normalizedCollection">
      <label>Container <select :value="active?.id" @change="selected=($event.target as HTMLSelectElement).value"><option v-for="view in views" :key="view.id" :value="view.id">{{ view.title }}</option></select></label>
      <RecordedFigure v-if="active" :key="active.id" :directory="directory" :view="active" />
    </template>
    <RenderTabs v-else-if="groups.length > 1" />
    <RecordedFigure v-else v-for="view in views" :key="view.id" :directory="directory" :view="view" />
    <p v-if="!error&&!views.length">No {{ mode==='latest'?'single-release profile':'comparison with at least two recorded releases' }} is available in this capture.</p>
  </section>
</template>
