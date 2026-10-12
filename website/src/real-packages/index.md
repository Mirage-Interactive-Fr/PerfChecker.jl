```@raw html
<a id="Real-package-examples"></a>
<a id="Choose-a-starting-point"></a>
```

# Examples

Complete experiments with scripts, saved measurements and notebooks. Each page explains what its figures measure and how to reproduce them.

- [Bibliography](../tutorials/bibliography.md) — import, parse and export entries across nine releases.
- [DataStructures](datastructures.md) — construct and use 35 containers across eight years.
- [Oxygen](oxygen.md) — HTTP features, application routes and real network traffic.

```@raw html
<a id="Get-the-runnable-examples"></a>
```

## Get the code

```sh
git clone --branch v1.0.1 https://github.com/Mirage-Interactive-Fr/PerfChecker.jl.git
cd PerfChecker.jl/examples/kitchen-sink
julia setup.jl core
```

Setup ends with a line in this form, where `/path/to` is your clone location:

```text
Prepared core: /path/to/PerfChecker.jl/examples/kitchen-sink/Project.toml
```

This identifies the environment to use for the commands on the DataStructures
and Oxygen pages. Setup installs dependencies; it does not measure a workload.

- The examples run Julia 1.12 or newer.
- `setup.jl core` links the checkout and installs example dependencies.
- Optional interfaces get their own `.controller/NAME` environment.

This recipe uses the published **1.0.1** tag, including its matching interface
companions. Setup develops that checkout into the example controller; it does
not install the latest registered Core automatically. Persistent preferences
and the read-only worker-seed correction require Core 1.1.0 or newer.

## Run one session at a time

Set one compute thread, one GC thread and one BLAS thread, then run campaigns sequentially on a quiet machine.

```powershell
$env:JULIA_NUM_THREADS = '1'
$env:JULIA_NUM_GC_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
```

```@raw html
<a id="Understand-the-output"></a>
```

## Read the output

Planning only lists the selected cases and creates no measurement report. After
an explicit measurement command, the script prints `Reports: <directory>` under
`results/`. Open that directory's report and `suite-result.json`; its saved
bundles can be reopened from the supported interfaces. A successful run means
the selected measurements completed and their correctness checks passed — no
performance budget was applied. The linked package guides show the actual
recorded outputs and explain their measurement scope.

## Next

- New to profiling? Read [Understand the result](../guide/understanding-measurements.md).
- Continue the manual with [Bibliography](../tutorials/bibliography.md).
