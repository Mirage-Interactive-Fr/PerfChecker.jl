# Real package examples

Start with a real workload, prove that its answer is right, then measure the
same work across package versions. This section follows that sequence with two
packages. You can run the scripts yourself or explore the recorded plots first.
An assistant, a hosted service and a GPU are not required.

| Example | Work performed | What the measurements include |
| --- | --- | --- |
| [DataStructures](datastructures.md) | Construct and use 35 containers, then investigate event processing | 70 separate operations across every 0.19 patch, plus a longer historical comparison |
| [Oxygen](oxygen.md) | Compare seven HTTP features, three application routes and real traffic | Older minor releases and every recent patch; network latency, bytes, packets and throughput have their own figures |

The application workloads share an event stream. It contains a priority, a unique
identifier and a category for every event. A fixed seed reproduces the input;
an independently computed expected answer checks each workload. This lets you
ask whether time is spent processing data or serving the request around it.

## Choose a starting point

Choose either [DataStructures](datastructures.md) or [Oxygen](oxygen.md).
Each page is a complete walkthrough: check an answer, select releases, measure,
read the figures, investigate costs and replay the evidence in every interface.
Each also has its own downloadable Pluto notebook. You do not need to jump
between pages to finish the experiment.

The [interface reference](interfaces.md) and [tool map](extensions.md) collect
the shared recipes for later use.

The plots on these pages come from local executions. The documentation build
only copies the recorded data and figures. It does **not** install the example
environments, start a server or rerun a performance campaign.

## Get the runnable examples

The scripts are in
[`examples/kitchen-sink`](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/release/v1.0.0-rc1/examples/kitchen-sink).
During the release candidate, use a checkout of that branch so the examples and
PerfChecker agree. This is preparation for these experiments, not an extra step
in [installing PerfChecker](../guide/installation.md).

```sh
git clone --branch release/v1.0.0-rc1 https://github.com/Mirage-Interactive-Fr/PerfChecker.jl.git
cd PerfChecker.jl/examples/kitchen-sink
julia setup.jl core
```

Run the following commands from this directory. The example controller requires
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
used at most four logical CPUs. They illustrate the workflow on one machine, not a
universal performance ranking.

## Understand the output

A run prints a new directory under `results/`. It contains `suite-result.json`,
a human-readable report, JUnit output and an integrity-checked run bundle.
Keep that directory: every interface can reuse its observations. In command
examples, replace `results/ACTUAL-RUN` with the printed directory.

Correctness and performance are separate. A successful run means the selected
checks and their required oracles passed. A regression verdict additionally
requires a baseline, a comparison policy and enough comparable samples.
The recorded history does not impose a CI performance budget.
