# Measurement model

What a metric includes, and when two records may be compared. For an introduction with plots, see [Understand the result](guide/understanding-measurements.md).

Each metric is:

```text
resource × lifecycle phase × execution regime × scope × method × statistic
```

For example: startup, import, first execution and steady-state time are four measurements. Julia heap bytes, native heap bytes, process RSS and GPU memory are four resources.

## Required context

Every measurement definition states:

- metric ID, unit, collector and definition version;
- phase: resolve, install, precompile, startup, import, first execution, steady state, endurance, shutdown;
- regime: clean depot, cached depot, fresh process, warm process, steady state;
- scope: expression, method, feature, task, process, process tree, interface, service, database, device;
- clock or counter source, and whether collection is exact, repeated, sampled, static or estimated;
- sample and aggregation semantics;
- whether compilation, GC, child processes, GPU synchronization, loopback and protocol overhead are included;
- expected perturbation and required privileges;
- runtime, source, dependency, artifact, platform, hardware and environment provenance;
- a semantic outcome proving both candidates did equivalent work.

Values are comparable only when their measurement definitions and comparison keys permit it.

## Comparability in a bundle

Suite bundles retain controller thread count, hardware fingerprint, local Git revision/branch/dirty state, and SHA-256 fingerprints of the effective Project and Manifest.

- Different OS, architecture, Julia thread count or known hardware makes a comparison `incomparable`.
- A changed runtime or resolved environment is a warning, because controlled campaigns may vary one deliberately.
- Older bundles with missing fingerprints carry less comparability information.

## Measurement families

- **Warm CPU execution** — latency, throughput, CPU user/system, GC. BenchmarkTools, Chairmarks.
- **Startup and import** — bare startup, activation, `using`, `__init__`, extension load. Fresh processes, `@time_imports`.
- **Compilation and TTFX** — first execution, inference, codegen, recompilation, dispatch. Trace flags, SnoopCompile, JET.
- **Precompile and images** — `Pkg.precompile`, cache hit/miss, image size. PrecompileTools, PackageCompiler.
- **Inference and invalidation** — inference time, unstable returns, dispatch sites, invalidation trees. JET, SnoopCompile.
- **CPU profiles** — self/cumulative samples, task/thread, Julia and native frames. `Profile`, PProf, Speedscope.
- **Scheduling and waiting** — runnable/running/waiting tasks, locks, saturation. Wall-time profile.
- **Julia allocation and GC** — bytes/count per operation, sites, pauses. `Profile.Allocs`, `@allocated`, AllocCheck.
- **Heap and process memory** — Julia heap, retained objects, RSS/commit peak, page faults. Heap snapshots, process sampler.
- **Microarchitecture** — cycles, instructions, IPC, cache/TLB/branch misses, migrations. LinuxPerf, LIKWID.
- **File and storage I/O** — logical/physical bytes, ops, latency, warm/cold cache. App counters plus OS adapters.
- **Network and services** — payload/interface/wire bytes, packets, retries, latency. Workload counters, isolated interface.
- **GPU/accelerator** — device compile, launch, kernel, transfer, sync, VRAM. CUDA/AMDGPU, vendor profilers.
- **Parallel/distributed** — speedup, efficiency, scaling, serialization, imbalance. Thread/process matrices, MPI.
- **Energy** — joules/run, joules/op, power. RAPL/LIKWID.
- **Domain algorithm** — growth with size, time-to-solution, accuracy, iterations. Workload-declared outcomes.
- **Load/endurance** — tail latency, backpressure, errors, recovery. Isolated staged-load scenarios.

Static analyzers emit diagnostics, not timings. A JET or AllocCheck finding can guide attribution; it is never presented as measured cost.

## Process and external memory

Set `:process_resources => true` on a feature to record a resource envelope around its backend collection.

- **Windows** — `WorkingSetSize`, lifetime `PeakWorkingSetSize`, `PrivateUsage`.
- **Linux** — `VmRSS`, lifetime `VmHWM`, `smaps_rollup` private mappings.
- **Other platforms** — all three `unavailable`.

- Unsupported fields are absent, never zero.
- The envelope surrounds the whole collection, not each sample.
- A process peak is never reset; `new_lifetime_peak` records only its growth during collection.
- BenchmarkTools `memory`/`allocs` columns remain Julia allocation evidence, separate from process RSS.

A feature that owns native memory can name a `:external_memory_probe` callback implementing `perfchecker-external-memory/1`. See [Process memory](process-memory.md).

## Network accounting

Five scopes, weakest to strongest attribution:

1. `application` — payload bytes and operations the workload reports.
2. `host_interface` — OS interface deltas; contaminated by unrelated traffic.
3. `isolated_interface` — the same counters inside a dedicated namespace or container.
4. `process_tree` — bytes/packets attributed by ETW/eBPF to the worker.
5. `wire` — packet capture including transport overhead; opt-in.

Package CI gates require level 3, 4 or a controlled interface. Latency is always labelled with its context (in-process, loopback, client end-to-end, server, DNS/TLS, scheduler wait).

## Native dependency closure

Four layers:

```text
declared package → resolved artifact → loaded native image → spawned process / service
```

`dependency_evidence()` snapshots the first layer's current process. `ProbeSpec` adds a feature-owned functional check inside the prepared worker. Successful resolution alone never proves an ABI or symbol is usable. Julia allocation counters never claim to cover native allocators.

## Julia runtimes

`JuliaRuntimeSpec` adds a runtime axis separate from package versions.

- Moving selectors (`release`, `rc`, `nightly`) are probed in a fresh process; the exact version, commit, bindir and LLVM version are frozen before workers start.
- `run_julia_runtime_campaign` compares bundles without treating a runtime difference as an automatic incompatibility.
- Failures are phase-classified: resolver vs precompile vs runtime crash vs suite failure vs launch vs missing report.

Two campaign styles:

- **Strict runtime attribution** keeps source, dependencies, workload and machine fixed while Julia changes.
- **Realistic compatibility** resolves independently under each runtime and reports dependency differences without attributing them to Julia.

```@raw html
<a id="Required-measurement-context"></a>
<a id="Julia-performance-families"></a>
<a id="Package-archetypes"></a>
<a id="Julia-stable-versus-candidate-runtimes"></a>
```
