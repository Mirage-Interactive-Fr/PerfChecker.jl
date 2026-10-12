```@raw html
<a id="Julia-and-native-performance-tools"></a>
```

# Julia and native profiling

Locate where an operation spends time.

Use Julia's tools first. Use a native profiler to inspect a C/C++/Fortran dependency or activity outside Julia.

```@raw html
<a id="Choose-an-instrument-from-the-question"></a>
```

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

Allocation profiles can complete without retained source sites. Check their
explicit capture status, measured totals and attribution scope before selecting
a hotspot; unsampled or unattributed allocations are not zero allocations.
See the [allocation collector contract](reference/checks.md#Profiles).

```@raw html
<a id="Cthulhu:-inspect-the-compiler's-view-interactively"></a>
```

## Static analysis and compilation

These inspect code, not measured cost. Treat a diagnostic as a hypothesis and confirm practical cost with a benchmark.

| Tool | Question | Result to inspect |
| --- | --- | --- |
| JET | Where does inference lose a type? | [Before/after dispatch findings below](#JET:-possible-inference-and-dispatch-problems). |
| AllocCheck | Which specialized code can allocate? | A reported allocation and its call path. |
| SnoopCompile | How much inference happened in the first lifecycle? | An inference timing tree. |
| Aqua | Which package-quality checks failed? | The failed test and implicated methods. |
| Cthulhu | Which inferred type needs closer inspection? | An interactive compiler view; no recorded session is shown here. |
| PrecompileTools / PackageCompiler | Does startup improve after precompilation? | Separately measured import, first call, steady state and build cost. |

```@raw html
<a id="JET:-possible-inference-and-dispatch-problems"></a>
```

## JET: find a dispatch problem, then check the change

**Same sales records, same revenue calculation, different element types.**
This example was executed with PerfChecker 1.1.0, JET 0.12.3 and Julia 1.13.1.

### Before: the collection hides the row type

```julia
rows = Any[records(4096)...] # Vector{Any}, containing validated Sale values
# Inside net_revenue(rows), cases.jl:14:
total += row.quantity * row.unit_price * (1.0 - row.discount)
```

Actual JET finding at that line:

```text
RuntimeDispatchReport(runtime dispatch detected: (%36::Any).quantity::Any)
```

`row` is inferred as `Any`. JET also reported the other field accesses and
arithmetic at the same line: **six runtime-dispatch findings** in total.

### After: keep the validated record type

```julia
rows = records(4096) # Vector{Sale}; net_revenue itself is unchanged
```

Actual result from the second isolated JET worker:

```text
status: complete
correctness: passed
findings: []
```

| Recorded check | `dynamic`: `Vector{Any}` | `typed`: `Vector{Sale}` |
| --- | --- | --- |
| Revenue oracle | 129,536.0 — passed | 129,536.0 — passed |
| JET runtime-dispatch findings | 6 | 0 |
| Scope | This operation and state type | This operation and state type |

Retaining the type lets Julia infer the fields and arithmetic inside the loop.
A return annotation would not repair the lost element information. Zero findings
here applies to this specialization; it is not a proof that every input or the
whole application is bug-free.

### Did this diagnostic correspond to a measured cost?

**Yes, for this recorded workload.** Separate BenchmarkTools workers measured
20 warmed reductions per implementation. JET did not run inside the benchmark.

| Median per reduction | `dynamic` | `typed` |
| --- | --- | --- |
| Wall time | 870.838 µs | 3.798 µs |
| Allocated bytes | 720,896 B | 0 B |
| Allocation count | 32,768 | 0 |

```@raw html
<InteractiveRecordedPlot source="/examples/jet-dispatch/measurements.json" html="/examples/jet-dispatch/measurements.html" title="Same revenue calculation, different element types" kind="observation_series" />
```

Select a panel, inspect individual timing samples, or compare the allocation
bars. **Implementation** labels are alternatives in this example, not published
package versions. Parsing, collection construction and oracle checks are outside
the timed boundary. These local measurements illustrate a cost, not a universal
speedup guarantee.

::: details The complete operation, scenario contract and commands

```julia
struct Sale
    quantity::Int
    unit_price::Float64
    discount::Float64
end

function net_revenue(rows)
    total = 0.0
    for row in rows
        total += row.quantity * row.unit_price * (1.0 - row.discount)
    end
    return total
end
```

The factories in `cases.jl` prepare 4,096 deterministic records. An independent,
fixed oracle checks the result against 129,536.0. Each measurement sample receives
fresh state and exactly one evaluation. Diagnostic and measurement workers are
separate; both must pass their oracle.

```julia
using PerfChecker
catalog = ScenarioCatalog(pwd(), [
    ScenarioSpec("net-revenue"; source = "cases.jl",
        factory = "SalesCases.$implementation", implementation,
        parameters = Dict("rows" => 4096), collectors = [:benchmark])
    for implementation in ("dynamic", "typed")
])
diagnosis = diagnose(catalog; project = pwd(), tools = [:jet],
    timeout = 180, threads = 1)
bundles = run_scenarios(catalog; project = pwd(), samples = 20,
    timeout = 180, threads = 1, reports = "results/measurements")
all(bundle_passed, bundles)
```

PerfChecker calls `JET.report_opt` on the operation specialized for its prepared
state type. It does not install an absent analyzer automatically. For genuinely
heterogeneous input, choose validation, conversion or a function barrier that
fits the data model instead of assuming every collection can be homogeneous.

:::

::: details Reproduce the analysis, measurements and interactive export

Save these files in one directory. The runner checks both controls and saves
the actual findings, all samples, run IDs and source/environment fingerprints.
Existing output directories are never overwritten.

```@raw html
<p><a href="examples/jet-dispatch/Project.toml" download="Project.toml">Project.toml</a> · <a href="examples/jet-dispatch/Manifest.toml" download="Manifest.toml">Manifest.toml (recorded Julia 1.13.1 environment)</a> · <a href="examples/jet-dispatch/cases.jl" download="cases.jl">cases.jl</a> · <a href="examples/jet-dispatch/run.jl" download="run.jl">run.jl</a> · <a href="examples/jet-dispatch/summary.json" download="summary.json">Recorded findings and samples</a></p>
```

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. run.jl results
```

The pinned tools require Julia 1.12 or newer; use Julia 1.13.1 with the recorded
Manifest. Analysis and measurement need only the downloaded environment. The
optional interactive export additionally needs **PerfCheckerMakie 1.0.2** and
WGLMakie in a rendering environment; it reads the saved evidence without rerunning
JET or the workload:

Start Julia with `julia --project=render-environment` and prepare that separate
environment once:

```julia
using Pkg
Pkg.add(name = "PerfChecker", version = "1.1.0")
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    subdir = "packages/PerfCheckerMakie", rev = "PerfCheckerMakie-v1.0.2"))
Pkg.add(name = "WGLMakie", version = "0.13")
Pkg.add(name = "JSON", version = "1")
```

```@raw html
<p><a href="examples/jet-dispatch/render.jl" download="render.jl">Download render.jl</a></p>
```

```sh
julia --project=render-environment render.jl results/summary.json exported-figure
```

The recorded run used Linux x86-64, two available CPU cores and one Julia thread.
The measured [operation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/5b3ab2ef5c02a89736f089e2eeba72338c508042/website/src/public/examples/jet-dispatch/cases.jl#L14)
and [runner](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/5b3ab2ef5c02a89736f089e2eeba72338c508042/website/src/public/examples/jet-dispatch/run.jl)
are archived at commit `5b3ab2e`. The downloads have since been formatted;
their parsed Julia code is unchanged, and the diagnostic still points to line 14.
`summary.json` keeps the original measured SHA-256 values and lists the formatted
reproduction hashes separately. Formatting did not trigger a new measurement.

Keep source and tool identities with any new result. See
[shared scenarios](shared-scenarios.md) for the same lifecycle in the other
interfaces, and [Oxygen](real-packages/oxygen.md) for a larger application where
some dynamic dispatch may be intentional.

:::

## Read three other analyzer results

These excerpts come from the saved **Oxygen, 2,048-event** investigation on
Julia 1.13.0 with one Julia thread. They are existing observations, not results
of rerunning the commands below on your machine. Start in the prepared
[Oxygen example directory](real-packages/oxygen.md#First-request-versus-warm-request).

| Tool | Recorded result | What to do next |
| --- | --- | --- |
| AllocCheck | `Vector{Any}` allocation on the `internalrequest` path | Inspect its caller and measured allocation profile. |
| SnoopCompile | 1.055 s inclusive inference, 17 direct children | Compare inference work with first/warm latency. |
| Aqua | Two `recursive_merge` methods are ambiguous at zero arguments | Review the API's empty-input behavior. |

```julia
using PerfChecker
catalog = load_scenario_catalog("oxygen/scenarios.toml")
case = select_scenarios(catalog,
    [Dict("id" => "oxygen-heap", "implementation" => "oxygen")])
```

```@raw html
<a id="AllocCheck:-inspect-possible-allocation-paths"></a>
<a id="SnoopCompile:-investigate-compilation-work"></a>
<a id="Precompilation-tools-and-package-quality"></a>
```

::: tabs

== AllocCheck

```julia
report = diagnose(case; project = ".controller/analyzers", tools = [:alloccheck])
first(report["records"])["findings"][1]["message"]
```

Abbreviated recorded excerpt, AllocCheck **0.2.6**:

```text
Allocation of Vector{Any} in .\boot.jl:649
  …
 [3] vect
 [4] internalrequest
```

Follow the call chain back to `internalrequest`; `boot.jl` is where the array is
created, not necessarily where your application should change. This is a static
allocation path. Use the interactive allocation profiles in the
[Oxygen investigation](real-packages/oxygen.md#5.-Find-the-expensive-call-paths)
to inspect measured allocation sites and a separate benchmark to check any gain.

== SnoopCompile

```julia
report = diagnose(case; project = ".controller/analyzers", tools = [:snoopcompile])
first(report["records"])["findings"][1]["message"]
```

Recorded output, SnoopCompile **3.2.9**:

```text
InferenceTimingNode: 0.000004/1.055385 on Base.Compiler.Timings.ROOT() with 17 direct children
```

The root's inclusive inference time was about **1.055 s** in the first complete
scenario lifecycle. It is not a warm-operation timing or the entire process's
startup time. Compare it with the separately recorded loading, first-lifecycle
and warm-lifecycle observations in the
[Oxygen diagnostics](real-packages/oxygen.md#First-request-versus-warm-request).

== Aqua

```julia
root = dirname(dirname(Base.find_package("Oxygen")))
report = diagnose(ScenarioCatalog(root, ScenarioSpec[]);
    project = ".controller/analyzers", tools = [:aqua])
record = only(report["records"])
(record["status"], record["quality"], record["log_excerpt"])
```

Recorded states and diagnostic excerpt, Aqua **0.8.16**:

```text
status: complete
quality: failed

Ambiguity #1
recursive_merge(x::AbstractDict...) @ Oxygen.Core.Util <local-source>
recursive_merge(x::AbstractVector...) @ Oxygen.Core.Util <local-source>

Possible fix, define
  recursive_merge()
```

Both vararg methods accept a call with no arguments; neither is more specific
for `recursive_merge()`. Review the intended empty-input result before adding a
zero-argument method. Aqua completed, but package quality failed; this finding
does not establish a timing regression or a failure of the measured HTTP route.

:::

```@raw html
<p>Original evidence: <a href="examples/real-packages/oxygen-diagnostics/diagnosis.json" download="oxygen-diagnosis.json">AllocCheck and SnoopCompile reports</a> · <a href="examples/real-packages/oxygen-diagnostics/additional.json" download="oxygen-additional.json">Aqua report</a></p>
```

```@raw html
<a id="Memcheck:-invalid-memory-operations-and-leaks"></a>
<a id="Callgrind:-instruction-cost-along-a-call-graph"></a>
<a id="Cachegrind:-instructions-and-optional-simulated-caches"></a>
<a id="Massif-and-heaptrack:-native-heap-growth"></a>
<a id="Hardware-counters:-events-on-the-actual-processor"></a>
```

## Linux native tools

`native_tool_plan` prepares argument vectors for Memcheck, Callgrind, Cachegrind, Massif, heaptrack, perf and VTune. It checks local executable presence without starting a process.

```julia
using PerfChecker
plan = native_tool_plan(:memcheck, "native_case.jl";
    project = "perf", output = "results/memcheck",
    suppressions = "contrib/valgrind-julia.supp")
```

**An availability result is a useful result too.** These selected fields are
from the recorded Oxygen probes on Linux, Julia 1.13.0, 13 September 2026:

```json
[
  {"tool": "perf", "availability": "not_installed", "executed": false, "correctness": "not_checked"},
  {"tool": "vtune", "availability": "not_installed", "executed": false, "correctness": "not_checked"}
]
```

No profiler ran in these two cases, so there is no cost or correctness result
to interpret. Install the intended tool before requesting its measurement;
do not read missing counters as zero. The
complete saved report also records the tools that did execute and their
individual completion states:

```@raw html
<p><a href="examples/real-packages/oxygen-native/summary.json" download="oxygen-native-report.json">Download the recorded native report</a></p>
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

```@raw html
<a id="GPU,-distributed-and-foreign-runtimes"></a>
```

## GPU, distributed, foreign runtimes

- CUDA: synchronize before comparing completed costs; separate host/device transfer from kernels.
- AMDGPU/rocprof, oneAPI, MPI/Dagger traces and NPU providers remain environment-specific candidates.
- Native dependency fingerprints, actual devices, transfer boundaries, rank identities and fallback detection are required before interpreting these measurements.
- macOS tooling stays inventoried; no Mac validation is claimed.

```@raw html
<a id="Qualification-experiment"></a>
```

## Before calling an adapter supported

Run four controls: a healthy workload, a known native leak, a known CPU hotspot and a child-process workload. Check symbol/source attribution, nonzero diagnostics for injected defects, bounded cancellation, artifact completeness and matching dependency identities. Then rerun unchanged controls without the profiler to measure its perturbation. Windows and Linux need their own evidence.
