# Real package examples

The examples develop the steps introduced in the manual into larger
experiments. Each provides the scripts and saved measurements used by its
figures, plus instructions for the terminal and graphical interfaces.

| Example | Work performed | What the measurements include |
| --- | --- | --- |
| [Bibliography](../tutorials/bibliography.md) | Import, parse and export bibliography entries | The manual's example extended to three related packages and nine releases |
| [DataStructures](datastructures.md) | Construct and use 35 containers, then investigate event processing | 70 separate operations across every 0.19 patch, plus a longer historical comparison |
| [Oxygen](oxygen.md) | Compare seven HTTP features, three application routes and real traffic | Older minor releases and every recent patch; network latency, bytes, packets and throughput have their own figures |

The application workloads share an event stream. It contains a priority, a unique
identifier and a category for every event. A fixed seed reproduces the input;
an independently computed expected answer checks each workload. This lets you
ask whether time is spent processing data or serving the request around it.

## Choose a starting point

Continue with [Bibliography](../tutorials/bibliography.md) to extend the manual's
example. Choose [DataStructures](datastructures.md) for CPU and allocation costs,
or [Oxygen](oxygen.md) for request handling and network measurements. Both pages
include profiling, diagnostics and commands for the graphical interfaces.

The [interface reference](interfaces.md) and [tool map](extensions.md) collect
the shared recipes for later use.

The documentation build reads saved data and figures; its duration is independent
of the time spent running the original benchmarks.

## Get the runnable examples

The DataStructures and Oxygen scripts are in
[`examples/kitchen-sink`](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/release/v1.0.0-rc1/examples/kitchen-sink).
During the release candidate, use a checkout of that branch so the examples and
PerfChecker use matching APIs.

```sh
git clone --branch release/v1.0.0-rc1 https://github.com/Mirage-Interactive-Fr/PerfChecker.jl.git
cd PerfChecker.jl/examples/kitchen-sink
julia setup.jl core
```

Run the DataStructures and Oxygen commands from this directory. The example controller requires
Julia 1.12 or newer. `setup.jl core` activates this directory's `Project.toml`,
links the checked-out PerfChecker and installs the example dependencies. Optional
interfaces get their own `.controller/NAME` environments when requested.

Use one Julia compute thread, one GC thread and one BLAS thread, with one
precompilation task. Run campaigns sequentially on an otherwise quiet machine.
In PowerShell, for example:

```powershell
$env:JULIA_NUM_THREADS = '1'
$env:JULIA_NUM_GC_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
$env:JULIA_NUM_PRECOMPILE_TASKS = '1'
```

These variables bound the components individually; an operating-system affinity
or CI CPU allocation bounds the whole process tree. The recorded Windows runs
used at most four logical CPUs.

## Understand the output

A run prints a new directory under `results/`. It contains `suite-result.json`,
a human-readable report, JUnit output and an integrity-checked run bundle.
Keep that directory: every interface can reuse its observations. In command
examples, replace `results/ACTUAL-RUN` with the printed directory.

A successful run means the selected measurements completed and their result
checks passed. To fail CI on a slowdown, add a baseline and limits as described
in [performance comparisons](../tutorials/comparisons.md).
