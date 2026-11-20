# Architecture

PerfChecker keeps experiment control, measured code and presentation separate. A Julia call, VS Code command, Web job or Pluto notebook prepares the same suite plan. The controller selects targets and collectors; isolated workers execute them; interfaces read the saved result.

## Controller and workers

Core owns discovery, plans, worker setup, measurement definitions, comparisons and reports. A plan names a package version or immutable source revision, a workload, its collector and its environment. Constructing or filtering a plan starts no measurement.

[Malt](https://github.com/JuliaPluto/Malt.jl) supplies isolated Julia workers for checks. Target dependencies resolve in their worker project rather than in the editor or plotting environment. A worker's Julia version, source, dependency manifests and thread settings stay attached to its result. Remote execution also needs an explicit controller and worker lifecycle; see [Scenarios](tools/scenarios.md).

## Prepare, operate, verify

A feature describes three steps:

1. **Prepare** creates the input and any state excluded from measurement.
2. **Operate** performs the one operation the collector observes.
3. **Verify** checks the answer against an independent oracle, outside measurement.

Fresh-state features prepare each evaluation independently. Reused state must be declared deliberately, for example for a continuous sampling profile of a read-only operation. An existing test item instead measures its whole item, including setup and assertions. Those are different measurement boundaries.

## Saved bundles and comparisons

A run bundle contains observations, measurement definitions, source/environment provenance, diagnostics and artifacts. A completed collector, a passing oracle and a passing regression budget are separate outcomes. Comparisons require compatible definitions and conditions; a zero or unavailable reference cannot acquire a meaningful percentage by plotting it.

Interfaces exchange these files instead of sharing mutable controller state. Replaying a bundle or rendering its JSON runs no workload. [Saved results](tools/results.md) explains inspection and export.

## Optional tools and interfaces

Core has no required plotting, Web or notebook application. `PerfCheckerMakie`, `PerfCheckerWeb`, `PerfCheckerPluto` and `PerfCheckerTachikoma` own their interfaces and dependencies. The VS Code client calls a Julia controller. Each companion has its own package identity and compatibility bounds.

Small integrations such as BenchmarkTools, Chairmarks, TestItemRunner, UnicodePlots and Documenter use Julia extensions. Diagnostic adapters load tools such as JET or Aqua in prepared target environments. Hardware-counter companions require their own workers and native prerequisites. Missing tools produce explicit unavailable evidence; importing Core does not certify a native backend.

See the [Public API](reference/public-api.md) for supported entry points and [Contributing](contributing/index.md) for changing this code or its examples.
