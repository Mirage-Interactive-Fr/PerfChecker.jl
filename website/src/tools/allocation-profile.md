# Allocation profile

Find allocation sites by sampled stacks and types. Byte weight ranks volume; event counts rank frequency. Julia-managed sampling excludes native allocations.

From `examples/bibliography`, prepare the core controller with `julia setup.jl core`, then run:

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

The interactive output is the existing capture at source revision `575ec81`, with original data and saved HTML available from the plot. It is a single-revision diagnostic.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/allocations.json" html="/examples/bibliography/profiles/allocations.html" title="Recorded Bibliography allocation profile" kind="allocation_flamegraph" />
```

Inspect a frame for its full stack and recorded weight; zoom and Fit explore the same capture. This profile alone cannot establish a version improvement.

::: details Empty captures and totals

Read `qualification["allocation_profile"]`: `zero_allocations` means independently measured byte/count totals were both zero; `no_samples`, `outside_target_scope` and `unattributed_samples` mean missing attribution, not zero cost. Bytes and allocation count come from two independently prepared evaluations. Legacy profile views distribute those totals over retained stacks; scenario profiles keep raw sampled weights. CSV caches keep this qualification in a matching `.csv.allocation-profile.toml` sidecar.

:::
