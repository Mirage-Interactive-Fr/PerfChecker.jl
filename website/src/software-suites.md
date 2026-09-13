# Define a suite

A `SoftwareSuite` names the packages, workloads, collectors and versions to measure — a Julia configuration object, not a package to install.

## Three objects

- `FeatureSpec` — one workload file, collector and settings.
- `PackageSuite` — a target package, its worker environment and its features.
- `SoftwareSuite` — the participating package suites and comparisons.

## Load and inspect

From `examples/bibliography/` in a prepared checkout:

```julia
using PerfChecker, BenchmarkTools, Chairmarks
suite = load_software_suite("suite.jl")
plan = plan_suite(suite; profile = :quick)
print_suite_plan(plan)
```

Planning lists checks. It does not measure anything.

## Select and run

```julia
selected = filter_suite_plan(plan;
    packages = "Bibliography", features = :export_bibtex, backends = [:benchmark])
print_suite_plan(selected)

report_directory = mktempdir(abspath("results"); prefix = "export-", cleanup = false)
result = run_suite_repl(selected; reports = report_directory, strict = false,
    overrides = Dict{Symbol,Any}(:threads => 1, :samples => 50, :evals => 1, :seconds => 0.5))
```

A new directory preserves earlier measurements. Read `suite-report.md` first.

## Workload lifecycle

```text
prepare input → measure operation → check result → release resources
```

- `perf_setup()` prepares state.
- `perf_workload(state)` is the measured operation.
- `perf_oracle(state, result)` checks the actual result. Add it — a benchmark without an oracle is `not_checked`.
- `perf_synchronize(state, result)` waits for async work, **inside** the measurement.
- `perf_cleanup(state)` releases resources.

Preparation and verification are outside the timed operation. The default `state_policy = :fresh` gives each operation new state; fresh timing cases require `evals = 1`. Use `:reuse` only when repeated mutation on one state is the intended workload.

## Why the worker has its own environment

The controller holds PerfChecker and the interface you use. `worker_environment` is a small seed project for the measurement worker — collectors and workload dependencies only.

- This keeps Oxygen, Pluto or plotting compatibility from constraining a historical target.
- A worker does not import PerfChecker unless PerfChecker is the target.
- Native item execution needs a prepared **test** environment instead.

Do not substitute one environment for the other.

## Profiles

- `:quick` — current local sources.
- `:ci` — current sources plus compatibility boundaries.
- `:historical` — known releases from the package suite.
- `:release` — released targets only.

Add candidates with `SuiteCandidate` and references with `ComparisonPolicy`. See [Comparison options](reference/comparisons.md).


## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Bibliography export samples grouped by nine tagged versions" caption="The same export workload can be repeated across a version matrix. Each dot is one recorded timing. The quick selection above measures just the pinned development revision; it does not produce this nine-version history." />
```

## Next

[Compare two versions](tutorials/comparisons.md).

```@raw html
<a id="Software-suites"></a>
<a id="Open-the-supplied-suite"></a>
<a id="Understand-its-workload-definition"></a>
<a id="Select-one-workload-and-one-collector"></a>
<a id="Run-and-save"></a>
<a id="Adapt-the-suite-to-your-package"></a>
<a id="Add-versions-and-comparisons"></a>
<a id="Continue-with-the-same-experiment"></a>
```
