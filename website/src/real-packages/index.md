# Examples

Complete experiments with scripts, saved measurements and notebooks. Each page explains what its figures measure and how to reproduce them.

- [Bibliography](../tutorials/bibliography.md) — import, parse and export entries across nine releases.
- [DataStructures](datastructures.md) — construct and use 35 containers across eight years.
- [Oxygen](oxygen.md) — HTTP features, application routes and real network traffic.

## Get the code

```sh
git clone --branch release/v1.0.0-rc1 https://github.com/Mirage-Interactive-Fr/PerfChecker.jl.git
cd PerfChecker.jl/examples/kitchen-sink
julia setup.jl core
```

- The examples run Julia 1.12 or newer.
- `setup.jl core` links the checkout and installs example dependencies.
- Optional interfaces get their own `.controller/NAME` environment.

## Run one session at a time

Set one compute thread, one GC thread and one BLAS thread, then run campaigns sequentially on a quiet machine.

```powershell
$env:JULIA_NUM_THREADS = '1'
$env:JULIA_NUM_GC_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
```

## Read the output

A run prints a new directory under `results/`, holding the report, a machine-readable result and a bundle every interface can reopen. A successful run means the selected measurements completed and their correctness checks passed — no performance budget was applied.

## Next

- New to profiling? Read [Understand the result](../guide/understanding-measurements.md).
- Continue the manual with [Bibliography](../tutorials/bibliography.md).

```@raw html
<a id="Real-package-examples"></a>
<a id="Choose-a-starting-point"></a>
<a id="Get-the-runnable-examples"></a>
<a id="Understand-the-output"></a>
```
