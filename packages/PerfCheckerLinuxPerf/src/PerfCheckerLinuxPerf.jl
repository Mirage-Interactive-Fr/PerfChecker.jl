"""
Optional Linux perf-event counters for explicitly configured PerfChecker workers.
No capabilities, kernel settings, CPU affinity or installed libraries are changed.
"""
module PerfCheckerLinuxPerf

using LinuxPerf
using PerfChecker
using SHA: sha256
using UUIDs: uuid4
import JSON
import Pkg
import TOML

export CounterRecord, CounterResult, measure_counters, counter_bundle,
       counter_command, counter_executor, run_counter_suite

const _EVENTS = ("cpu-cycles", "instructions", "cache-references", "cache-misses",
    "branch-instructions", "branch-misses", "context-switches", "cpu-migrations",
    "page-faults", "minor-faults", "major-faults")

# Atomic close-on-exec for every owned leader/member descriptor (Linux >= 3.14).
const _PERF_FLAG_FD_CLOEXEC = Clong(1) << 3

function _abi_unavailable_reason(arch = Sys.ARCH)
    expected_syscall = arch === :x86_64 ? 298 :
                       arch === :i686 ? 336 :
                       arch === :aarch64 ? 241 : nothing
    expected_syscall === nothing && return "unsupported_architecture"
    Base.ENDIAN_BOM == 0x04030201 || return "unsupported_byte_order"
    LinuxPerf.SYS_perf_event_open == expected_syscall || return "unsupported_syscall_abi"
    # Linux perf_event_attr size version 5, including its bitfield word at offset 40.
    attr = LinuxPerf.perf_event_attr
    offsets = (0, 4, 8, 16, 24, 32, 40, 48, 52, 56, 64, 72, 80, 88, 92, 96, 104, 108)
    sizeof(attr) == 112 && fieldcount(attr) == length(offsets) &&
        all(index -> fieldoffset(attr, index) == offsets[index], eachindex(offsets)) ||
        return "unsupported_attribute_abi"
    # GROUP + TOTAL_TIME_ENABLED + TOTAL_TIME_RUNNING reads native u64 words.
    sizeof(UInt64) == 8 || return "unsupported_read_abi"
    nothing
end

"""
    CounterRecord(event, value::UInt64, enabled_ns::UInt64, running_ns::UInt64)

One raw Linux perf-event record. `event` is the exact canonical event name;
`value` is an unscaled count (unit `1`). `enabled_ns` and `running_ns` are the
kernel's unsigned nanosecond times for that group window, not operation duration.
The record covers the selected calling OS thread's user-space activity, excluding
kernel, hypervisor, other threads and children. Cycles are counts, not seconds.
"""
struct CounterRecord
    event::String
    value::UInt64
    enabled_ns::UInt64
    running_ns::UInt64
end

"""
    CounterResult(status, reason, records, thread_id, allowed_cpuids)

Evidence for one calling-thread counter window. `status` is `:complete` or
`:unavailable` for native measurement; the isolated worker also uses `:blocked`
for a blocking probe, `:invalid` for a failed oracle and `:failed` for an error.
`reason` explains refusal/failure; `records` holds raw [`CounterRecord`](@ref)s
and is empty when unavailable. `thread_id` is the measured Linux OS thread ID;
zero means no thread identity was captured. `allowed_cpuids` records inherited
affinity, not CPUs measured individually. No affinity is changed and callbacks
that yield may run outside the measured thread. Enabled/running times are not
used to scale counts or infer duration.
"""
struct CounterResult
    status::Symbol
    reason::String
    records::Vector{CounterRecord}
    thread_id::Int
    allowed_cpuids::Vector{Int}
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

function _events(events)
    names = String.(collect(events))
    isempty(names) && throw(ArgumentError("at least one perf event is required"))
    length(unique(names)) == length(names) || throw(ArgumentError("duplicate perf event"))
    all(name -> name in _EVENTS, names) ||
        throw(ArgumentError("unsupported event; only explicit generic count events are accepted"))
    names
end

function _open_group(names)
    streams = IOStream[]
    leader = Cint(-1)
    try
        for name in names
            event = LinuxPerf.NAME_TO_EVENT[name]
            attr = LinuxPerf.perf_event_attr()
            attr.size = sizeof(attr)
            attr.typ = event.category
            attr.config = event.event
            attr.flags = (UInt64(1) << 5) | (UInt64(1) << 6)
            leader == -1 && (attr.flags |= UInt64(1))
            attr.read_format = LinuxPerf.PERF_FORMAT_GROUP |
                               LinuxPerf.PERF_FORMAT_TOTAL_TIME_ENABLED |
                               LinuxPerf.PERF_FORMAT_TOTAL_TIME_RUNNING
            fd = LinuxPerf.perf_event_open(attr, Cint(0), Cint(-1), leader,
                _PERF_FLAG_FD_CLOEXEC)
            fd < 0 && throw(SystemError("perf_event_open", Libc.errno()))
            stream = try
                Base.fdio(fd, true)
            catch
                ccall(:close, Cint, (Cint,), fd)
                rethrow()
            end
            push!(streams, stream)
            leader == -1 && (leader = fd)
        end
        return streams, leader
    catch
        _close_streams(streams)
        rethrow()
    end
end

function _close_streams(streams)
    errors = Any[]
    for stream in reverse(streams)
        try
            close(stream)
        catch error
            push!(errors, error)
        end
    end
    isempty(errors) || throw(CompositeException(errors))
    nothing
end

function _ioctl(fd, operation)
    value = ccall(:ioctl, Cint, (Cint, Clong, Clong), fd, operation, 1)
    Base.systemerror("perf-event ioctl", value < 0)
    nothing
end

function _unavailable(error)
    error isa SystemError || return nothing
    error.errnum in (Libc.EACCES, Libc.EPERM) && return "permission_denied"
    error.errnum in (Libc.EINVAL, Libc.ENOENT, Libc.ENODEV, Libc.ENOSYS) &&
        return "event_unavailable"
    nothing
end

"""
    measure_counters(f; events=["instructions", "cpu-cycles"]) -> CounterResult

Measure exactly one call to `f` with a fresh LinuxPerf 0.4.2 perf-event group.
Little-endian Linux x86_64, i686 and aarch64 are supported at the syscall/ABI boundary; other
architectures or a mismatched native layout return `:unavailable` before `f`.
The scope is the calling OS thread, user space only, excluding the hypervisor;
other threads, child processes and kernel execution are not counted. Callbacks
that yield can execute elsewhere, so this is not a whole-process measurement.
No affinity is changed. Counts are raw `UInt64`; enabled/running are raw kernel
nanoseconds. Counts are never scaled and cycles are never converted to duration.

An accepted event unavailable at opening, an unsupported platform/ABI, or denied
permissions returns `:unavailable` without calling `f`. `counter_not_scheduled`
is different: the group was opened and `f` ran once, but its recorded running time
was zero. That result is unavailable with no numeric counters, not a measured zero.
Empty, duplicate
or unaccepted event names throw `ArgumentError`. Callback, read and stop errors propagate
after owned descriptors are closed. A successful window with zero running time
is unavailable, not a measured zero. Loading this package changes no permissions.
"""
function measure_counters(f; events = ["instructions", "cpu-cycles"])
    names = _events(events)
    Sys.islinux() || return CounterResult(:unavailable, "unsupported_platform",
        CounterRecord[], 0, Int[])
    reason = _abi_unavailable_reason()
    reason === nothing || return CounterResult(:unavailable, reason,
        CounterRecord[], 0, Int[])
    thread_id = Int(ccall(:gettid, Cint, ()))
    allowed = _allowed_cpuids()
    streams, leader = try
        _open_group(names)
    catch error
        reason = _unavailable(error)
        reason === nothing && rethrow()
        return CounterResult(:unavailable, reason, CounterRecord[], thread_id, allowed)
    end
    enabled = false
    try
        _ioctl(leader, LinuxPerf.PERF_EVENT_IOC_RESET)
        _ioctl(leader, LinuxPerf.PERF_EVENT_IOC_ENABLE)
        enabled = true
        f()
        _ioctl(leader, LinuxPerf.PERF_EVENT_IOC_DISABLE)
        enabled = false
        values = Vector{UInt64}(undef, length(names) + 3)
        read!(first(streams), values)
        values[1] == length(names) ||
            error("perf-event group returned a different event count")
        records = [CounterRecord(name, values[index + 3], values[2], values[3])
                   for (index, name) in enumerate(names)]
        values[3] > 0 || return CounterResult(:unavailable, "counter_not_scheduled",
            CounterRecord[], thread_id, allowed)
        CounterResult(:complete, "", records, thread_id, allowed)
    finally
        try
            enabled && _ioctl(leader, LinuxPerf.PERF_EVENT_IOC_DISABLE)
        finally
            _close_streams(streams)
        end
    end
end

include("provider.jl")

end
