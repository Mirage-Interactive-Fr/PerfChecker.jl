<script setup lang="ts">
import { computed, h, onMounted, ref, resolveComponent } from 'vue'
import { withBase } from 'vitepress'
import RecordedFigure from './RecordedFigure.vue'
const props = defineProps<{ directory: string }>()
const views = ref<any[]>([]), error = ref('')
const kinds = [
  ['allocation_pie', 'Allocation share'], ['allocation_files', 'By file'],
  ['allocation_lines', 'By line'], ['allocation_heatmap', 'Heatmap'],
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
    views.value = (await response.json()).views
  } catch (e) { error.value = String(e) }
})
</script>
<template>
  <section class="recorded-figures" aria-label="Recorded profile figures">
    <p v-if="error" role="alert">{{ error }}</p>
    <RenderTabs v-if="groups.length > 1" />
    <RecordedFigure v-else v-for="view in views" :key="view.id" :directory="directory" :view="view" />
  </section>
</template>
