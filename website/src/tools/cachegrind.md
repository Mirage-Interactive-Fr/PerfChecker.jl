# Valgrind Cachegrind

Inspect simulated instruction and cache activity for a real workload. A plan checks availability and describes a command; it does not execute it.

From `examples/kitchen-sink` in the source checkout, run `julia setup-linux.jl` on Linux or WSL. Start Julia with `julia --project=.controller/linux` to plan the supplied `native-workload.jl`:

```julia
using PerfChecker
plan = native_tool_plan(:cachegrind, "native-workload.jl";
    project=dirname(Base.active_project()), output="exports/cachegrind")
display(plan["availability"])
display(plan["arguments"])
```

From the same directory, prepare the native support files and run only this tool:

```sh
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --startup-file=no --project=.controller/linux native-run.jl datastructures cachegrind
```

```@raw html
<p>The existing <a href="../examples/real-packages/datastructures-native/summary.json">Linux/Julia 1.13.0 receipt</a> uses 512 events and three lifecycles, including startup. Recorded status: <strong><code>completed</code></strong>, exit <strong>0</strong>, <code>cachegrind.1689</code> and log. The workload oracle passed.</p>
```

Cache simulation is not a hardware-counter capture. Keep its instrumentation scope attached to the result.

```@raw html
<p><a href="../examples/real-packages/oxygen-native/summary.json">Oxygen has separate per-tool receipts</a>; inspect its completion/timeout states instead of transferring a container-workload verdict.
</p>
```