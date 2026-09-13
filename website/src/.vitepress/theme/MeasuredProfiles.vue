<script setup lang="ts">
import { computed, ref } from 'vue'
import { withBase } from 'vitepress'
const selected = ref('cpu')
const views = [
  { id: 'cpu', label: 'CPU samples', reading: 'Width is the share of retained CPU samples. Follow a wide export branch into its callees; the number of samples is neither an invocation count nor a duration in nanoseconds.' },
  { id: 'wall', label: 'Wall-time task samples', reading: 'Width is the share of retained task samples. A task can be waiting, so a wide branch does not necessarily indicate CPU work. Compare this call path with the CPU profile and the elapsed-time benchmark.' },
  { id: 'allocations', label: 'Allocated bytes', reading: 'Width is the share of sampled allocated bytes. It locates allocation paths, not elapsed time or objects proven to leak. Use the benchmark to measure the per-export allocation cost.' },
]
const view = computed(() => views.find(item => item.id === selected.value)!)
const root = '/examples/bibliography/profiles/'
</script>

<template>
  <section class="measured-profiles" aria-label="Recorded Bibliography flame graphs">
    <label>Profile weight
      <select v-model="selected" aria-label="Choose profile weight">
        <option v-for="item in views" :key="item.id" :value="item.id">{{ item.label }}</option>
      </select>
    </label>
    <p>{{ view.reading }}</p>
    <iframe :key="selected" :src="withBase(root+selected+'.html')" :title="'Bibliography export flame graph: '+view.label" loading="lazy"></iframe>
    <p>The full graph is fitted initially. Use + to enlarge its labels, then scroll inside the graph. Hover a rectangle, or use Tab to focus it, for its full stack and weight. Fit graph restores the overview.</p>
    <p><a :href="withBase(root+selected+'.html')">Open the full graph</a> · <a :href="withBase(root+selected+'.json')" download>Download its frames and provenance</a></p>
  </section>
</template>

<style scoped>
select{margin-left:.6rem;padding:.4rem;border:1px solid var(--vp-c-divider);border-radius:6px;background:var(--vp-c-bg);color:var(--vp-c-text-1);font:inherit}label{font-weight:600}iframe{display:block;width:100%;height:570px;border:1px solid var(--vp-c-divider);border-radius:8px}
</style>
