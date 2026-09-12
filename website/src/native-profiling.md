# Julia and native performance tools

Start with the question in the table below, then read the corresponding tool
section. For a reproducible Julia profile, use the [Bibliography collector commands](tutorials/bibliography.md#Select-a-package,-workload-and-collector).
Native tools additionally need a compatible installation and a workload script.

The inventory in `data/tool-catalog.json`, available through `tool_catalog()` and
the web/VS Code catalogue, distinguishes implemented collectors, optional
extensions and external tools. Inventory membership never implies qualification.
This review was refreshed on 12 September 2026.

## Choose an instrument from the question

| Question | First measurement | Follow-up evidence | Main limitation |
| --- | --- | --- | --- |
| Is an operation slower? | BenchmarkTools or Chairmarks distribution | Same input and oracle, repeated sessions | Setup, JIT and environment differences can dominate |
| Where does CPU time go? | Julia Profile, with C frames when needed | perf or VTune; symbols for native libraries | Sampling noise; unresolved/inlined frames |
| Why is wall time larger than CPU time? | Wall profile plus workload timeline | ETW/WPR on Windows; perf/bpftrace on Linux | Other processes, scheduling and I/O attribution |
| Why does the Julia heap allocate? | Profile.Allocs, GC counters, heap snapshots | AllocCheck and inference inspection | Native allocations are a different quantity |
| Why does native memory grow? | RSS/private memory and explicit resource ledgers | Memcheck, Massif, heaptrack | Allocator pools, mappings and retained capacity differ |
| Why is startup slow? | Fresh-process startup/first-call measurement | SnoopCompile; runtime timing zones | Warm measurements conceal compilation and imports |
| Why does threading scale badly? | Same workload across declared thread counts | Counters, affinity, lock events and timelines | NUMA, quotas and oversubscription confound results |
| Is a device doing the work? | Verified device identity and synchronized operation | CUDA/Nsight, ROCm tools, VTune | Async launch time is not completed device execution |
| Is a native dependency incorrect? | Functional oracle and dependency provenance | Sanitizers or Memcheck | Instrumented execution does not measure native speed |

Julia's own profiler can include native C/Fortran frames. Allocation profiling
describes Julia allocations; it must not be presented as all process memory.
Keep warmup and asynchronous completion explicit. See the [Julia profiling manual](https://docs.julialang.org/en/v1/manual/profile/).

## Static analysis and compilation

A static analyzer inspects code and its inferred or compiled representation.
It can find suspicious operations without timing an actual Bibliography export.
A diagnostic therefore points to a hypothesis: for example, an uncertain type
may lead to dynamic method selection, but its practical cost still needs a
measurement. Compilation tools answer another question: how much work happens
before the operation can run efficiently?

### JET: possible inference and dispatch problems

JET's optimization analysis follows the inferred call graph and reports potential
performance pitfalls. **Runtime dispatch** means that selecting a method still
depends on information available during execution. For Bibliography, a report
inside the export path can suggest which call to inspect. Diagnostic counts are
not time measurements, and clearing a warning does not establish a speedup.
See [JET's optimization analysis](https://github.com/aviatesk/JET.jl/blob/master/docs/src/optanalysis.md).

### Cthulhu: inspect the compiler's view interactively

Cthulhu lets you descend through inferred code and inspect where type information
becomes less precise. It is useful when a report points into several layers of
calls and you need to understand how the uncertainty arose. The displayed types
describe the compiler's analysis, not a frequency measured while exporting.
See [Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl).

### SnoopCompile: investigate compilation work

SnoopCompile helps examine inference and the calls that trigger it. **Inference**
is the compiler's analysis of possible types; it contributes to preparing
specialized code. For a slow first Bibliography export, inspect this work
separately from the warm export benchmark. Inference timings do not represent
the complete startup interval or all later execution costs. See
[SnoopCompile's inference tutorial](https://juliadebug.github.io/SnoopCompile.jl/dev/tutorials/snoop_inference_analysis/).

### AllocCheck: inspect possible allocation paths

AllocCheck inspects generated LLVM code for possible allocation and dispatch.
It can help investigate a path intended to avoid allocation, including branches
that a small measured fixture might not exercise. Its exception-path policy
matters and its entry wrapper has overhead. Read a finding as a possible code
path, then measure the relevant Bibliography input; it is not an allocation byte
counter. See [AllocCheck](https://github.com/JuliaLang/AllocCheck.jl).

### Precompilation tools and package quality

PrecompileTools and PackageCompiler change the artifact/startup tradeoff. Compare
cold imports, first invocation, steady-state performance, build cost and artifact
size separately. Aqua and property-testing tools remain quality/correctness
checks, not performance profilers.

For example, Aqua checks issues such as ambiguous methods and unused type
parameters. An ambiguity means Julia may lack one most-specific applicable
method for some call. This is valuable package-quality evidence, but an Aqua
pass does not establish an export latency or memory budget. See
[Aqua's checks](https://juliatesting.github.io/Aqua.jl/dev/test_all/).

## Linux native tools

Native tools can inspect the Julia process and code from its C, C++, Fortran or
other compiled dependencies. Their units matter: instruction counts measure
executed instructions, cache misses concern memory accesses that were not served
by a particular cache, and heap profiles concern allocated or retained memory.
None is a direct substitute for elapsed seconds. Start with the suspected cause
and select the matching evidence, rather than collecting every counter.

`native_tool_plan` prepares argument vectors for Memcheck, Callgrind, Cachegrind,
Massif, heaptrack, perf and VTune. It checks local executable presence without
starting a process or installing anything. These are command plans; execution,
artifact import and causal diagnosis are not qualified adapters yet.

This plan example assumes you supplied `native_case.jl`, a prepared `perf`
project and a suppression file matching your Julia build. It does not execute
that workload:

```julia
using PerfChecker
plan = native_tool_plan(:memcheck, "native_case.jl";
    project="perf", output="results/memcheck",
    suppressions="contrib/valgrind-julia.supp")
```

Valgrind needs `--smc-check=all-non-file` for Julia's JIT. The plan includes child
process tracing and per-process artifact names. Match suppression files to the
runtime. Some investigations need Julia built with memory pools disabled; some
CPU targets are unsupported. A zero exit is insufficient without the workload
oracle and reviewed diagnostics. See [Julia's Valgrind guidance](https://docs.julialang.org/en/v1/devdocs/valgrind/).

### Memcheck: invalid memory operations and leaks

Memcheck looks for invalid reads or writes, use of uninitialized values and
incorrect memory deallocation. These are correctness diagnostics, not speed
scores. For a Julia workload calling a native library, inspect the reported
stack and allocation origin to identify which layer owns the memory. Running
under Memcheck changes execution cost substantially; use an ordinary benchmark
for the final performance comparison.

Its leak report distinguishes **definitely lost** blocks, for which it cannot
find a pointer, from **still reachable** blocks, for which a pointer remains.
Reachable memory can include intentionally retained runtime state. Bytes and
block counts describe different aspects of that report; neither equals
Bibliography's per-export Julia allocation count. Review leak categories,
suppressions and the workload's lifetime together. See the
[Memcheck manual](https://valgrind.org/docs/manual/mc-manual.html).

### Callgrind: instruction cost along a call graph

Callgrind records instruction execution and calling relationships. **Self cost**
belongs to a function itself; **inclusive cost** includes its callees. A large
inclusive cost at a Bibliography entry point suggests following its calls to
find where the work occurs. Do not add that total to the same work shown under
its children. A call count describes calls, whereas an instruction count
describes executed machine instructions.

Fewer instructions can suggest less work, but instructions have different costs
and memory stalls also matter. Callgrind does not turn an instruction count into
the native elapsed time of an export. Confirm an improvement with the same
uninstrumented workload. See the
[Callgrind manual](https://valgrind.org/docs/manual/cl-manual.html).

### Cachegrind: instructions and optional simulated caches

Cachegrind counts instructions and can simulate caches and branch prediction.
A **cache miss** means an access was not served by the selected simulated cache;
a **branch misprediction** means a simulated prediction chose the wrong branch.
These can help investigate access patterns or conditional code. Read each
counter's label and denominator before comparing miss rates.

Cache and branch simulation are disabled by default in current versions and do
not faithfully model modern processors. Record the tool version and enabled
simulation options. These results can motivate a Bibliography implementation
experiment, but they are not measurements of the current CPU's exact cache
behavior or a substitute for elapsed time. See the
[Cachegrind manual](https://valgrind.org/docs/manual/cg-manual.html).

### Massif and heaptrack: native heap growth

Massif samples heap usage and attributes it to allocation paths. A **peak** is
the largest recorded usage during the observed execution; an endpoint is usage
at its end. Neither is the cumulative volume allocated over every export. Read
the horizontal axis too: Massif's time axis can represent instructions,
milliseconds or allocated bytes depending on configuration. Its default heap
view is not all process RAM. See the
[Massif manual](https://valgrind.org/docs/manual/ms-manual.html).

heaptrack records native allocation stacks and helps separate temporary
allocation activity from retained memory. Repeating the same Bibliography
operation can help reveal whether a native dependency retains more memory each
time, but growth alone does not establish a leak: caches and allocator capacity
also matter. Neither tool replaces analysis of which Julia objects remain
reachable. See [heaptrack](https://github.com/KDE/heaptrack).

### Hardware counters: events on the actual processor

perf, LIKWID and PAPI can supply hardware/scheduler evidence where the kernel,
hardware and permissions support it. Counter multiplexing and affinity must be
recorded; unavailable counters must not become zero values. The [LIKWID wrapper](https://juliaperf.github.io/LIKWID.jl/stable/)
documents its topology and counter facilities.

A **cycle** is a processor clock cycle; an **instruction** is an executed
machine instruction. Their ratio, instructions per cycle, describes execution
behavior under that counter configuration, not useful Bibliography exports per
second. **Multiplexing** means the tool alternates limited hardware counters
between requested events and may scale their totals. Compare compatible event
definitions and report the measured interval; a missing or unsupported event
is not evidence that it never occurred.

## Windows, traces and instrumented builds

A trace records events over time: for example, a thread becoming runnable,
waiting for I/O, or returning from a system operation. This timeline helps
investigate why a Julia operation took a long time despite little visible CPU
work. A thread that is ready to run can still wait for the operating system to
schedule it. Attribute events to the measured worker before blaming the package.

WPR records ETW traces and WPA analyzes them: useful for scheduling, I/O and system
activity around Julia and its native dependencies. This is a separate trace path,
not a Julia allocation collector. VTune is another optional CPU analysis route.
See the [Windows Performance Toolkit](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/).

Julia exposes profiler build support for Tracy and VTune timing zones. Its
DTrace/bpftrace probes provide another event-level view. Probe and zone coverage
depends on the actual build. See [external profiler support](https://docs.julialang.org/en/v1/devdocs/external_profilers/)
and [runtime probes](https://docs.julialang.org/en/v1/devdocs/probes/).

Sanitizers require compatible instrumented runtime/library builds and diagnose
memory errors or races. Their timing and memory overhead cannot be treated as
unmodified production performance. See [Julia sanitizer support](https://docs.julialang.org/en/v1/devdocs/sanitizers/).

## GPU, distributed and foreign runtimes

For CUDA, synchronize before comparing completed operation costs and separate
host/device transfer from kernels. Nsight Systems investigates timelines; Nsight
Compute investigates individual kernels. See [CUDA.jl profiling](https://cuda.juliagpu.org/stable/development/profiling/)
and [Nsight Systems](https://docs.nvidia.com/nsight-systems/UserGuide/index.html).

AMDGPU/rocprof, oneAPI/VTune, MPI/Dagger traces, NPU execution providers and device
energy counters remain environment-specific integration candidates in the
catalogue. Native dependency fingerprints, actual devices, transfer boundaries,
rank/process identities, synchronization and fallback detection are required
before interpreting these measurements. Mac tooling stays inventoried; no Mac
validation is claimed.

## Qualification experiment

Before calling a native adapter supported, run four controls: a healthy workload,
a known native allocation/leak, a known CPU hotspot, and a child-process workload.
Check symbol/source attribution, nonzero diagnostics for injected defects,
bounded cancellation, artifact completeness and matching dependency identities.
Then run unchanged controls without the profiler to measure its perturbation.
Windows and Linux need their own evidence; WSL results describe the Linux guest.
