const PROCESS_MEMORY_SCHEMA = "perfchecker-process-memory/1"
const EXTERNAL_MEMORY_SCHEMA = "perfchecker-external-memory/1"
const RESOURCE_ENVELOPE_SCHEMA = "perfchecker-resource-envelope/1"

const OptionalByteCount = Union{Nothing, UInt64}

"A point-in-time operating-system view of one process' memory usage."
struct ProcessMemorySnapshot
    schema_version::String
    pid::Int
    timestamp_ns::UInt64
    rss_bytes::OptionalByteCount
    peak_rss_bytes::OptionalByteCount
    private_bytes::OptionalByteCount
    provider::String
    status::Symbol
    message::String
end

function ProcessMemorySnapshot(pid::Integer, timestamp_ns::Integer;
        rss_bytes = nothing, peak_rss_bytes = nothing, private_bytes = nothing,
        provider::AbstractString = "fixture", status::Symbol = :observed,
        message::AbstractString = "")
    status in (:observed, :unavailable) || throw(ArgumentError(
        "process-memory status must be :observed or :unavailable"))
    function normalize(value, name)
        if value === nothing
            nothing
        elseif value isa Integer && value >= 0
            UInt64(value)
        else
            throw(ArgumentError("$name must be a non-negative integer or nothing"))
        end
    end
    rss = normalize(rss_bytes, "rss_bytes")
    peak = normalize(peak_rss_bytes, "peak_rss_bytes")
    private = normalize(private_bytes, "private_bytes")
    status === :observed && all(isnothing, (rss, peak, private)) &&
        throw(ArgumentError(
            "an observed process-memory snapshot must contain at least one counter"))
    return ProcessMemorySnapshot(PROCESS_MEMORY_SCHEMA, Int(pid), UInt64(timestamp_ns),
        rss, peak, private, String(provider), status, String(message))
end

function _unavailable_process_memory(pid::Integer, provider::AbstractString,
        message::AbstractString)
    return ProcessMemorySnapshot(pid, time_ns(); provider, status = :unavailable,
        message)
end

function _windows_size_t(buffer::Vector{UInt8}, offset::Int)
    GC.@preserve buffer begin
        pointer_at = pointer(buffer, offset + 1)
        return Sys.WORD_SIZE == 64 ?
               unsafe_load(Ptr{UInt64}(pointer_at)) :
               UInt64(unsafe_load(Ptr{UInt32}(pointer_at)))
    end
end

function _windows_process_memory_snapshot(pid::Integer)
    requested_pid = Int(pid)
    requested_pid > 0 || return _unavailable_process_memory(
        requested_pid, "windows-psapi", "process id must be positive")
    current = requested_pid == getpid()
    handle = if current
        ccall((:GetCurrentProcess, "kernel32"), Ptr{Cvoid}, ())
    else
        # PROCESS_QUERY_LIMITED_INFORMATION. GetProcessMemoryInfo documents this
        # access right on supported Windows versions.
        ccall((:OpenProcess, "kernel32"), Ptr{Cvoid},
            (UInt32, Cint, UInt32), UInt32(0x1000), Cint(0), UInt32(requested_pid))
    end
    handle == C_NULL && return _unavailable_process_memory(requested_pid,
        "windows-psapi", "OpenProcess failed with Windows error " * string(
            ccall((:GetLastError, "kernel32"), UInt32, ())))

    size_t_bytes = Sys.WORD_SIZE ÷ 8
    buffer_size = 8 + 9 * size_t_bytes
    buffer = zeros(UInt8, buffer_size)
    ok = GC.@preserve buffer begin
        unsafe_store!(Ptr{UInt32}(pointer(buffer)), UInt32(buffer_size))
        ccall((:GetProcessMemoryInfo, "psapi"), Cint,
            (Ptr{Cvoid}, Ptr{Cvoid}, UInt32), handle, pointer(buffer),
            UInt32(buffer_size))
    end
    error_code = ok == 0 ? ccall((:GetLastError, "kernel32"), UInt32, ()) : UInt32(0)
    current || ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), handle)
    ok == 0 && return _unavailable_process_memory(requested_pid,
        "windows-psapi", "GetProcessMemoryInfo failed with Windows error $error_code")

    peak_working_set = _windows_size_t(buffer, 8)
    working_set = _windows_size_t(buffer, 8 + size_t_bytes)
    private_usage = _windows_size_t(buffer, 8 + 8 * size_t_bytes)
    return ProcessMemorySnapshot(requested_pid, time_ns();
        rss_bytes = working_set, peak_rss_bytes = peak_working_set,
        private_bytes = private_usage, provider = "windows-psapi")
end

function _linux_kibibytes(document::AbstractString, key::AbstractString)
    prefix = String(key) * ":"
    for line in eachline(IOBuffer(document))
        startswith(line, prefix) || continue
        fields = split(strip(line[(length(prefix) + 1):end]))
        isempty(fields) && return nothing
        value = tryparse(UInt64, fields[1])
        value === nothing && return nothing
        length(fields) == 1 && return value
        lowercase(fields[2]) == "kb" && return value * UInt64(1024)
        return nothing
    end
    return nothing
end

function _linux_private_bytes(pid::Integer)
    path = "/proc/$(Int(pid))/smaps_rollup"
    isfile(path) || return nothing
    document = try
        read(path, String)
    catch
        return nothing
    end
    fields = ("Private_Clean", "Private_Dirty", "Private_Hugetlb")
    values = OptionalByteCount[_linux_kibibytes(document, field) for field in fields]
    all(isnothing, values) && return nothing
    return sum(something(value, UInt64(0)) for value in values; init = UInt64(0))
end

function _linux_process_memory_snapshot(pid::Integer)
    requested_pid = Int(pid)
    path = "/proc/$requested_pid/status"
    document = try
        read(path, String)
    catch error
        return _unavailable_process_memory(requested_pid, "linux-proc-status",
            sprint(showerror, error))
    end
    rss = _linux_kibibytes(document, "VmRSS")
    peak = _linux_kibibytes(document, "VmHWM")
    private = _linux_private_bytes(requested_pid)
    provider = private === nothing ? "linux-proc-status" :
               "linux-proc-status+smaps-rollup"
    all(isnothing, (rss, peak, private)) && return _unavailable_process_memory(
        requested_pid, provider, "Linux process counters were absent")
    return ProcessMemorySnapshot(requested_pid, time_ns(); rss_bytes = rss,
        peak_rss_bytes = peak, private_bytes = private, provider)
end

"Report which process-memory counters PerfChecker can observe on this platform."
function process_memory_capabilities()
    if Sys.iswindows()
        counters = ["rss_bytes", "peak_rss_bytes", "private_bytes"]
        provider = "windows-psapi"
    elseif Sys.islinux()
        counters = [
            "rss_bytes", "peak_rss_bytes", "private_bytes_when_smaps_rollup_is_readable"]
        provider = "linux-proc-status+smaps-rollup"
    else
        counters = String[]
        provider = "unavailable"
    end
    return Dict{String, Any}(
        "schema_version" => "perfchecker-process-memory-capabilities/1",
        "supported" => !isempty(counters), "provider" => provider,
        "counters" => counters,
        "peak_semantics" => "process lifetime high-water mark",
        "attribution" => "one isolated worker process")
end

"Take a non-throwing memory snapshot for `pid`; unsupported counters remain `nothing`."
function process_memory_snapshot(pid::Integer = getpid(); strict::Bool = false)
    snapshot = if Sys.iswindows()
        _windows_process_memory_snapshot(pid)
    elseif Sys.islinux()
        _linux_process_memory_snapshot(pid)
    else
        _unavailable_process_memory(pid, "unavailable",
            "process memory counters are unavailable on $(Sys.KERNEL)")
    end
    strict && snapshot.status === :unavailable && throw(ErrorException(snapshot.message))
    return snapshot
end

"Return the portable `perfchecker-process-memory/1` representation of a snapshot."
function process_memory_snapshot_dict(snapshot::ProcessMemorySnapshot)
    return Dict{String, Any}(
        "schema_version" => snapshot.schema_version, "pid" => snapshot.pid,
        "timestamp_ns" => snapshot.timestamp_ns, "rss_bytes" => snapshot.rss_bytes,
        "peak_rss_bytes" => snapshot.peak_rss_bytes,
        "private_bytes" => snapshot.private_bytes, "provider" => snapshot.provider,
        "status" => string(snapshot.status), "message" => snapshot.message)
end

"A versioned workload-owned view of native or otherwise external memory."
struct ExternalMemorySnapshot
    schema_version::String
    timestamp_ns::UInt64
    live_bytes::OptionalByteCount
    reserved_bytes::OptionalByteCount
    allocated_bytes_total::OptionalByteCount
    freed_bytes_total::OptionalByteCount
    provider::String
    status::Symbol
    message::String
end

function _unavailable_external_memory(message::AbstractString = "no external-memory probe")
    return ExternalMemorySnapshot(EXTERNAL_MEMORY_SCHEMA, time_ns(), nothing, nothing,
        nothing, nothing, "unavailable", :unavailable, String(message))
end

function _external_field(raw, name::String, default = nothing)
    if raw isa AbstractDict
        haskey(raw, name) && return raw[name]
        haskey(raw, Symbol(name)) && return raw[Symbol(name)]
    elseif raw isa NamedTuple
        symbol = Symbol(name)
        hasproperty(raw, symbol) && return getproperty(raw, symbol)
    end
    return default
end

function _external_byte_count(raw, name::String)
    value = _external_field(raw, name, nothing)
    value === nothing && return nothing
    value isa Integer && value >= 0 || throw(ArgumentError(
        "external-memory field $name must be a non-negative integer or nothing"))
    return UInt64(value)
end

"Normalize a dictionary or named tuple implementing `perfchecker-external-memory/1`."
function external_memory_snapshot(raw; provider::AbstractString = "workload")
    raw === nothing && return _unavailable_external_memory()
    raw isa ExternalMemorySnapshot && return raw
    raw isa AbstractDict || raw isa NamedTuple ||
        throw(ArgumentError(
            "external-memory probe must return a dictionary, named tuple, or nothing"))
    schema = String(_external_field(raw, "schema_version", ""))
    schema == EXTERNAL_MEMORY_SCHEMA || throw(ArgumentError(
        "external-memory probe must declare schema_version=$EXTERNAL_MEMORY_SCHEMA"))
    token = lowercase(String(_external_field(raw, "status", "observed")))
    if token in ("unavailable", "unsupported", "missing")
        message = String(_external_field(
            raw, "message", "external-memory probe unavailable"))
        return _unavailable_external_memory(message)
    end
    token in ("observed", "available", "pass", "passed", "ok") ||
        throw(ArgumentError("unknown external-memory status $token"))
    live = _external_byte_count(raw, "live_bytes")
    reserved = _external_byte_count(raw, "reserved_bytes")
    allocated = _external_byte_count(raw, "allocated_bytes_total")
    freed = _external_byte_count(raw, "freed_bytes_total")
    all(isnothing, (live, reserved, allocated, freed)) && throw(ArgumentError(
        "an observed external-memory snapshot must contain at least one counter"))
    timestamp = _external_field(raw, "timestamp_ns", time_ns())
    timestamp isa Integer && timestamp >= 0 || throw(ArgumentError(
        "external-memory timestamp_ns must be a non-negative integer"))
    actual_provider = String(_external_field(raw, "provider", provider))
    message = String(_external_field(raw, "message", ""))
    return ExternalMemorySnapshot(EXTERNAL_MEMORY_SCHEMA, UInt64(timestamp), live,
        reserved, allocated, freed, actual_provider, :observed, message)
end

"Return the portable `perfchecker-external-memory/1` representation of a snapshot."
function external_memory_snapshot_dict(snapshot::ExternalMemorySnapshot)
    return Dict{String, Any}(
        "schema_version" => snapshot.schema_version,
        "timestamp_ns" => snapshot.timestamp_ns, "live_bytes" => snapshot.live_bytes,
        "reserved_bytes" => snapshot.reserved_bytes,
        "allocated_bytes_total" => snapshot.allocated_bytes_total,
        "freed_bytes_total" => snapshot.freed_bytes_total,
        "provider" => snapshot.provider, "status" => string(snapshot.status),
        "message" => snapshot.message)
end

"One resource envelope around a backend collection in an isolated worker."
struct ResourceEnvelope
    schema_version::String
    elapsed_seconds::Float64
    process_before::ProcessMemorySnapshot
    process_after::ProcessMemorySnapshot
    external_before::ExternalMemorySnapshot
    external_after::ExternalMemorySnapshot
    external_requested::Bool
end

function ResourceEnvelope(elapsed_seconds::Real, process_before::ProcessMemorySnapshot,
        process_after::ProcessMemorySnapshot, external_before::ExternalMemorySnapshot,
        external_after::ExternalMemorySnapshot; external_requested::Bool = false)
    elapsed_seconds >= 0 || throw(ArgumentError(
        "resource-envelope elapsed time must be non-negative"))
    process_before.pid == process_after.pid || throw(ArgumentError(
        "resource-envelope snapshots refer to different processes"))
    return ResourceEnvelope(RESOURCE_ENVELOPE_SCHEMA, Float64(elapsed_seconds),
        process_before, process_after, external_before, external_after,
        external_requested)
end

"Return the portable `perfchecker-resource-envelope/1` representation."
function resource_envelope_dict(envelope::ResourceEnvelope)
    return Dict{String, Any}(
        "schema_version" => envelope.schema_version,
        "elapsed_seconds" => envelope.elapsed_seconds,
        "process_before" => process_memory_snapshot_dict(envelope.process_before),
        "process_after" => process_memory_snapshot_dict(envelope.process_after),
        "external_before" => external_memory_snapshot_dict(envelope.external_before),
        "external_after" => external_memory_snapshot_dict(envelope.external_after),
        "external_requested" => envelope.external_requested)
end

function _optional_difference(after::OptionalByteCount, before::OptionalByteCount)
    after === nothing && return nothing
    before === nothing && return nothing
    return Float64(Int128(after) - Int128(before))
end

function _optional_growth(after::OptionalByteCount, before::OptionalByteCount)
    delta = _optional_difference(after, before)
    delta === nothing && return nothing
    return max(delta, 0.0)
end

function _optional_monotonic_difference(after::OptionalByteCount,
        before::OptionalByteCount, name::AbstractString)
    after === nothing && return nothing
    before === nothing && return nothing
    after >= before || throw(ArgumentError("external-memory counter $name decreased"))
    return Float64(after - before)
end

"Flatten an envelope into explicitly named, non-conflated resource metrics."
function resource_envelope_metrics(envelope::ResourceEnvelope)
    before = envelope.process_before
    after = envelope.process_after
    external_before = envelope.external_before
    external_after = envelope.external_after
    return Dict{Symbol, Union{Nothing, Float64}}(
        :collector_seconds => envelope.elapsed_seconds,
        :rss_before_bytes => before.rss_bytes === nothing ? nothing :
                             Float64(before.rss_bytes),
        :rss_after_bytes => after.rss_bytes === nothing ? nothing : Float64(after.rss_bytes),
        :rss_delta_bytes => _optional_difference(after.rss_bytes, before.rss_bytes),
        :peak_rss_before_bytes => before.peak_rss_bytes === nothing ? nothing :
                                  Float64(before.peak_rss_bytes),
        :peak_rss_after_bytes => after.peak_rss_bytes === nothing ? nothing :
                                 Float64(after.peak_rss_bytes),
        :new_peak_rss_bytes => _optional_growth(after.peak_rss_bytes,
            before.peak_rss_bytes),
        :private_before_bytes => before.private_bytes === nothing ? nothing :
                                 Float64(before.private_bytes),
        :private_after_bytes => after.private_bytes === nothing ? nothing :
                                Float64(after.private_bytes),
        :private_delta_bytes => _optional_difference(after.private_bytes,
            before.private_bytes),
        :external_live_before_bytes => external_before.live_bytes === nothing ? nothing :
                                       Float64(external_before.live_bytes),
        :external_live_after_bytes => external_after.live_bytes === nothing ? nothing :
                                      Float64(external_after.live_bytes),
        :external_live_delta_bytes => _optional_difference(external_after.live_bytes,
            external_before.live_bytes),
        :external_reserved_before_bytes => external_before.reserved_bytes === nothing ?
                                           nothing : Float64(external_before.reserved_bytes),
        :external_reserved_after_bytes => external_after.reserved_bytes === nothing ?
                                          nothing : Float64(external_after.reserved_bytes),
        :external_reserved_delta_bytes => _optional_difference(
            external_after.reserved_bytes, external_before.reserved_bytes),
        :external_allocated_delta_bytes => _optional_monotonic_difference(
            external_after.allocated_bytes_total, external_before.allocated_bytes_total,
            "allocated_bytes_total"),
        :external_freed_delta_bytes => _optional_monotonic_difference(
            external_after.freed_bytes_total, external_before.freed_bytes_total,
            "freed_bytes_total"))
end

const RESOURCE_POLICY_SCHEMA = "perfchecker-resource-policy-evaluation/1"

"Evaluate absolute memory bounds and ownership balance for one resource envelope."
function evaluate_resource_envelope(envelope::ResourceEnvelope;
        upper_limits::AbstractDict = Dict{Symbol, Float64}(),
        require_process::Bool = false, require_external::Bool = false,
        require_external_balance::Bool = false)
    metrics = resource_envelope_metrics(envelope)
    violations = String[]
    unavailable = String[]
    require_process &&
        (envelope.process_before.status !== :observed ||
         envelope.process_after.status !== :observed) &&
        push!(unavailable, "process memory is unavailable")
    require_external &&
        (envelope.external_before.status !== :observed ||
         envelope.external_after.status !== :observed) &&
        push!(unavailable, "external memory is unavailable")

    normalized_limits = Dict{Symbol, Float64}()
    for (raw_metric, raw_limit) in pairs(upper_limits)
        metric = Symbol(raw_metric)
        haskey(metrics, metric) || throw(ArgumentError(
            "unknown resource metric $metric"))
        !(raw_limit isa Bool) && raw_limit isa Real && isfinite(raw_limit) &&
            raw_limit >= 0 ||
            throw(ArgumentError(
                "resource upper limit for $metric must be finite and non-negative"))
        limit = Float64(raw_limit)
        normalized_limits[metric] = limit
        value = metrics[metric]
        if value === nothing
            push!(unavailable, "resource metric $metric is unavailable")
        elseif value > limit
            push!(violations, "resource metric $metric is $value; upper limit is $limit")
        end
    end

    if require_external_balance
        allocated = metrics[:external_allocated_delta_bytes]
        freed = metrics[:external_freed_delta_bytes]
        live_delta = metrics[:external_live_delta_bytes]
        if allocated === nothing || freed === nothing
            push!(unavailable, "external allocation/free totals are unavailable")
        elseif allocated != freed
            push!(violations,
                "external allocation/free delta is unbalanced ($allocated allocated, $freed freed)")
        end
        if live_delta === nothing
            push!(unavailable, "external live-byte delta is unavailable")
        elseif live_delta > 0
            push!(violations, "external live bytes grew by $live_delta")
        end
    end

    unique!(violations)
    unique!(unavailable)
    status = !isempty(violations) ? "failed" :
             !isempty(unavailable) ? "unavailable" : "passed"
    message = status == "failed" ? join(violations, "; ") :
              status == "unavailable" ? join(unavailable, "; ") : ""
    return Dict{String, Any}(
        "schema_version" => RESOURCE_POLICY_SCHEMA,
        "status" => status, "message" => message,
        "upper_limits" => Dict(string(key) => value
        for (key, value) in normalized_limits),
        "require_process" => require_process,
        "require_external" => require_external,
        "require_external_balance" => require_external_balance,
        "violations" => violations, "unavailable" => unavailable,
        "metrics" => Dict(string(key) => value for (key, value) in metrics))
end

"""
Return whether an `evaluate_resource_envelope` result has `status="passed"`. Missing status is treated as failure.
"""
function resource_policy_passed(evaluation::AbstractDict)
    get(evaluation, "status", "failed") == "passed"
end
