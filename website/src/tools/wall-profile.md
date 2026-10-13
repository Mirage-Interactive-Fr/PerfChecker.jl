# Wall profile

Find task stacks that explain elapsed time, including waiting. Requires Julia 1.12 or later. Width is task-sample weight, separate from CPU samples.

From `examples/bibliography`, prepare the core controller with `julia setup.jl core`, then run:

```sh
julia --startup-file=no --project=.controller/core run.jl wall_profile Bibliography export_bibtex
```

The interactive output is the existing capture at source revision `575ec81`, with original data and saved HTML available from the plot. It is a single-revision diagnostic.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/wall.json" html="/examples/bibliography/profiles/wall.html" title="Recorded Bibliography wall profile" kind="wall_flamegraph" />
```

Inspect a frame for its full stack and recorded weight; zoom and Fit explore the same capture. This profile alone cannot establish a version improvement.
