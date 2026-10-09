# PerfCheckerLIKWID

An optional LIKWID 0.4.6 companion for PerfChecker 1.x. Keep its prepared worker
project separate from LinuxPerf: LIKWID requires PrettyTables 3, LinuxPerf 2.
Until this companion is separately registered, develop it explicitly from the
monorepo into the worker project. Native `liblikwid` installation and permission
configuration are prerequisites; the companion never installs or changes them.

Declare exact custom CPU event/counter pairs and units, not a group alias:

```julia
using PerfChecker, PerfCheckerLIKWID
target_source = joinpath(homedir(), ".julia", "dev", "Example")
worker_project = joinpath(target_source, "perf", "likwid-worker")
entrypoint = joinpath(target_source, "perf", "sum_workload.jl")
feature = FeatureSpec(:sum_counters; backend=:likwid, entrypoint,
    oracle=OracleSpec(), options=Dict(
        :counter_environment => worker_project,
        :event_set => "INSTR_RETIRED_ANY:FIXC0,CPU_CLK_UNHALTED_CORE:FIXC1",
        :units => Dict("INSTR_RETIRED_ANY"=>"1", "CPU_CLK_UNHALTED_CORE"=>"1"),
        :cpuids => [16],  # Must be inside this process's inherited affinity.
        :timeout_seconds => 300))
package = PackageSuite("Example"; source=target_source,
    worker_environment=worker_project, features=[feature])
plan = plan_suite(SoftwareSuite(:hardware, [package]); profile=:quick)
result = withenv("LIKWID_PERF_PID" => nothing) do
    run_counter_suite(plan)
end
write_suite_reports(result, joinpath(target_source, "perf", "counter-results"))
```

Supported events depend on hardware. Uncore counters, group aliases, event
options, CPU selection outside inherited affinity and automatic repinning are
refused. Existing native PerfMon/topology/NUMA/timer ownership is preserved.
The exact target, pins, workload and Project/Manifest identities are checked in
the real `ExternalCommandSpec` Julia worker before running user code.

The entrypoint defines preparation, operation, optional synchronization, oracle
and cleanup hooks as in PerfCheckerLinuxPerf. Preparation/probes are outside the
window. The operation runs once, synchronization is inside the window, and the
oracle receives that actual result after stop. A supplied cleanup hook is attempted after successful preparation.
A `perf_setup` that throws before returning must release its own partial resources. No warmup
or implicit workload rerun is performed; JIT compilation inside the callback is
part of the measured window.

Scope is a native backend window on selected CPUs, with the actual access mode
and optional `LIKWID_PERF_PID` recorded. Foreign or invalid inherited PIDs are
refused before initialization. Direct/daemon modes may include unrelated CPU
activity. PERF attribution depends on the installed native library and PID
setting; there is no guarantee that all threads of a process are counted.
LIKWID itself can set the current PID at import. The native library version is
explicitly unknown in these records. Raw backend Float64 values are preserved without
inventing exact integer counts. Units are declared for every exact event; the
documented fixed instruction/cycle events use count unit `1`, never duration.
Group time is a separate seconds field. Enabled/running times are unavailable
with an explicit reason because this API does not expose them. No scaling is
added by the companion.

The example explicitly removes `LIKWID_PERF_PID` only during worker launch and
restores the controller environment afterwards. In PERF mode LIKWID can then
select the worker's own PID at import, rather than inherit the controller PID.
The companion does not silently retarget an inherited PID or monitor another
process. Direct `measure_counters` accepts only an absent PID or its own PID.

`run_counter_suite` retains provider evidence and qualification/provenance even
for unavailable attempts. Native library absence is not a zero counter or a
successful measurement. The local machine has no `liblikwid`; the actual refusal
and isolated provider path are tested. Positive hardware qualification still
requires a real permitted native environment. This does not close issue #17 on
the strength of a plan or an unavailable run.

## Frontend scope

The explicit Julia API is supported. Julia's terminal `run_suite_repl` and
`run_suite_file` accept an explicit `executor=counter_executor(...)`; a supplied
`bundle_sink` retains detailed provider evidence for unavailable attempts.
Default CLI/VSCode runs and generated Pluto notebooks do not select this executor
and are not native LIKWID frontend support. Generic benchmark plots do not turn
these raw CPU counters into timing metrics.

The Web companion's Julia `register_oxygen_routes!` and `run_studio_agent`
configuration forwards an explicit executor. This source-level capability is
not a completed hardware-counter HTTP/UI qualification. Native frontend
selection needs a separate reviewed explicit dispatcher and appropriate
report/plot handling. No global registry or implicit configuration override is
used here.

Primary contracts: [LIKWID 0.4.6 PerfMon](https://github.com/JuliaPerf/LIKWID.jl/blob/v0.4.6/src/perfmon.jl),
[native perfctr scope](https://github.com/RRZE-HPC/likwid/wiki/likwid-perfctr).
