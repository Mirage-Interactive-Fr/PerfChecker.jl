<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
import WorkloadGroup from './WorkloadGroup.vue'
const props = defineProps<{ directory: string; containers?: boolean }>()
const catalog = ref<any>(null), records = ref<Record<string, any>>({}), error = ref('')
const purposes: Record<string, string> = {
  heap_2048: 'Insert 2,048 events into a heap and remove them in priority order. Compare the two collectors separately; they use distinct sampling machinery.',
  vector_2048: 'Sort the same events with a Base Julia vector. This control helps reveal timing changes that are not specific to DataStructures.',
  counter_2048: 'Count the categories of 2,048 events. The independent oracle uses a fixed-size vector of counts.',
  buffer_2048: 'Retain the last 64 of 2,048 events in a circular buffer, including the cost of overwriting older entries.',
  heap_request: 'Decode 2,048 events, order them with a heap, and encode the response. Compare the BenchmarkTools and Chairmarks captures as separate experiments.',
  counter_request: 'Decode the event request, count categories, and encode the counts. JSON and response handling are included.',
  buffer_request: 'Decode the event request, retain the latest 64 events, and encode the response. This includes overwriting the circular buffer.',
  Deque: 'A double-ended queue. Construction inserts at the back; draining removes from the front. Watch the cost of allocating and crossing storage blocks.',
  Queue: 'A first-in, first-out queue. The drain case excludes construction, so a change in insertion cost cannot conceal a change in removal cost.',
  Stack: 'A last-in, first-out stack. The oracle expects the reverse arrival order. Compare its storage allocations separately from the cost of popping.',
  CircularDeque: 'A bounded double-ended queue. Capacity is set to the input size before insertion; this case never overflows the queue.',
  CircularBuffer: 'A bounded ring buffer. This case fills and drains 512 entries without overwriting. The earlier event-retention case exercises overwriting separately.',
  LinkedList: 'An immutable linked list, built with cons. Traversal includes producing an ordinary vector; the oracle checks arrival order.',
  MutableLinkedList: 'A mutable linked list. Construction and destructive front removal expose node allocation and pointer traversal independently.',
  BinaryMinHeap: 'A binary minimum heap. Repeated insertion builds the heap; draining must produce ascending keys. Input generation is outside both measurements.',
  BinaryMaxHeap: 'A binary maximum heap. Draining must produce descending keys; compare it with the minimum heap only when that ordering matches your application.',
  MutableBinaryMinHeap: 'A minimum heap with handles for later updates. This baseline measures construction and extraction; it does not measure handle updates.',
  MutableBinaryMaxHeap: 'A maximum heap with handles. The case retains the same insertion sequence as the other heaps and checks descending extraction.',
  BinaryMinMaxHeap: 'A heap supporting both extremes. The baseline drains its minimum end; alternating minimum/maximum removal is a different workload.',
  PriorityQueue: 'A mapping from unique keys to priorities. The drain operation returns key–priority pairs in priority order; it is not a FIFO queue.',
  OrderedDict: 'A dictionary preserving insertion order. The lookup case follows a fixed shuffled key order and excludes construction.',
  LittleDict: 'A compact ordered dictionary intended for small collections. The 512-key case deliberately tests beyond tiny dictionaries; rerun with smaller n before choosing it.',
  DefaultDict: 'A dictionary with a default value. Construction uses explicit assignments; lookup uses existing keys, so default-value creation is not part of this baseline.',
  DefaultOrderedDict: 'An insertion-ordered dictionary with defaults. Existing-key lookup separates ordinary access from default insertion.',
  RobinDict: 'A dictionary using Robin Hood hashing. The fixed permutation gives every release identical keys and insertion order.',
  OrderedRobinDict: 'An ordered Robin Hood dictionary. Compare construction allocations with RobinDict to observe the cost of maintaining order.',
  SwissDict: 'A Swiss-table dictionary. Existing integer-key lookups are a controlled baseline; collision-heavy keys require an additional scenario.',
  SortedDict: 'A key-sorted dictionary. Construction checks sorted contents; lookups use shuffled keys rather than a favorable sequential traversal.',
  SortedMultiDict: 'A sorted dictionary that permits duplicate keys. This baseline uses unique keys, then traverses sorted pairs; duplicate-heavy behavior remains a separate case.',
  MultiDict: 'A dictionary holding several values per key. Keys are grouped into 16 buckets; traversal checks every value against an independent partition.',
  OrderedSet: 'A set preserving insertion order. Construction and membership probes use the same unique integer population.',
  SortedSet: 'A sorted set. Construction validates sorted keys; membership probes use the fixed shuffled order.',
  SparseIntSet: 'A sparse set specialized for integers. This dense 1:512 population is a baseline; increase the key range to study sparse occupancy.',
  Accumulator: 'An integer counter. Construction counts 16 categories; traversal returns the complete category-count dictionary.',
  Trie: 'A prefix tree with character keys. Integer keys are converted to decimal strings; lookup includes that conversion, consistently across releases.',
  IntDisjointSet: 'An integer union–find structure. Construction joins adjacent pairs; the second case checks group counts and connectivity after those unions.',
  DisjointSet: 'A union–find structure for general keys. The same adjacent integer pairs allow comparison with the integer specialization.',
  FenwickTree: 'A binary indexed tree for prefix sums. Construction loads the fixed permutation; the query case requests every prefix and checks against cumsum.',
  DiBitVector: 'A packed two-bit vector. Construction writes values from zero to three; traversal checks the unpacked sequence.',
  AVLTree: 'An AVL search tree. Construction inserts a shuffled population; lookup probes every present key. Deletion and absent-key queries are different scenarios.',
  RBTree: 'A red–black search tree. The same insertion and lookup sequences make release comparisons independent of random input changes.',
  SplayTree: 'A self-adjusting search tree. Every sample starts from a freshly built tree, because successful lookups can change its shape.',
  plain: 'Return a short text response. This isolates dispatch and response conversion from application work.',
  path: 'Parse two typed path parameters and return their sum. The independent answer is 42.',
  query: 'Parse two query-string parameters and return their sum. This exercises Oxygen.queryparams separately from typed path extraction.',
  json: 'Serialize a dictionary containing a boolean and 64 integers. The oracle compares decoded data, so dictionary key order does not change correctness.',
  html: 'Return a short HTML response with Oxygen.html. This measures the helper and routing, not browser rendering.',
  binary: 'Echo a fixed 4 KiB body using Oxygen.binary. No JSON decoding is involved.',
  not_found: 'Request an unregistered route and check HTTP 404. Error dispatch is a separate workload from successful routes.'
}
const views = computed(() => catalog.value?.views.filter((v:any) => v.kind === 'normalized_metrics') ?? [])
const groups = computed(() => {
  const grouped = new Map<string, any[]>()
  for (const view of views.value) {
    const name = view.workload.replace(/_(build|lookup|drain|traverse|connectivity|prefixsum|http)$/, '')
    grouped.set(name, [...(grouped.get(name) ?? []), view])
  }
  return [...grouped].map(([name, cases]) => ({ name, cases }))
})
function observations(id:string) {
  const rows = records.value[id]?.plot?.data?.filter((r:any) => r.metric === 'julia.wall.time' && r.value != null) ?? []
  if (rows.length < 2) return ''
  const best = rows.reduce((a:any,b:any) => a.value < b.value ? a : b)
  let pair = [rows[0], rows[1]]
  for (let i=2; i<rows.length; i++) {
    if (rows[i-1].value > 0 && rows[i].value / rows[i-1].value > pair[1].value / pair[0].value) pair = [rows[i-1], rows[i]]
  }
  const change = pair[0].value > 0 ? 100 * (pair[1].value / pair[0].value - 1) : null
  const microsecondFactor:Record<string,number>={ns:.001,'µs':1,us:1,ms:1000,s:1000000}
  const factor=microsecondFactor[best.unit]
  const formatted=factor===undefined?`${best.value} ${best.unit}`:`${(best.value*factor).toFixed(2)} µs`
  return `Lowest observed time: ${formatted} at ${best.version}. ` +
    (change !== null && change > 0 ? `Largest adjacent increase: ${change.toFixed(1)}% from ${pair[0].version} to ${pair[1].version}. Recheck that pair before calling it a regression.` : 'No adjacent time increase was observed in these minima.')
}
onMounted(async () => {
  try {
    const response = await fetch(withBase(props.directory + '/catalog.json'))
    if (!response.ok) throw Error('The recorded catalogue could not be loaded.')
    catalog.value = await response.json()
    // Small numeric projections drive the captions; measurements never run in the browser.
    const entries = await Promise.all(views.value.map(async (v:any) => {
      const response = await fetch(withBase(props.directory + '/' + v.json))
      if (!response.ok) throw Error('A recorded measurement could not be loaded.')
      return [v.id, await response.json()]
    }))
    records.value = Object.fromEntries(entries)
  } catch (e) { error.value = String(e) }
})
</script>
<template>
  <section class="workload-atlas" aria-label="Separate workload histories">
    <p v-if="error" role="alert">{{ error }}</p>
    <template v-if="catalog">
      <p><strong>{{ views.length }} separate workload figures · {{ catalog.versions.length }} releases.</strong>
        Each curve uses 30 samples after warmup. The four metrics are divided by their own minimum across the selected versions.</p>
      <nav aria-label="Workloads"><a v-for="group in groups" :key="group.name" :href="'#case-'+group.name">{{ group.name }}</a></nav>
      <section v-for="group in groups" :key="group.name" :id="'case-'+group.name">
        <h3>{{ group.name }}</h3>
        <p>{{ purposes[group.name] }}</p>
        <WorkloadGroup :directory="directory" :group="group" :observations="observations" />
      </section>
    </template>
  </section>
</template>
<style scoped>
nav{display:flex;flex-wrap:wrap;gap:.3rem .8rem;margin:1rem 0}nav a{font-size:.9rem}
section[id]{scroll-margin-top:90px}figure{margin:1rem 0 2rem}img{width:100%;background:white;border-radius:8px}
figcaption{font-size:.94rem;color:var(--vp-c-text-2)}h4{margin:.8rem 0}
</style>
