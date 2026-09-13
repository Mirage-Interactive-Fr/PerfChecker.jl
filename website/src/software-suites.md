# Software suites

A `SoftwareSuite` specifies the packages, workloads, collectors and versions
to measure. For example, a Bibliography suite can measure import and export
with BenchmarkTools on several releases, using the same inputs throughout.

The example below loads that suite, inspects its plan and saves a report.
[Suites and comparisons](suites-and-comparisons.md) introduces the terminology;
for existing TestItems, see [your first result](guide/first-check.md).

A suite is a Julia configuration object, not another package to install.
You can write it by hand or distribute it with a package. This chapter first
uses the supplied configuration, then builds a smaller suite from its parts.

## Open the supplied suite

First [prepare Bibliography](tutorials/bibliography.md#Prepare-the-example-once).
From `examples/bibliography/`, start the prepared controller:

```sh
julia --startup-file=no --project=.controller/core
```

Then load its suite and inspect the plan:

```julia
using PerfChecker, BenchmarkTools, Chairmarks
suite = load_software_suite("suite.jl")
plan = plan_suite(suite; profile=:quick)
print_suite_plan(plan)
```

The supplied `suite.jl` exposes `build_suite()`, which returns a `SoftwareSuite`.
Loading it constructs the configuration. Planning lists the checks; it does not
time a workload. The quick example lists seven workloads with five collectors
each. Rows marked unavailable give the reason a check cannot run.

## Understand its workload definition

Each package contains ordinary Julia workload files. For export, `perf_setup()`
prepares a bibliography, and `perf_workload(bibliography)` exports it. The
operation uses the same fixed input for each version.

```text
prepare input → measure export → check result → release resources
```

For operation benchmarks, preparation and verification are outside the timed
operation. Optional `perf_synchronize(state, result)` waits for asynchronous work
inside the measurement. `perf_cleanup(state)` releases resources afterwards.
The default `state_policy=:fresh` supplies fresh state to each operation;
fresh timing cases require `evals=1`. Use `:reuse` only when repeated operations
on the same state describe the experiment you intend.

The pinned Bibliography export file supplies preparation and workload callbacks.
It has no correctness oracle. Its successful benchmark therefore means
**executed**, not **validated**. The separate [native items](test-items.md)
include assertions. When writing your own workload, add
`perf_oracle(state, result)` to check the actual result of the measured operation.
For example, an export oracle can check that the output still contains the
expected citation key and title.

## Select one workload and one collector

Continue in the same Julia session:

```julia
selected = filter_suite_plan(plan;
    packages=["Bibliography"], features=["export_bibtex"],
    backends=[:benchmark])
print_suite_plan(selected)
```

This leaves one row for the pinned development source. Change `backends` to
`[:profile_alloc]` to locate allocations, or select several collectors explicitly.
The workload stays the same. See the [check catalog](reference/checks.md) for
what each collector measures and how to interpret it.

## Run and save

```julia
mkpath("results")
report_directory = mktempdir(abspath("results"); prefix="export-", cleanup=false)
result = run_suite_repl(selected; reports=report_directory, strict=false,
    overrides=Dict{Symbol,Any}(:threads=>1, :samples=>50, :evals=>1, :seconds=>0.5))
println("Reports: ", report_directory)
```

The directory is output. Choosing a new one preserves previous measurements.
The report includes the selected source, environment and collector settings,
alongside execution and comparison outcomes. Read `suite-report.md` first, then
open a bundle from its `bundles/` directory in the
[plotting interface](interfaces/visualization.md#Build-a-plot-from-a-saved-run).
The [complete walkthrough](tutorials/bibliography.md#Read-the-report-before-interpreting-the-graph)
explains the report files and shows actual output.

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Bibliography export samples grouped by nine tagged versions" caption="The same export workload can be repeated across a version matrix. Each dot is one recorded timing. The quick selection above measures just the pinned development revision; it does not produce this nine-version history." />
```

## Adapt the suite to your package

There are three objects to connect:

| Object | Describes | Bibliography example |
| --- | --- | --- |
| `FeatureSpec` | One workload file, collector and measurement settings | `export_bibtex` using BenchmarkTools |
| `PackageSuite` | The target package, worker environment and available features | Bibliography with pinned BibInternal/BibParser dependencies |
| `SoftwareSuite` | The participating package suites and comparisons | Bibliography, BibParser and BibInternal together |

For a concrete `FeatureSpec` using the already prepared example files:

```julia
export_feature = FeatureSpec(:export_bibtex;
    backend=:benchmark,
    entrypoint=abspath(".sources/Bibliography/perf/features/export_bibtex.jl"),
    comparison_key="bibliography-export/v1",
    options=Dict(:samples=>50, :evals=>1, :seconds=>0.5))
```

This creates a definition; it does not add it to `suite` or execute it. Continue
in the same session to assemble a suite containing just this export check.
Reuse the package paths already prepared by the example:

```julia
bibliography = only(filter(package -> package.package == "Bibliography", suite.packages))
export_package = PackageSuite("Bibliography";
    source=bibliography.source,
    worker_environment=worker_environment(bibliography),
    dev_sources=bibliography.dev_sources,
    versions=VersionNumber[],
    include_dev=true,
    features=[export_feature])
export_suite = SoftwareSuite(:bibliography_export, [export_package];
    description="Measure export of one prepared bibliography")
export_plan = plan_suite(export_suite; profile=:quick)
print_suite_plan(export_plan)
```

The plan contains one check against the local Bibliography source. The empty
`versions` list adds no release targets; `include_dev=true` includes the local
source. Use `export_plan` in place of `selected` in [Run and save](#Run-and-save)
to execute it. Defining the objects above does not start a worker.

For your own package, replace the package name, source path and workload file,
then give the worker a project containing that workload's dependencies. A suite
file should expose `build_suite()` returning the resulting `SoftwareSuite`, so
`load_software_suite` and the interfaces can open it. The supplied `suite.jl`
shows this entry point. Keep your adapted files outside `.sources/`: the example
setup verifies those pinned checkouts and refuses local changes.

`write_software_suite_template` and the CLI `init` command can write starter
files if useful. They are optional file generators; they do not enable an
otherwise unavailable PerfChecker feature.

`FeatureSpec.id` identifies a concrete check. Set the same `workload` on several
features to group timing, allocation and profile collectors under one operation
in the interfaces. Keep `comparison_key` stable only while the inputs, output
semantics and measurement procedure remain comparable.

## Why the worker has its own environment

The controller contains PerfChecker and whichever interface you use.
`PackageSuite.worker_environment` is a small seed project for the measurement
worker, containing its collectors and workload dependencies. PerfChecker prepares
the selected target and dependency pins there before measuring.

Separating these environments prevents Oxygen, Pluto or plotting compatibility
from constraining a historical target. A suite worker does not import PerfChecker
unless PerfChecker itself is the target under test. Native TestItemRunner execution
has a different requirement: it uses a prepared test environment, including the
test runner integration. Do not substitute one environment for the other.

The supplied Bibliography setup and suite already declare these paths. This
preparation belongs to the example, not to installation of the PerfChecker package.
For distributing reusable workload code with its own dependencies, expose the
suite from an ordinary Julia package that users can install with Pkg.

## Add versions and comparisons

| Profile | Selection |
| --- | --- |
| `:quick` | Current local sources |
| `:ci` | Current sources and representative compatibility boundaries |
| `:historical` | Known releases selected by the package suite |
| `:release` | Released targets, excluding an untagged development tree |

`FeatureVariant` and the `since`, `until`, `excluded` fields describe package
versions a workload supports. The corresponding `julia_since`, `julia_until`
and `julia_excluded` fields constrain the runtime separately. Unsupported pairs
remain visible in the plan. `release_pins` fixes historical dependency versions;
`dev_sources` chooses coherent local dependency sources.

`SuiteCandidate` selects a named Git revision. `ComparisonPolicy` selects its
reference and aggregation. The [comparison reference](reference/comparisons.md)
documents these APIs; [compare versions and revisions](tutorials/comparisons.md)
uses them in a complete experiment. You can also run the supplied
[nine-version history](tutorials/bibliography.md#Compare-the-package-history).
A comparison needs explicit limits to act as a performance gate; a plot alone
does not decide whether a change is acceptable.

## Continue with the same experiment

Next, [compare two revisions](tutorials/comparisons.md) of the export function.
We will keep the dependency versions fixed so the comparison focuses on the
source change. Constructor options are listed in the [API reference](reference/api.md).
