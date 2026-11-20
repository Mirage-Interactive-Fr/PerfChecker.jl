```@raw html
---
search: false
---
```

# Julia and native profiling

Follow the [recorded JET before/after example](tools/jet.md#Follow-a-finding-through-a-change), or use [CPU profiles](tools/cpu-profile.md), [native instruction counts](tools/callgrind.md), [native heap timelines](tools/massif.md) and [hardware counters](tools/linuxperf.md).

```@raw html
<a id="Julia-and-native-performance-tools"></a>
<a id="Choose-an-instrument-from-the-question"></a>
<a id="JET:-possible-inference-and-dispatch-problems"></a>
<a id="AllocCheck:-inspect-possible-allocation-paths"></a>
<a id="SnoopCompile:-investigate-compilation-work"></a>
<a id="Precompilation-tools-and-package-quality"></a>
<a id="Memcheck:-invalid-memory-operations-and-leaks"></a>
<a id="Callgrind:-instruction-cost-along-a-call-graph"></a>
<a id="Cachegrind:-instructions-and-optional-simulated-caches"></a>
<a id="Massif-and-heaptrack:-native-heap-growth"></a>
<a id="Hardware-counters:-events-on-the-actual-processor"></a>
<a id="GPU,-distributed-and-foreign-runtimes"></a>
<a id="Qualification-experiment"></a>
<a id="Julia-and-native-profiling"></a>
<a id="Pick-an-instrument-from-the-question"></a>
<a id="Static-analysis-and-compilation"></a>
<a id="JET:-find-a-dispatch-problem,-then-check-the-change"></a>
<a id="Before:-the-collection-hides-the-row-type"></a>
<a id="Inside-net_revenue(rows),-cases.jl:14:"></a>
<a id="After:-keep-the-validated-record-type"></a>
<a id="Did-this-diagnostic-correspond-to-a-measured-cost?"></a>
<a id="Read-three-other-analyzer-results"></a>
<a id="Linux-native-tools"></a>
<a id="Windows,-traces-and-instrumented-builds"></a>
<a id="GPU,-distributed,-foreign-runtimes"></a>
<a id="Before-calling-an-adapter-supported"></a>
```
