"""
Optional LIKWID CPU counters in explicitly prepared PerfChecker worker projects.
This companion changes no permissions, libraries, thread affinity or CPU settings.
"""
module PerfCheckerLIKWID

using LIKWID
using PerfChecker
using SHA: sha256
using UUIDs: uuid4
import JSON
import Pkg
import TOML

export CounterRecord, CounterResult, measure_counters, counter_bundle,
       counter_command, counter_executor, run_counter_suite

"""
    CounterRecord(event, counter, cpu_id, unit, value::Float64)

One raw native LIKWID record. `event` and `counter` are the exact custom event and
FIXC/PMC names; `cpu_id` is the selected logical CPU ID. `unit` is the explicit
event declaration (documented instruction/cycle events use count unit `1`).
`value` retains the backend's Float64 representation without scaling or an
invented exact integer count. Attribution depends on the access mode and PID in
[`CounterResult`](@ref); a CPU ID alone does not imply whole-process attribution.
"""
struct CounterRecord
    event::String
    counter::String
    cpu_id::Int
    unit::String
    value::Float64
end

"""
    CounterResult(status, reason, records, allowed_cpuids, cpuids,
                  group_time_seconds, access_mode, perf_pid)

Evidence for a native selected-CPU backend window. `status` is `:complete` or
`:unavailable` for native measurement; worker evidence can be `:blocked` for a
blocking probe, `:invalid` for a failed oracle or `:failed` for an error. `reason`
explains refusal/failure; `records` holds raw [`CounterRecord`](@ref)s and is empty
when unavailable. `allowed_cpuids` is inherited affinity; `cpuids` is the explicit
selection. `group_time_seconds` is native group time in seconds, or `nothing`;
enabled/running times are not exposed by this backend API.

`access_mode` records the native PERF/DIRECT/DAEMON mode; `perf_pid` records the
optional own-process PID setting, or `nothing`. Direct/daemon windows can include
unrelated CPU activity; PERF semantics depend on the installed library and PID
setting, without a guarantee of counting all process threads. The six-argument
constructor leaves mode `"not_recorded"` and PID `nothing`; it does not attest
native attribution. No counts are converted into duration and no CPUs are pinned.
"""
struct CounterResult
    status::Symbol
    reason::String
    records::Vector{CounterRecord}
    allowed_cpuids::Vector{Int}
    cpuids::Vector{Int}
    group_time_seconds::Union{Nothing, Float64}
    access_mode::String
    perf_pid::Union{Nothing, Int}
end

function CounterResult(status, reason, records, allowed_cpuids, cpuids, group_time_seconds)
    CounterResult(status, reason, records, allowed_cpuids, cpuids, group_time_seconds,
        "not_recorded", nothing)
end

function _allowed_cpuids()
    Sys.islinux() || return Int[]
    line = only(filter(line -> startswith(line, "Cpus_allowed_list:"),
        readlines("/proc/thread-self/status")))
    result = Int[]
    for interval in split(strip(split(line, ':'; limit = 2)[2]), ',')
        bounds = parse.(Int, split(interval, '-'))
        append!(result, length(bounds) == 1 ? bounds : collect(bounds[1]:bounds[2]))
    end
    result
end

function _configuration(event_set, cpuids, units; check_affinity = true)
    text = String(event_set)
    entries = split(text, ',')
    all(entry -> occursin(r"^[A-Z][A-Z0-9_]*:(?:FIXC|PMC)[0-9]+$", entry), entries) ||
        throw(ArgumentError("declare explicit CPU events with FIXC/PMC counters; groups, options and uncore counters are unsupported"))
    events = [split(entry, ':')[1] for entry in entries]
    counters = [split(entry, ':')[2] for entry in entries]
    allunique(events) && allunique(counters) ||
        throw(ArgumentError("duplicate event or counter"))
    cpus = collect(cpuids)
    !isempty(cpus) &&
        all(cpu -> cpu isa Integer && !(cpu isa Bool) && 0 <= cpu <= typemax(Int32),
            cpus) ||
        throw(ArgumentError("cpuids must be explicit nonnegative Int32-compatible integers"))
    allunique(cpus) || throw(ArgumentError("duplicate CPU id"))
    declared = Dict(String(event) => String(unit) for (event, unit) in pairs(units))
    Set(keys(declared)) == Set(events) ||
        throw(ArgumentError("units must name every exact event and no others"))
    for event in ("INSTR_RETIRED_ANY", "CPU_CLK_UNHALTED_CORE", "CPU_CLK_UNHALTED_REF")
        haskey(declared, event) && declared[event] != "1" &&
            throw(ArgumentError("documented instruction/cycle events have count unit 1, not duration"))
    end
    all(unit -> occursin(r"^[A-Za-z0-9][A-Za-z0-9./_*^-]{0,127}$", unit),
        values(declared)) ||
        throw(ArgumentError("each event requires an explicit bounded unit identifier"))
    allowed = _allowed_cpuids()
    check_affinity && Sys.islinux() && !all(cpu -> cpu in allowed, cpus) &&
        throw(ArgumentError("CPU selection is outside inherited affinity; repinning is forbidden"))
    (event_set = text, events = events, counters = counters, cpuids = Int.(cpus),
        units = declared, allowed_cpuids = allowed)
end

"""
    measure_counters(f; event_set, cpuids, units) -> CounterResult

Count one invocation using LIKWID 0.4.6's low-level PerfMon API. All arguments
are explicit: custom CPU event/counter pairs (for example
`"INSTR_RETIRED_ANY:FIXC0,CPU_CLK_UNHALTED_CORE:FIXC1"`), CPU IDs inside the
calling thread's inherited affinity, and a unit dictionary keyed by exact event.
Group aliases, event options and uncore counters are refused. Nothing is pinned.

The scope is a native backend window on selected CPUs. The actual access mode and
optional `LIKWID_PERF_PID` are recorded; a foreign or invalid PID is refused.
Direct/daemon modes may include unrelated CPU activity. PERF attribution depends
on the installed native library and PID setting: this API does not guarantee all
threads of a process. LIKWID itself may set its own PID at import. Preparation and oracle
work must be outside `f`; asynchronous work must be synchronized inside `f`.
Values retain the backend's Float64 representation, not an invented exact UInt64
count. No scaling is added. Group time is reported separately in seconds;
enabled/running times are unavailable because this API does not expose them.
Units are caller declarations, never inferred from names or values; cycles must
not be declared as duration. A missing library/refused initialization returns
`:unavailable` without calling `f`. Callback and stop/read errors propagate after
owned native state is finalized. Pre-existing PerfMon/topology/NUMA state is
refused rather than finalized. No kernel settings or capabilities are changed.
"""
function measure_counters(f; event_set, cpuids, units)
    config = _configuration(event_set, cpuids, units)
    access_mode = "not_recorded"
    perf_pid = nothing
    function unavailable(reason)
        CounterResult(:unavailable, reason, CounterRecord[],
            config.allowed_cpuids, config.cpuids, nothing, access_mode, perf_pid)
    end
    Sys.islinux() || return unavailable("unsupported_platform")
    if haskey(ENV, "LIKWID_PERF_PID")
        perf_pid = tryparse(Int, ENV["LIKWID_PERF_PID"])
        perf_pid == getpid() || return unavailable("foreign_or_invalid_perf_pid")
    end
    LIKWID.liblikwid_available() || return unavailable("library_unavailable")
    (LIKWID.perfmon_initialized[] || LIKWID.topo_initialized[] ||
     LIKWID.numa_initialized[] || LIKWID.timer_initialized[]) &&
        return unavailable("native_state_already_owned")
    mode = LIKWID.accessmode()
    mode in (LIKWID.LibLikwid.ACCESSMODE_PERF, LIKWID.LibLikwid.ACCESSMODE_DIRECT,
        LIKWID.LibLikwid.ACCESSMODE_DAEMON) || return unavailable("access_mode_unknown")
    access_mode = string(mode)
    started = false
    attempted = false
    try
        attempted = true
        LIKWID.PerfMon.init(config.cpuids) === true ||
            return unavailable("initialization_refused")
        group = LIKWID.PerfMon.add_event_set(config.event_set)
        group isa Integer && group > 0 || return unavailable("event_set_refused")
        LIKWID.PerfMon.get_number_of_events(group) == length(config.events) ||
            return unavailable("event_set_changed")
        for index in eachindex(config.events)
            LIKWID.PerfMon.get_name_of_event(group, index) == config.events[index] &&
                LIKWID.PerfMon.get_name_of_counter(group, index) ==
                config.counters[index] ||
                return unavailable("event_identity_changed")
        end
        LIKWID.PerfMon.setup_counters(group) === true || return unavailable("setup_refused")
        LIKWID.PerfMon.start_counters() === true || return unavailable("start_refused")
        started = true
        f()
        LIKWID.PerfMon.stop_counters() === true || error("LIKWID stop failed")
        started = false
        records = CounterRecord[]
        for (thread_index, cpu) in enumerate(config.cpuids),
            (event_index, event) in enumerate(config.events)

            value = LIKWID.PerfMon.get_result(group, event_index, thread_index)
            value isa Float64 && isfinite(value) ||
                error("LIKWID returned no finite raw Float64 value")
            push!(records,
                CounterRecord(event, config.counters[event_index], cpu,
                    config.units[event], value))
        end
        group_time = LIKWID.PerfMon.get_time_of_group(group)
        group_time isa Float64 && isfinite(group_time) && group_time >= 0 ||
            error("LIKWID returned no valid group time")
        CounterResult(
            :complete, "", records, config.allowed_cpuids, config.cpuids, group_time,
            access_mode, perf_pid)
    finally
        try
            started && LIKWID.PerfMon.stop_counters() !== true &&
                error("LIKWID cleanup stop failed")
        finally
            try
                attempted && LIKWID.PerfMon.finalize()
            finally
                try
                    LIKWID.timer_initialized[] && LIKWID.Timer.finalize()
                finally
                    try
                        LIKWID.numa_initialized[] && LIKWID.finalize_numa()
                    finally
                        LIKWID.topo_initialized[] && LIKWID.finalize_topology()
                    end
                end
            end
        end
    end
end

include("provider.jl")

end
