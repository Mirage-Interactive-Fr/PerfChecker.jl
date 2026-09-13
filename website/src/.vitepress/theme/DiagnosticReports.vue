<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
const props = defineProps<{ source: string }>()
const records = ref<any[]>([]), error = ref('')
function findingGroups(record: any) {
  const groups = new Map<string, {rule: string; severity: string; count: number; locations: Set<string>}>()
  for (const finding of record.findings ?? []) {
    const key = `${finding.rule_id}:${finding.severity}`
    const group = groups.get(key) ?? {rule: finding.rule_id || 'Finding', severity: finding.severity || '', count: 0, locations: new Set<string>()}
    group.count++
    if (finding.location?.file) group.locations.add(`${finding.location.file}:${finding.location.line ?? '?'}`)
    groups.set(key, group)
  }
  return [...groups.values()].sort((a,b) => b.count-a.count)
}
function location(finding: any) {
  return finding.location?.file ? `${finding.location.file}:${finding.location.line ?? '?'}` : 'Location not recorded'
}
onMounted(async () => {
  try {
    const response = await fetch(withBase(props.source))
    if (!response.ok) throw Error('The recorded diagnostic reports could not be loaded.')
    records.value = (await response.json()).records
  } catch (e) { error.value = String(e) }
})
</script>
<template>
  <section class="diagnostic-reports" aria-label="Diagnostic findings">
    <p v-if="error" role="alert">{{ error }}</p>
    <p v-else><a :href="withBase(source)" download>Download the full diagnostic records</a></p>
    <article v-for="record in records" :key="record.tool">
      <h4>{{ record.tool }} <small>{{ record.tool_version }}</small></h4>
      <p>{{ record.analysis_scope || record.scope }}. Status: <strong>{{ record.status || record.availability }}</strong>;
        oracle: {{ record.correctness }}<template v-if="record.quality">; quality: {{ record.quality }}</template>.</p>
      <p v-if="record.summary">{{ record.summary.length > 280 ? record.summary.slice(0,280)+'…' : record.summary }}</p>
      <details v-if="record.summary?.length > 280"><summary>Full summary</summary><pre>{{ record.summary }}</pre></details>
      <p v-if="record.instrumented_instructions != null">Instrumented instructions: {{ record.instrumented_instructions.toLocaleString() }}.</p>
      <template v-if="record.findings?.length">
        <p><strong>{{ record.findings.length }} findings</strong>, grouped below by kind. Counts are diagnostic reports, not measured slowdowns.</p>
        <table class="finding-summary"><thead><tr><th>Finding</th><th>Count</th><th>Locations</th></tr></thead>
          <tbody><tr v-for="group in findingGroups(record)" :key="group.rule+group.severity">
            <td>{{ group.rule }} <small>{{ group.severity }}</small></td><td>{{ group.count }}</td>
            <td>{{ [...group.locations].slice(0,2).join(', ') || 'Not recorded' }}<span v-if="group.locations.size > 2"> · {{ group.locations.size-2 }} more</span></td>
          </tr></tbody>
        </table>
        <details class="finding-details"><summary>Inspect all {{ record.findings.length }} findings</summary>
          <ol><li v-for="(finding,i) in record.findings" :key="i"><details>
            <summary>{{ finding.rule_id }} · {{ location(finding) }}</summary><pre>{{ finding.message }}</pre>
          </details></li></ol>
        </details>
      </template>
      <p v-else-if="['jet','alloccheck'].includes(record.tool)">No findings were reported in this specialization and scope.</p>
      <p v-if="record.measurements?.inference_seconds != null">Recorded inference: {{ (record.measurements.inference_seconds*1e6).toFixed(2) }} µs.</p>
      <details v-if="record.log_excerpt"><summary>Tool output</summary><pre>{{ record.log_excerpt }}</pre></details>
    </article>
  </section>
</template>
<style scoped>
pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:.82rem;max-height:24rem;overflow:auto}
small{font-weight:400;color:var(--vp-c-text-2)}summary{cursor:pointer;overflow-wrap:anywhere}
.finding-summary{font-size:.88rem;table-layout:fixed;width:100%}.finding-summary td{overflow-wrap:anywhere}
.finding-details{margin:1rem 0;padding:.65rem 1rem;background:var(--vp-c-bg-soft);border-radius:8px}
li details{margin:.6rem 0}article{margin-bottom:1.5rem}
</style>
