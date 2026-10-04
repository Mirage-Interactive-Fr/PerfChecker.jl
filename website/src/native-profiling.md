# Julia and native profiling

Locate where an operation spends time.

Use Julia's tools first. Use a native profiler to inspect a C/C++/Fortran dependency or activity outside Julia.

## Pick an instrument from the question

- Slower than before? BenchmarkTools or Chairmarks, before and after.
- Which calls take the time? Julia CPU profiler, then perf or VTune for native frames.
- Waiting rather than computing? Wall-time profile; WPR/WPA or perf/bpftrace for system traces.
- Which Julia code allocates? `Profile.Allocs`; a heap snapshot for retained objects.
- Process memory growing? [Process-memory counters](process-memory.md); Massif or heaptrack for native heap.
- Slow first call? Measure startup and first call separately; SnoopCompile for compilation.
- More threads not helping? Repeat at several thread counts; inspect scheduling and locks.
- GPU work? A device profiler such as Nsight; synchronize before timing.
- Native dependency misusing memory? Memcheck or a sanitizer build.

Native tools require separate installation. PerfChecker can **prepare commands** for some of them; listing a tool does not mean it can run it or import its output.

## Static analysis and compilation

These inspect code, not measured cost. Treat a diagnostic as a hypothesis and confirm practical cost with a benchmark.

- **JET** — follows the inferred call graph; reports possible runtime dispatch and inference pitfalls.
- **Cthulhu** — descend through inferred code to see where type information becomes imprecise.
- **SnoopCompile** — examine inference work that contributes to compilation.
- **AllocCheck** — statically visible allocation and dispatch paths in generated LLVM.
- **PrecompileTools / PackageCompiler** — change the startup/artifact tradeoff; compare cold import, first call, steady state, build cost and artifact size separately.
- **Aqua** — package quality (ambiguities, unused type parameters). A pass is not a latency or memory budget.

## Linux native tools

`native_tool_plan` prepares argument vectors for Memcheck, Callgrind, Cachegrind, Massif, heaptrack, perf and VTune. It checks local executable presence without starting a process.

```julia
using PerfChecker
plan = native_tool_plan(:memcheck, "native_case.jl";
    project = "perf", output = "results/memcheck",
    suppressions = "contrib/valgrind-julia.supp")
```

Valgrind needs `--smc-check=all-non-file` for Julia's JIT. Some investigations need Julia built with memory pools disabled. A zero exit is not enough without the workload oracle and reviewed diagnostics.

- **Memcheck** — invalid reads/writes, uninitialized values, leaks. Correctness diagnostics, not speed.
- **Callgrind** — instruction execution and call relationships. Read self vs inclusive cost; not elapsed time.
- **Cachegrind** — instructions plus simulated caches/branches. Simulation, disabled by default, not modern CPUs.
- **Massif** — sampled native heap usage. Peak vs endpoint; the time axis may be instructions.
- **heaptrack** — native allocation stacks. Temporary activity vs retained memory.
- **perf / LIKWID / PAPI** — hardware counters. Record multiplexing and affinity; a missing counter is not zero.

Units matter: instruction counts, cache misses and heap sizes are not elapsed seconds. Use an ordinary benchmark for the final comparison.

## Windows, traces and instrumented builds

- **WPR/WPA** record and analyze ETW traces for scheduling, I/O and system activity.
- **VTune** is another CPU analysis route.
- Julia exposes Tracy/VTune timing zones and DTrace/bpftrace probes; coverage depends on the build.
- **Sanitizers** diagnose memory errors or races; their overhead cannot be treated as production performance.

## GPU, distributed, foreign runtimes

- CUDA: synchronize before comparing completed costs; separate host/device transfer from kernels.
- AMDGPU/rocprof, oneAPI, MPI/Dagger traces and NPU providers remain environment-specific candidates.
- Native dependency fingerprints, actual devices, transfer boundaries, rank identities and fallback detection are required before interpreting these measurements.
- macOS tooling stays inventoried; no Mac validation is claimed.

## Before calling an adapter supported

Run four controls: a healthy workload, a known native leak, a known CPU hotspot and a child-process workload. Check symbol/source attribution, nonzero diagnostics for injected defects, bounded cancellation, artifact completeness and matching dependency identities. Then rerun unchanged controls without the profiler to measure its perturbation. Windows and Linux need their own evidence.

```@raw html
<a id="Julia-and-native-performance-tools"></a>
<a id="Choose-an-instrument-from-the-question"></a>
<a id="JET:-possible-inference-and-dispatch-problems"></a>
<a id="Cthulhu:-inspect-the-compiler's-view-interactively"></a>
<a id="SnoopCompile:-investigate-compilation-work"></a>
<a id="AllocCheck:-inspect-possible-allocation-paths"></a>
<a id="Precompilation-tools-and-package-quality"></a>
<a id="Memcheck:-invalid-memory-operations-and-leaks"></a>
<a id="Callgrind:-instruction-cost-along-a-call-graph"></a>
<a id="Cachegrind:-instructions-and-optional-simulated-caches"></a>
<a id="Massif-and-heaptrack:-native-heap-growth"></a>
<a id="Hardware-counters:-events-on-the-actual-processor"></a>
<a id="GPU,-distributed-and-foreign-runtimes"></a>
<a id="Qualification-experiment"></a>
```
