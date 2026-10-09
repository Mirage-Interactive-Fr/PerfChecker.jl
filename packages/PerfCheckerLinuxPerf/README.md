# PerfCheckerLinuxPerf

An optional LinuxPerf 0.4.2 companion for PerfChecker 1.x. It uses raw Linux
perf-event counts, with separate enabled/running times in nanoseconds. CPU
cycles have count unit `1`; they are never converted to elapsed time. Only the
calling OS thread's user-space execution is counted, not other threads or child
processes. Callbacks that yield may execute outside this thread. Compilation
inside the callback is part of the window; there is no implicit warmup or rerun.

The supported syscall/ABI boundary is little-endian Linux x86_64, i686 and
aarch64 (syscall numbers 298, 336 and 241). Other architectures are explicitly
unavailable before the callback. The companion checks LinuxPerf's actual syscall
number and the native 112-byte version-5 `perf_event_attr` layout. Group reads
use native unsigned 64-bit words for count, enabled/running times and values,
independently of the architecture's C-long width. This boundary check is not a
positive hardware qualification on all three architectures.
The companion CI checks Julia 1.10/latest on x86_64 and latest on i686 with a
required ABI assertion. aarch64 currently has source/guard review only, not an
execution qualification. CI does not change permissions or the kernel; any
native positive counters depend on the runner's existing access.

This companion is developed from the monorepo until separately registered. Use
an explicit worker project with `Pkg.develop(path=...)` for the companion and
the target source. LinuxPerf requires PrettyTables 2, so keep this worker project
separate from the LIKWID worker project, which requires PrettyTables 3.

```julia
using PerfChecker, PerfCheckerLinuxPerf

# These are existing, explicitly prepared projects/files, not generated here.
target_source = joinpath(homedir(), ".julia", "dev", "Example")
worker_project = joinpath(target_source, "perf", "linuxperf-worker")
entrypoint = joinpath(target_source, "perf", "sum_workload.jl")
feature = FeatureSpec(:sum_counters; backend=:linuxperf, entrypoint,
    oracle=OracleSpec(), options=Dict(
        :counter_environment => worker_project,
        :events => ["instructions", "cpu-cycles"],
        :timeout_seconds => 300))
package = PackageSuite("Example"; source=target_source,
    worker_environment=worker_project, features=[feature])
plan = plan_suite(SoftwareSuite(:hardware, [package]); profile=:quick)
result = run_counter_suite(plan)
write_suite_reports(result, joinpath(target_source, "perf", "counter-results"))
```

The entrypoint defines `perf_setup()`, `perf_workload(state)`, an optional
`perf_synchronize(state, result)`, `perf_oracle(state, result)`, and
`perf_cleanup(state)`. Probes and preparation occur before the counter window;
the operation and synchronization occur once inside it; the counters stop before
the oracle receives the actual result. A supplied `perf_cleanup` is attempted
once after preparation returns, including refusal, callback error or oracle
failure. A `perf_setup` that throws before returning must release its own partial
resources.

`counter_command` returns a real `ExternalCommandSpec` for an isolated Julia
worker emitting `perfchecker-provider-result/1`. Target version/source, exact
release pins, workload bytes and resolved Project/Manifest are checked before
workload execution. Candidate refs are not installed implicitly. The custom
`counter_executor` specializes PerfChecker's current internal unavailable
predicate only for this companion's exception; `run_counter_suite` retains raw
provider evidence and worker qualification/provenance in every attempted row.

Denied permissions return unavailable evidence with no observations. Neither
this API nor its tests change `perf_event_paranoid`, capabilities or affinity.
`counter_not_scheduled` is an unavailable result after the operation has run
once: the opened group recorded zero running time. The worker still synchronizes,
checks the actual result and cleans up, but exports no numeric counters and keeps
the suite verdict partially executed. Other opening/permission refusals do not
run the operation. This distinction must be preserved when deciding to retry.
`UInt64` values above `2^53-1` remain exact decimal strings in raw diagnostics and
are omitted from numeric observations with a warning. A raw count window is not
a benchmark timing sample or a validated performance comparison.

The local qualification environment denies perf events; refusal, descriptor
cleanup and the actual isolated provider path are tested there. Positive hardware
measurement remains conditional on an environment that actually grants access.
Perf-event descriptors are opened atomically with close-on-exec, so executable
subprocesses do not inherit them. This positive descriptor path is not qualified
on the permission-denied local machine.

## Frontend scope

The Julia API above is explicit. Julia's terminal API also propagates an explicit
`executor=counter_executor(...)` through `run_suite_repl`; provide a `bundle_sink`
to retain the detailed provider evidence, especially unavailable attempts.
`run_suite_file(...; executor=...)` has the same explicit Julia keyword route.
CLI commands, default VSCode runs and generated Pluto notebooks do not select
this executor, and are not native LinuxPerf frontend support. Their ordinary
backend configuration must not be used to imply such support.

PerfCheckerWeb's Julia configuration accepts and forwards an explicit executor
in `register_oxygen_routes!` and `run_studio_agent`; this source-level route is
separate from qualifying a real counter HTTP/UI job. That frontend qualification
has not been completed here. Native frontend selection would require a separate,
reviewed explicit dispatcher and report/plot support; no global backend registry
or implicit configuration mutation is introduced by this companion.

Primary backend contract: [LinuxPerf 0.4.2 source](https://github.com/JuliaPerf/LinuxPerf.jl/blob/v0.4.2/src/LinuxPerf.jl).
