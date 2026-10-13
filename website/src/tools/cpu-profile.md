# CPU profile

Find frequently sampled call paths. Width counts CPU samples, including descendants; it is neither call count nor chronology.

From `examples/bibliography`, prepare the core controller with `julia setup.jl core`, then run:

```sh
julia --startup-file=no --project=.controller/core run.jl profile Bibliography export_bibtex
```

The interactive output is the existing capture at source revision `575ec81`, with original data and saved HTML available from the plot. It is a single-revision diagnostic.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/cpu.json" html="/examples/bibliography/profiles/cpu.html" title="Recorded Bibliography cpu profile" kind="cpu_flamegraph" />
```

Inspect a frame for its full stack and recorded weight; zoom and Fit explore the same capture. This profile alone cannot establish a version improvement.
