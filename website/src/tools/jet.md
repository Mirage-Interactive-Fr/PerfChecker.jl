# JET

Inspect inference and dispatch separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl analyzers`. Then start Julia with `julia --project=.controller/analyzers` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:jet], reports="results/heap-jet")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: JET 0.12.1 completed with <strong>0 findings</strong> and a passing oracle.</p>
```

Zero findings apply to this prepared-state specialization, not every possible input.

::: details Follow a finding through a change

## Follow a finding through a change


**Same sales records, same revenue calculation, different element types.**
This example was executed on Linux with PerfChecker 1.1.0, JET 0.12.3, BenchmarkTools 1.7.0 and Julia 1.13.1. The two implementations ran on one machine; they are not package releases or an inter-machine comparison.

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

**Yes, for this recorded workload.** The four-metric figure uses a separate
BenchmarkTools capture of 20 warmed reductions per implementation (40 real samples total), retaining
the actual GC-time samples. JET does not run inside the benchmark. The original
diagnostic record remains separately downloadable; its older timing summaries
are not mixed into this figure.

```@raw html
<NormalizedMeasurements source="/examples/jet-dispatch/measurements.json" html="/examples/jet-dispatch/measurements.html" package-name="JET tutorial · implementations" />
```

Four metrics share one normalized ratio axis, referenced to the `dynamic`
implementation. Inspect an implementation and metric for its original minimum
and unit. **Implementation** labels are alternatives
in this example, not published package versions. Parsing, collection construction and oracle checks are outside
the timed boundary. These local measurements illustrate a cost, not a universal
speedup guarantee.

### Complete operation, scenario contract and commands

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

### Reproduce the analysis, measurements and interactive export

Save these files in one directory. The runner checks both controls and saves
the actual findings, all samples, run IDs and source/environment fingerprints.
Existing output directories are never overwritten.

```@raw html
<p><a href="../examples/jet-dispatch/Project.toml" download="Project.toml">Project.toml</a> · <a href="../examples/jet-dispatch/Manifest.toml" download="Manifest.toml">Manifest.toml (recorded Julia 1.13.1 environment)</a> · <a href="../examples/jet-dispatch/cases.jl" download="cases.jl">cases.jl</a> · <a href="../examples/jet-dispatch/run.jl" download="run.jl">run.jl</a> · <a href="../examples/jet-dispatch/summary.json" download="summary.json">Recorded findings and samples</a></p>
```

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. run.jl results
```

The pinned tools require Julia 1.12 or newer; use Julia 1.13.1 with the recorded
Manifest. Analysis and measurement need only the downloaded environment. The
optional interactive export uses **PerfCheckerMakie 1.0.4** and
WGLMakie in a rendering environment; it reads the saved evidence without rerunning
JET or the workload:

Start Julia with `julia --project=render-environment` and prepare that separate
environment once, using the exact renderer source reviewed for this documentation:

```julia
using Pkg
Pkg.add(name = "PerfChecker", version = "1.1.0")
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    subdir = "packages/PerfCheckerMakie", rev = "06b2b4d9b54c6c1c5c84ba346ff2317f896a20d9"))
Pkg.add(name = "WGLMakie", version = "0.13")
Pkg.add(name = "JSON", version = "1")
```

```@raw html
<p><a href="../examples/jet-dispatch/render.jl" download="render.jl">Download render.jl</a></p>
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
[shared scenarios](scenarios.md) for the same lifecycle in the other
interfaces, and [Oxygen](../real-packages/oxygen.md) for a larger application where
some dynamic dispatch may be intentional.

:::
