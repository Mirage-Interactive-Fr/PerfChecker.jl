# Valgrind Massif

Inspect native heap growth for a real workload. A plan checks availability and describes a command; it does not execute it.

From `examples/kitchen-sink` in the source checkout, run `julia setup-linux.jl` on Linux or WSL. Start Julia with `julia --project=.controller/linux` to plan the supplied `native-workload.jl`:

```julia
using PerfChecker
plan = native_tool_plan(:massif, "native-workload.jl";
    project=dirname(Base.active_project()), output="exports/massif")
display(plan["availability"])
display(plan["arguments"])
```

From the same directory, prepare the native support files and run only this tool:

```sh
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --startup-file=no --project=.controller/linux native-run.jl datastructures massif
```

```@raw html
<p>The existing <a href="../examples/real-packages/datastructures-native/summary.json">Linux/Julia 1.13.0 receipt</a> uses 512 events and three lifecycles, including startup. Recorded status: <strong><code>completed</code></strong>, exit <strong>0</strong>, <code>massif.1685</code> and log. The workload oracle passed.</p>
```

The native heap timeline covers startup as well as the workload. It is distinct from Julia allocation totals.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-native/massif-1.plot.json" html="/examples/real-packages/datastructures-native/massif-1.html" title="Observed Massif native heap timeline" />
```

```@raw html
<p><a href="../examples/real-packages/oxygen-native/summary.json">Oxygen has separate per-tool receipts</a>; inspect its completion/timeout states instead of transferring a container-workload verdict.
</p>
```