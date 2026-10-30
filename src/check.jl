"""
    initpkgs(::Val{backend}) -> Expr

Backend hook returning code that loads backend-specific packages inside each
worker. Extensions normally define methods such as
`PerfChecker.initpkgs(::Val{:benchmark})`.
"""
initpkgs(x) = quote
    nothing
end

"""
    prep(config::Dict, block::Expr, ::Val{backend}) -> Expr

Backend hook returning code run before the measured block. Its result is stored
as `config[:prep_result]` before `post` is called.
"""
prep(d, b, v) = quote
    nothing
end

"""
    check(config::Dict, block::Expr, ::Val{backend}) -> Expr

Backend hook returning code that performs the measurement. Its result is stored
as `config[:check_result]` before `post` is called.
"""
check(d, b, v) = quote
    nothing
end

"""
    post(config::Dict, ::Val{backend})

Backend hook that selects or transforms the worker result before it is converted
to a `TypedTables.Table` by `to_table`.
"""
post(d, v) = nothing

"""
    default_options(::Val{backend}) -> Dict

Backend hook returning default configuration values. These defaults are merged
with the user dictionary before `normalize_config` validates shared options.
"""
default_options(v) = Dict()

"""
    cleanup(config::Dict, ::Val{backend})

Backend hook run after workers have stopped. Backends that create process-exit
artifacts can use it to remove files that are flushed only when a worker exits.
"""
cleanup(d, v) = nothing

"""
    stop_before_post(::Val{backend}) -> Bool

Backend hook for measurements whose artifacts are flushed when the worker
process exits.
"""
stop_before_post(v) = false

initpkgs(x::Symbol) = initpkgs(Val(x))
prep(d::Dict, b::Expr, v::Symbol) = prep(d, b, Val(v))
check(d::Dict, b::Expr, v::Symbol) = check(d, b, Val(v))
post(d::Dict, v::Symbol) = post(d, Val(v))
cleanup(d::Dict, v::Symbol) = cleanup(d, Val(v))
stop_before_post(v::Symbol) = stop_before_post(Val(v))

function default_options(d::Dict, v::Symbol)
    di = default_options(Val(v))
    return merge(di, d)
end

function run_targets(config::CheckConfig)
    pkgs = if config.packages === nothing
        config.include_current ? PackageSpec[PackageSpec()] : PackageSpec[]
    else
        [PackageSpec(name = config.packages.name, version = i)
         for i in get_versions(config.packages)[2]]
    end

    targets = [RunTarget(pkg, something(pkg.name, "current"), false) for pkg in pkgs]
    if config.devops !== nothing
        pkg = config.devops isa Tuple ? config.devops[1] : config.devops
        name = pkg isa PackageSpec ? pkg.name : String(pkg)
        push!(targets, RunTarget(PackageSpec(name = name, version = "dev"), name, true))
    end
    return targets
end

struct CheckCleanupFailure <: Exception
    errors::Vector{Any}
    directories::Vector{String}
    retained_workers::Vector{Worker}
    primary::Union{Nothing, CapturedException}
end

function CheckCleanupFailure(errors, directories)
    CheckCleanupFailure(convert(Vector{Any}, errors),
        convert(Vector{String}, directories), Worker[], nothing)
end

function Base.showerror(io::IO, error::CheckCleanupFailure)
    print(io, "PerfChecker cleanup incomplete")
    isempty(error.directories) || print(io, "; private inventories retained at ",
        join(error.directories, ", "))
    for cause in error.errors
        print(io, "; ")
        showerror(io, cause)
    end
end

function _cleanup_check_directories!(
        temp_roots, allocation_artifacts, retained_roots, failures;
        retained_workers = Worker[])
    for (i, root) in temp_roots
        if !(i in retained_roots)
            try
                rm(root; recursive = true, force = true)
            catch error
                push!(retained_roots, i)
                push!(failures, error)
            end
        end
        if i in retained_roots
            try
                haskey(allocation_artifacts, i) &&
                    _retain_allocation_inventory!(allocation_artifacts[i])
            catch error
                # The saved journal remains useful even if writing the inventory
                # metadata also fails. Never hide this error as cancellation.
                push!(failures, error)
                @warn "Could not save allocation inventory metadata" directory=root exception=error
            end
            @warn "PerfChecker cleanup incomplete; private inventory retained" directory=root
        end
    end
    isempty(failures) || throw(CheckCleanupFailure(failures,
        [temp_roots[i] for i in retained_roots if ispath(temp_roots[i])],
        retained_workers, nothing))
    nothing
end

"A worker's terminal observation failed PerfChecker's acceptance criteria."
struct WorkerShutdownFailure <: Exception
    report::Malt.WorkerShutdownReport
    reasons::Vector{String}
end

function Base.showerror(io::IO, error::WorkerShutdownFailure)
    report = error.report
    print(io, "PerfChecker worker ", report.pid, " shutdown was not qualified",
        " (exitcode=", report.exitcode, ", termsignal=", report.termsignal, ")")
    for reason in error.reasons
        print(io, "; ", reason)
    end
    nothing
end

function _worker_resources_closed(report::Malt.WorkerShutdownReport)
    report.complete && report.process_exited && report.socket_closed &&
        report.stdout_closed && report.stderr_closed && report.tasks_done &&
        report.active_senders == 0 && report.pending_replies == 0 &&
        all(task -> task.done, report.tasks)
end

function _qualify_worker_shutdown(report::Malt.WorkerShutdownReport)
    reasons = String[]
    _worker_resources_closed(report) ||
        push!(reasons, "resources or manager tasks remain owned")
    report.exitcode == 0 || push!(reasons, "worker did not exit with code zero")
    report.termsignal == 0 || push!(reasons, "worker terminated with a signal")
    isempty(report.errors) || append!(reasons, report.errors)
    all(task -> !task.failed, report.tasks) || push!(reasons, "a manager task failed")
    report.failed_replies == 0 || push!(reasons, "an asynchronous RPC failed")
    isempty(reasons) || throw(WorkerShutdownFailure(report, reasons))
    report
end

function safe_stop(worker::Worker; exit_timeout::Real = 15.0,
        term_timeout::Real = 15.0, timeout::Real = exit_timeout + term_timeout + 20.0)
    # The report observes process exit, every retained task and the connections.
    # A PID which stopped running alone is not an accepted measurement outcome.
    report = Malt.shutdown(worker; exit_timeout, term_timeout, timeout,
        close_unmonitored = true)
    _qualify_worker_shutdown(report)
end

safe_cleanup(options, backend::Symbol) = cleanup(options, backend)

function _worker_shutdown_options(options)
    raw = get(options, :worker_shutdown, (;))
    raw isa Union{NamedTuple, AbstractDict} ||
        throw(ArgumentError(":worker_shutdown must be a NamedTuple or dictionary"))
    all(key -> key isa Symbol && key in (:timeout, :exit_timeout, :term_timeout),
        keys(raw)) ||
        throw(ArgumentError(":worker_shutdown accepts only timeout, exit_timeout and term_timeout"))
    function duration(value, name)
        value isa Real && !(value isa Bool) ||
            throw(ArgumentError("worker shutdown $name must be a finite nonnegative duration"))
        seconds = Float64(value)
        isfinite(seconds) && seconds >= 0 && seconds * 1.0e9 < Float64(typemax(Int64)) ||
            throw(ArgumentError("worker shutdown $name must fit a finite nonnegative deadline"))
        seconds
    end
    exit_timeout = duration(get(raw, :exit_timeout, 15.0), :exit_timeout)
    term_timeout = duration(get(raw, :term_timeout, 15.0), :term_timeout)
    timeout = duration(get(raw, :timeout, exit_timeout + term_timeout + 20.0), :timeout)
    (; exit_timeout, term_timeout, timeout)
end

"A saved table lacks a matching, successful worker-shutdown receipt."
struct HistoricalCacheUnqualified <: Exception
    path::String
    reason::String
end

function Base.showerror(io::IO, error::HistoricalCacheUnqualified)
    print(io, "Historical PerfChecker cache is not shutdown-qualified: ",
        error.path, "; ", error.reason,
        ". Read it explicitly with csv_to_table or select a new run identity.")
end

const WORKER_SHUTDOWN_CACHE_SCHEMA = "perfchecker-worker-shutdown/1"

function _worker_qualification_sources(root)
    sources = Dict{String, String}()
    for (directory, _, names) in walkdir(joinpath(root, "src"))
        for name in names
            endswith(name, ".jl") || continue
            path = joinpath(directory, name)
            Base.include_dependency(path)
            sources[replace(relpath(path, root), '\\' => '/')] = bytes2hex(SHA.sha256(read(path)))
        end
    end
    project = joinpath(root, "Project.toml")
    Base.include_dependency(project)
    sources["Project.toml"] = bytes2hex(SHA.sha256(read(project)))
    Dict{String, Any}("version" => String(TOML.parsefile(project)["version"]),
        "sources" => sources)
end

function _worker_qualification_identity()
    Dict{String, Any}(
        "PerfChecker" => _worker_qualification_sources(dirname(@__DIR__)),
        "Malt" => _worker_qualification_sources(dirname(dirname(pathof(Malt)))))
end

# This records the source tree observed when this module is loaded. The same
# tree must still be present before collection and before publishing a receipt.
# It is provenance for a frozen checkout, not attestation of arbitrary hot reloads.
const _LOADED_WORKER_QUALIFICATION_IDENTITY = _worker_qualification_identity()

function _check_worker_qualification_identity(expected)
    current = _worker_qualification_identity()
    current == expected || throw(ArgumentError(
        "PerfChecker or Malt sources changed; reload the frozen packages before collection"))
    current
end

function _worker_shutdown_receipt_path(root, result)
    joinpath(root, "metadata", "worker-shutdown", string(result) * ".json")
end

function _worker_shutdown_report_dict(report::Malt.WorkerShutdownReport)
    Dict{String, Any}("pid" => report.pid, "stage" => string(report.stage),
        "process_exited" => report.process_exited, "exitcode" => report.exitcode,
        "termsignal" => report.termsignal, "socket_closed" => report.socket_closed,
        "stdout_closed" => report.stdout_closed, "stderr_closed" => report.stderr_closed,
        "tasks_done" => report.tasks_done, "pending_replies" => report.pending_replies,
        "active_senders" => report.active_senders, "failed_replies" => report.failed_replies,
        "completed_replies" => report.completed_replies,
        "unmonitored_discarded" => report.unmonitored_discarded,
        "errors" => collect(report.errors), "complete" => report.complete,
        "tasks" => [Dict("name" => string(task.name), "done" => task.done,
                        "failed" => task.failed) for task in report.tasks])
end

function _qualified_cached_shutdown(report)
    report isa AbstractDict || return false
    for key in ("complete", "process_exited", "socket_closed", "stdout_closed",
        "stderr_closed", "tasks_done")
        get(report, key, nothing) === true || return false
    end
    for key in (
        "exitcode", "termsignal", "active_senders", "pending_replies", "failed_replies")
        value = get(report, key, nothing)
        value isa Integer && !(value isa Bool) && value == 0 || return false
    end
    errors = get(report, "errors", nothing)
    errors isa AbstractVector && isempty(errors) || return false
    tasks = get(report, "tasks", nothing)
    tasks isa AbstractVector && !isempty(tasks) || return false
    all(
        task -> task isa AbstractDict && get(task, "done", nothing) === true &&
                    get(task, "failed", nothing) === false,
        tasks)
end

function _read_worker_shutdown_receipt(root, result, csv_path;
        allocation_profile::Bool = false)
    path = _worker_shutdown_receipt_path(root, result)
    isfile(path) || throw(HistoricalCacheUnqualified(String(csv_path),
        "worker-shutdown receipt is missing"))
    try
        document = _json_parsefile(path)
        document isa AbstractDict || error("receipt is not an object")
        get(document, "schema_version", nothing) == WORKER_SHUTDOWN_CACHE_SCHEMA ||
            error("unsupported receipt schema")
        get(document, "result_uuid", nothing) == string(result) ||
            error("result UUID mismatch")
        get(document, "csv_sha256", nothing) == bytes2hex(SHA.sha256(read(csv_path))) ||
            error("saved table digest mismatch")
        if allocation_profile
            digest = get(document, "allocation_profile_sha256", nothing)
            digest isa AbstractString && occursin(r"^[0-9a-f]{64}$", digest) ||
                error("allocation-profile payload digest is missing or invalid")
        end
        identity = get(document, "code_identity", nothing)
        identity isa AbstractDict || error("source identity is missing")
        for package in ("PerfChecker", "Malt")
            entry = get(identity, package, nothing)
            entry isa AbstractDict || error("$package identity is missing")
            get(entry, "version", nothing) isa AbstractString ||
                error("$package version is missing")
            sources = get(entry, "sources", nothing)
            sources isa AbstractDict && !isempty(sources) ||
                error("$package sources are missing")
        end
        get(document, "code_identity_sha256", nothing) == _content_digest(identity) ||
            error("source identity digest mismatch")
        get(document, "observed_at_utc", nothing) isa AbstractString ||
            error("observation time is missing")
        _qualified_cached_shutdown(get(document, "report", nothing)) ||
            error("worker shutdown did not satisfy the terminal contract")
        return Dict{String, Any}("origin" => "qualified_cache", "receipt_path" => path,
            "receipt" => document)
    catch error
        error isa InterruptException && rethrow()
        throw(HistoricalCacheUnqualified(String(csv_path), sprint(showerror, error)))
    end
end

function _write_worker_shutdown_receipt(root, result, csv_path, report, identity;
        allocation_profile::Bool = false)
    _qualify_worker_shutdown(report)
    document = Dict{String, Any}("schema_version" => WORKER_SHUTDOWN_CACHE_SCHEMA,
        "result_uuid" => string(result), "csv_sha256" => bytes2hex(SHA.sha256(read(csv_path))),
        "code_identity" => deepcopy(identity), "code_identity_sha256" => _content_digest(identity),
        "observed_at_utc" => string(Dates.now(Dates.UTC)),
        "report" => _worker_shutdown_report_dict(report))
    if allocation_profile
        document["allocation_profile_sha256"] = bytes2hex(
            SHA.sha256(read(_allocation_cache_path(csv_path))))
    end
    path = _worker_shutdown_receipt_path(root, result)
    mkpath(dirname(path))
    temporary, stream = mktemp(dirname(path); cleanup = false)
    try
        close(stream)
        _write_json(temporary, document; canonical = true)
        # Same-directory rename publishes the complete receipt last. No fsync or
        # power-loss durability is implied by this namespace-atomic operation.
        Base.Filesystem.rename(temporary, path)
    finally
        isopen(stream) && close(stream)
        ispath(temporary) && rm(temporary; force = true)
    end
    Dict{String, Any}("origin" => "current_run", "receipt_path" => path,
        "receipt" => document)
end

function _shutdown_report(error)
    error isa Union{WorkerShutdownFailure, Malt.ShutdownIncompleteException,
        Malt.WorkerStartupException} ? error.report : nothing
end

function _contains_incomplete_shutdown(error, seen = Base.IdSet{Any}())
    error in seen && return false
    push!(seen, error)
    report = _shutdown_report(error)
    report === nothing || return !_worker_resources_closed(report)
    if error isa TaskFailedException
        return any(item -> _contains_incomplete_shutdown(item.exception, seen),
            Base.current_exceptions(error.task))
    elseif error isa CompositeException
        return any(cause -> _contains_incomplete_shutdown(cause, seen), error.exceptions)
    elseif error isa CheckCleanupFailure
        return !isempty(error.retained_workers) ||
               any(cause -> _contains_incomplete_shutdown(cause, seen), error.errors)
    end
    false
end

function _same_failure(first, second)
    first === second || (first isa TaskFailedException && second isa TaskFailedException &&
     first.task === second.task)
end

function _append_check_failure!(failures, error)
    any(previous -> _same_failure(previous, error), failures) || push!(failures, error)
    nothing
end

function _combine_check_cleanup_failure(primary, backtrace, cleanup_error)
    errors = Any[primary]
    directories = String[]
    workers = Worker[]
    if primary isa CheckCleanupFailure
        append!(directories, primary.directories)
        append!(workers, primary.retained_workers)
    end
    if cleanup_error isa CheckCleanupFailure
        for cause in cleanup_error.errors
            _append_check_failure!(errors, cause)
        end
        append!(directories, cleanup_error.directories)
        append!(workers, cleanup_error.retained_workers)
    else
        _append_check_failure!(errors, cleanup_error)
    end
    CheckCleanupFailure(errors, unique(directories), unique(workers),
        CapturedException(primary, backtrace))
end

function _stop_check_worker!(reports, index, worker, shutdown_options)
    try
        report = safe_stop(worker; shutdown_options...)
        reports[index] = report
        report
    catch error
        report = _shutdown_report(error)
        # A complete but abnormal exit is still a failure, but requires no
        # second stop merely to rediscover the same terminal status.
        report === nothing || !_worker_resources_closed(report) ||
            (reports[index] = report)
        rethrow()
    end
end

function _retain_related_check_roots!(retained_roots, temp_roots, error)
    error isa CheckCleanupFailure || return nothing
    for (index, root) in temp_roots
        any(
            path -> PerfCheckerProfileRuntime.within_root(root, path) ||
                PerfCheckerProfileRuntime.within_root(path, root),
            error.directories) &&
            push!(retained_roots, index)
    end
    nothing
end

function _retain_cleanup_dependency!(error::CheckCleanupFailure, environment,
        owned_roots, retained_roots)
    (isempty(error.directories) && isempty(error.retained_workers) &&
     !_contains_incomplete_shutdown(error)) && return nothing
    for root in owned_roots
        if PerfCheckerProfileRuntime.within_root(environment, root)
            push!(retained_roots, root)
            root in error.directories || push!(error.directories, root)
        end
    end
    nothing
end

function _cleanup_preparation_roots!(roots, retained_roots,
        primary_error = nothing, primary_backtrace = nothing)
    failures = Any[]
    for root in roots
        root in retained_roots && continue
        try
            rm(root; recursive = true, force = true)
        catch error
            push!(retained_roots, root)
            _append_check_failure!(failures, error)
        end
    end
    isempty(failures) && return nothing
    cleanup_error = CheckCleanupFailure(failures,
        [root for root in retained_roots if ispath(root)])
    primary_error === nothing && throw(cleanup_error)
    throw(_combine_check_cleanup_failure(primary_error, primary_backtrace, cleanup_error))
end

function _finish_check_cleanup!(creation_tasks, creation_errors, procs, worker_indices,
        reports, shutdown_options, backend, options, cleanup_options,
        temp_roots, allocation_artifacts; primary_error = nothing, keep_roots = false)
    failures = Any[]
    retained_roots = Set{Int}()
    unsafe_roots = Set{Int}()
    retained_workers = Worker[]
    _retain_related_check_roots!(retained_roots, temp_roots, primary_error)

    # A cancelled constructor wait does not cancel the constructor. Drain every
    # task before observing the worker slots or removing any environment.
    for (index, task) in creation_tasks
        try
            wait(task)
        catch error
            cause = creation_errors[index] === nothing ? error : creation_errors[index]
            incomplete = _contains_incomplete_shutdown(cause)
            if incomplete
                push!(retained_roots, index)
                push!(unsafe_roots, index)
            end
            if incomplete || !_same_failure(error, primary_error)
                _append_check_failure!(failures, error)
            end
        end
    end
    for index in worker_indices
        worker = procs[index]
        if worker === nothing
            cause = creation_errors[index]
            if cause !== nothing && _contains_incomplete_shutdown(cause)
                push!(retained_roots, index)
                push!(unsafe_roots, index)
                isempty(creation_tasks) && _append_check_failure!(failures, cause)
            end
            continue
        end
        haskey(reports, index) && continue
        try
            _stop_check_worker!(reports, index, worker, shutdown_options)
        catch error
            _append_check_failure!(failures, error)
            report = _shutdown_report(error)
            if report === nothing || !_worker_resources_closed(report)
                push!(retained_roots, index)
                push!(unsafe_roots, index)
                push!(retained_workers, worker)
            end
        end
    end

    if backend !== nothing && backend !== :alloc
        # Cleanup hooks promise that their workers have stopped. Do not invoke
        # a destructive hook against a still-owned process; defer it with the
        # retained environment instead. Independent closed targets still run.
        if isempty(unsafe_roots)
            try
                safe_cleanup(options, backend)
            catch error
                _append_check_failure!(failures, error)
                union!(retained_roots, keys(temp_roots))
            end
        end
        for (index, target_options) in enumerate(cleanup_options)
            index in unsafe_roots && continue
            try
                safe_cleanup(target_options, backend)
            catch error
                _append_check_failure!(failures, error)
                haskey(temp_roots, index) && push!(retained_roots, index)
            end
        end
    end
    for (index, artifacts) in allocation_artifacts
        index in unsafe_roots && continue
        try
            _cleanup_allocation_artifacts!(artifacts)
        catch error
            push!(retained_roots, index)
            _append_check_failure!(failures, error)
        end
    end
    keep_roots && isempty(failures) && return nothing
    _cleanup_check_directories!(temp_roots, allocation_artifacts,
        retained_roots, failures; retained_workers)
    nothing
end

function _external_memory_probe(worker, options::Dict{Symbol, Any})
    probe = get(options, :external_memory_probe, nothing)
    probe === nothing && return _unavailable_external_memory()
    probe isa Symbol || probe isa AbstractString ||
        throw(ArgumentError(
            ":external_memory_probe must be a function name as Symbol or String"))
    function_name = Symbol(probe)
    function_literal = QuoteNode(function_name)
    raw = try
        remote_eval_fetch(Main,
            worker,
            quote
                function_name = $function_literal
                isdefined(Main, function_name) || error(
                    "external-memory probe " * string(function_name) * " is not defined")
                callback = getfield(Main, function_name)
                applicable(callback) || error(
                    "external-memory probe " * string(function_name) *
                    " must accept no arguments")
                Base.invokelatest(callback)
            end)
    catch error
        Bool(get(options, :external_memory_required, false)) && rethrow()
        return _unavailable_external_memory(sprint(showerror, error))
    end
    return try
        external_memory_snapshot(raw; provider = string(function_name))
    catch error
        Bool(get(options, :external_memory_required, false)) && rethrow()
        _unavailable_external_memory(sprint(showerror, error))
    end
end

function _resource_policy_requested(options::Dict{Symbol, Any})
    limits = get(options, :resource_upper_limits, Dict{Symbol, Float64}())
    limits isa AbstractDict || throw(ArgumentError(
        ":resource_upper_limits must be a dictionary"))
    return !isempty(limits) || Bool(get(options, :require_process_resources, false)) ||
           Bool(get(options, :require_external_balance, false))
end

function _apply_resource_policy!(qualification::Dict{String, Any},
        envelope::ResourceEnvelope, options::Dict{Symbol, Any})
    _resource_policy_requested(options) || return qualification
    evaluation = evaluate_resource_envelope(envelope;
        upper_limits = get(options, :resource_upper_limits,
            Dict{Symbol, Float64}()),
        require_process = Bool(get(options, :require_process_resources, false)),
        require_external = Bool(get(options, :external_memory_required, false)),
        require_external_balance = Bool(
            get(options, :require_external_balance, false)))
    qualification["resource_policy"] = evaluation
    passed = resource_policy_passed(evaluation)
    qualification["performance"] = Dict{String, Any}(
        "status" => passed ? "passed" : "failed",
        "message" => passed ? "" : String(evaluation["message"]),
        "evidence" => evaluation)
    _finalize_qualification!(qualification)
    return qualification
end

function _drop_incompatible_manifest!(environment::AbstractString;
        runtime::VersionNumber = VERSION)
    manifest = joinpath(environment, "Manifest.toml")
    isfile(manifest) || return false
    metadata = try
        parse(read(manifest, String))
    catch
        return false
    end
    recorded = get(metadata, "julia_version", nothing)
    recorded === nothing && return false
    version = try
        VersionNumber(String(recorded))
    catch
        return false
    end
    (version.major, version.minor) == (runtime.major, runtime.minor) && return false
    rm(manifest; force = true)
    return true
end

function _install_target!(worker, target::RunTarget, options::Dict{Symbol, Any})
    remote_eval_wait(Main, worker,
        quote
            d = $options
            is_dev = $(target.is_dev)
            target_spec = $(target.spec)
            target_label = $(target.label)
            pkg_io = get(d, :quiet, false) ? devnull : stderr
            if is_dev
                pkg = d[:devops]
                try
                    Pkg.rm(target_label; io = pkg_io)
                catch
                end
                if get(d, :target_install, :develop) === :add
                    Pkg.add(pkg; io = pkg_io)
                elseif pkg isa Tuple
                    Pkg.develop(pkg[1]; pkg[2]..., io = pkg_io)
                    haskey(d, :extra_devops) &&
                        Pkg.develop(d[:extra_devops]; io = pkg_io)
                else
                    dev_specs = haskey(d, :extra_devops) ?
                                vcat([pkg], d[:extra_devops]) : [pkg]
                    Pkg.develop(dev_specs; io = pkg_io)
                end
            elseif !isnothing(target_spec.name)
                try
                    Pkg.rm(target_spec.name; io = pkg_io)
                catch
                end
                Pkg.add(target_spec; io = pkg_io)
            end
            if haskey(d, :extra_pkgs)
                extras = d[:extra_pkgs]
                extras = extras isa AbstractVector ? extras : [extras]
                specs = [spec isa NamedTuple ? Pkg.PackageSpec(; spec...) : spec
                         for spec in extras]
                Pkg.add(specs; io = pkg_io)
            end
            !is_dev && haskey(d, :extra_devops) &&
                Pkg.develop(d[:extra_devops]; io = pkg_io)
        end)
    return nothing
end

function _relocated_dependency_path(
        path, source_base, destination_base, source, destination)
    path isa AbstractString || throw(ArgumentError("dependency paths must be strings"))
    isabspath(path) && return String(path)
    absolute = normpath(abspath(source_base, path))
    resolved = ispath(absolute) ? realpath(absolute) : absolute
    source_root = realpath(source)
    if PerfCheckerProfileRuntime.within_root(absolute, source) &&
       PerfCheckerProfileRuntime.within_root(resolved, source_root)
        copied = joinpath(destination, relpath(absolute, source))
        return relpath(copied, destination_base)
    end
    absolute
end

function _local_repository_path(path)
    path isa AbstractString &&
        (isabspath(path) || !occursin(r"^[^/\\]+:", path))
end

"Materialize linked metadata and make only the private regular file writable."
function _privatize_metadata!(path, original)
    if islink(path)
        contents = read(original)
        rm(path)
        write(path, contents)
    end
    chmod(path, filemode(path) | 0o600)
    nothing
end

function _private_metadata_parent(path, destination)
    parent = dirname(path)
    while parent != destination
        islink(parent) && return false
        next = dirname(parent)
        next == parent && return false
        parent = next
    end
    true
end

function _relocate_check_metadata!(source, destination)
    manifests = Dict{String, String}()
    for name in readdir(source)
        occursin(r"^(Julia)?Manifest(?:-v[0-9]+\.[0-9]+)?\.toml$", name) || continue
        isfile(joinpath(source, name)) &&
            (manifests[abspath(source, name)] = abspath(destination, name))
    end
    for name in ("Project.toml", "JuliaProject.toml")
        original, copied = joinpath(source, name), joinpath(destination, name)
        isfile(original) || continue
        _privatize_metadata!(copied, original)
        project = TOML.parsefile(original)
        changed = false
        for entry in values(get(project, "sources", Dict()))
            entry isa AbstractDict || continue
            for key in ("path", "url")
                haskey(entry, key) || continue
                key == "url" && !_local_repository_path(entry[key]) && continue
                value = _relocated_dependency_path(
                    entry[key], source, destination, source, destination)
                changed |= value != entry[key]
                entry[key] = value
            end
        end
        if haskey(project, "manifest")
            manifest = abspath(source, String(project["manifest"]))
            isfile(manifest) ||
                throw(ArgumentError("explicit manifest is missing: $manifest"))
            internal = PerfCheckerProfileRuntime.within_root(manifest, source) ?
                       abspath(destination, relpath(manifest, source)) : nothing
            relocated = if haskey(manifests, manifest)
                manifests[manifest]
            elseif internal !== nothing &&
                   _private_metadata_parent(internal, destination)
                ispath(internal) || islink(internal) ||
                    throw(ArgumentError(
                        "explicit manifest was excluded from the worker environment: $manifest"))
                internal
            else
                private = mktempdir(destination; prefix = ".perfchecker-manifest-")
                target = joinpath(private, basename(manifest))
                cp(manifest, target; follow_symlinks = true)
                target
            end
            manifests[manifest] = relocated
            reference = relpath(relocated, destination)
            changed |= reference != project["manifest"]
            project["manifest"] = reference
        end
        changed && open(io -> TOML.print(io, project), copied, "w")
    end
    for (original, copied) in manifests
        _privatize_metadata!(copied, original)
        document = TOML.parsefile(original)
        dependencies = get(document, "deps", document)
        dependencies isa AbstractDict || continue
        changed = false
        for entries in values(dependencies)
            entries isa AbstractVector || continue
            for entry in entries
                entry isa AbstractDict || continue
                for key in ("path", "repo-url")
                    haskey(entry, key) || continue
                    key == "repo-url" && !_local_repository_path(entry[key]) && continue
                    value = _relocated_dependency_path(entry[key], dirname(original),
                        dirname(copied), source, destination)
                    changed |= value != entry[key]
                    entry[key] = value
                end
            end
        end
        changed && open(io -> TOML.print(io, document), copied, "w")
    end
    nothing
end

"Copy a worker environment, preserving the meaning of local dependency paths."
function _copy_check_environment(source, destination; exclude = String[])
    source, destination = abspath(source), abspath(destination)
    exclude isa AbstractVector && all(x -> x isa AbstractString, exclude) ||
        throw(ArgumentError("environment_excludes must be a vector of top-level names"))
    excluded = Set(String.(exclude))
    for name in excluded
        (isempty(name) || name in (".", "..") || any(c -> c in ('/', '\\', ':'), name)) &&
            throw(ArgumentError("environment_excludes accepts top-level names only"))
        (lowercase(name) in ("project.toml", "juliaproject.toml", "localpreferences.toml") ||
         occursin(r"^(julia)?manifest.*\.toml$", lowercase(name))) &&
            throw(ArgumentError("environment metadata cannot be excluded"))
    end
    ispath(destination) &&
        throw(ArgumentError("worker environment destination already exists"))
    mkpath(destination)
    try
        for name in readdir(source)
            name in excluded && continue
            cp(joinpath(source, name), joinpath(destination, name))
        end
        # Pkg and metadata relocation write into this private copy. Never follow
        # a copied directory link: its target may still belong to the seed.
        for (directory, _, _) in walkdir(destination; follow_symlinks = false)
            chmod(directory, filemode(directory) | 0o700)
        end
        _relocate_check_metadata!(source, destination)
    catch
        # This directory was created exclusively by this call.
        rm(destination; recursive = true, force = true)
        rethrow()
    end
    destination
end

"Prepare one immutable package target environment for reuse by fresh workers."
function _prepare_check_environment(config::Union{PerfConfig, CheckConfig})
    normalized = config isa CheckConfig ? config : normalize_config(config)
    targets = run_targets(normalized)
    length(targets) == 1 || throw(ArgumentError(
        "suite environment preparation requires exactly one package target"))
    options = legacy_options(normalized)
    shutdown_options = _worker_shutdown_options(options)
    root = mktempdir(; prefix = "perfchecker-prepared-", cleanup = false)
    environment = joinpath(root, "environment")
    procs = Any[nothing]
    creation_errors = Any[nothing]
    reports = Dict{Int, Malt.WorkerShutdownReport}()
    temp_roots = Dict(1 => root)
    artifacts = Dict{Int, AllocationArtifacts}()
    function finish(; primary_error = nothing, keep_roots = false)
        _finish_check_cleanup!(Pair{Int, Task}[], creation_errors, procs, [1],
            reports, shutdown_options, nothing, options, Dict{Symbol, Any}[],
            temp_roots, artifacts; primary_error, keep_roots)
    end
    try
        _copy_check_environment(normalized.path, environment;
            exclude = get(options, :environment_excludes, String[]))
        _drop_incompatible_manifest!(environment)
        procs[1] = Worker(;
            exeflags = ["-t $(normalized.threads)",
                "--project=$environment"])
        quiet = get(options, :quiet, false)
        remote_eval_wait(Main, procs[1],
            quote
                import Pkg
                ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
                $quiet && (Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true)
                Pkg.instantiate(; io = $quiet ? devnull : stderr)
            end)
        _install_target!(procs[1], only(targets), options)
    catch error
        backtrace = catch_backtrace()
        procs[1] === nothing && (creation_errors[1] = error)
        try
            finish(; primary_error = error)
        catch cleanup_error
            throw(_combine_check_cleanup_failure(error, backtrace, cleanup_error))
        end
        # Malt retains a constructor interruption until its rollback completes.
        # Only successful cleanup permits exposing that original cancellation.
        if error isa Malt.WorkerStartupException && error.cause isa InterruptException
            throw(error.cause)
        end
        rethrow()
    end
    finish(; keep_roots = true)
    return root, environment
end

function check_function(x::Symbol, d::Dict, block1, block2; qualification = nothing)
    return check_function(x, normalize_config(x, d), block1, block2; qualification)
end

function check_function(x::Symbol, config::CheckConfig, block1, block2;
        qualification = nothing)
    x == config.backend || throw(ArgumentError(
        "backend mismatch: requested $x but CheckConfig uses $(config.backend)"))
    di = legacy_options(config)
    shutdown_options = _worker_shutdown_options(di)
    code_identity = _check_worker_qualification_identity(_LOADED_WORKER_QUALIFICATION_IDENTITY)
    hwinfo = HwInfo()

    results = CheckerResult(
        Table[],
        hwinfo,
        config.tags,
        PackageSpec[],
        Dict{String, Any}[],
        Union{Nothing, ResourceEnvelope}[]
    )

    targets = run_targets(config)
    len = length(targets)

    collect_resources = Bool(get(di, :process_resources, false)) ||
                        haskey(di, :external_memory_probe)
    cached_paths = [!collect_resources && qualification === nothing && !target.is_dev &&
                    !isnothing(target.spec.name) ?
                    cached_output_path(
                        config, target.spec.name, target.spec.version, block1, block2, hwinfo) :
                    nothing for target in targets]
    cache_receipts = Dict{Int, Any}()
    # Validate the entire cache plan before admitting any worker, including a
    # mixed plan whose other targets are not cached. Legacy data is never replayed
    # implicitly merely because its terminal provenance is absent or damaged.
    for (index, path) in enumerate(cached_paths)
        target = targets[index]
        eligible = !collect_resources && qualification === nothing && !target.is_dev &&
                   !isnothing(target.spec.name)
        eligible || continue
        result = result_uuid(config, target.spec.name, target.spec.version,
            block1, block2, hwinfo)
        if path === nothing
            candidate = output_path(config.path, result)
            isfile(candidate) && throw(HistoricalCacheUnqualified(candidate,
                "saved table is not recorded in the cache index"))
            continue
        end
        cache_receipts[index] = _read_worker_shutdown_receipt(config.path, result, path;
            allocation_profile = x === :profile_alloc)
    end
    allocation_caches = Dict{Int, Any}()
    if x === :profile_alloc
        for (i, path) in enumerate(cached_paths)
            path === nothing && continue
            capture = try
                _read_allocation_cache(path;
                    expected_sha256 = cache_receipts[i]["receipt"]["allocation_profile_sha256"])
            catch error
                error isa InterruptException && rethrow()
                throw(HistoricalCacheUnqualified(path, sprint(showerror, error)))
            end
            capture === nothing && throw(HistoricalCacheUnqualified(path,
                "allocation-profile cache payload is missing or invalid"))
            allocation_caches[i] = capture
        end
    end
    worker_indices = findall(isnothing, cached_paths)
    temp_roots = Dict{Int, String}()
    worker_envs = Dict{Int, String}()
    prepared_environment = get(di, :prepared_environment, nothing)
    environment_source = prepared_environment === nothing ? config.path :
                         abspath(String(prepared_environment))
    isdir(environment_source) || throw(ArgumentError(
        "prepared environment does not exist: $environment_source"))
    procs = Any[nothing for _ in 1:len]
    cleanup_options = Dict{Symbol, Any}[]
    allocation_artifacts = Dict{Int, AllocationArtifacts}()
    creation_tasks = Pair{Int, Task}[]
    creation_errors = Any[nothing for _ in 1:len]
    reports = Dict{Int, Malt.WorkerShutdownReport}()
    function finish(; primary_error = nothing)
        _finish_check_cleanup!(creation_tasks, creation_errors, procs, worker_indices,
            reports, shutdown_options, x, di, cleanup_options,
            temp_roots, allocation_artifacts; primary_error)
    end
    try
        g = prep(di, block1, x)
        h = check(di, block2, x)
        initpkg = initpkgs(x)
        for index in worker_indices
            temp_roots[index] = mktempdir(; prefix = "perfchecker-check-", cleanup = false)
            worker_envs[index] = joinpath(temp_roots[index], "environment")
            _copy_check_environment(environment_source, worker_envs[index];
                exclude = get(di, :environment_excludes, String[]))
            _drop_incompatible_manifest!(worker_envs[index])
        end
        initial_roots = config.track == "none" ? Dict{Int, Vector{String}}() :
                        Dict(i => _allocation_roots(
                                 di, [environment_source, worker_envs[i]])
        for i in worker_indices)
        for i in worker_indices
            task = @async begin
                try
                    procs[i] = Worker(;
                        exeflags = ["--track-allocation=$(config.track)",
                            "-t $(config.threads)", "--project=$(worker_envs[i])"])
                    if config.track != "none"
                        artifacts = _allocation_artifacts(procs[i],
                            joinpath(temp_roots[i], "allocation-artifacts"))
                        allocation_artifacts[i] = artifacts
                        try
                            _register_allocation_roots!(artifacts, initial_roots[i])
                            _install_allocation_journal!(procs[i], artifacts)
                        catch
                            # User code has not started. Do not let graceful exit
                            # overwrite a trace whose snapshot was interrupted.
                            Base.process_running(procs[i].proc) &&
                                kill(procs[i].proc, Base.SIGKILL)
                            rethrow()
                        end
                    end
                catch error
                    creation_errors[i] = error
                    rethrow()
                end
            end
            push!(creation_tasks, i => task)
        end
        foreach(entry -> wait(last(entry)), creation_tasks)

        for i in 1:len
            target = targets[i]
            run_options = copy(di)
            run_options[:current_spec] = target.spec
            run_options[:current_version] = target.spec.version
            haskey(allocation_artifacts, i) &&
                (run_options[:allocation_artifacts] = allocation_artifacts[i])
            push!(cleanup_options, run_options)

            cached_path = cached_paths[i]
            qualification_evidence = _empty_qualification()
            resource_envelope = nothing

            if cached_path === nothing
                quiet = get(di, :quiet, false)
                instantiate_environment = prepared_environment === nothing
                remote_eval_wait(Main,
                    procs[i],
                    quote
                        import Pkg
                        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
                        $quiet && (Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true)
                        let
                            i = $i
                            $quiet || @info "Worker No.: $i"
                        end
                        $instantiate_environment &&
                            Pkg.instantiate(; io = $quiet ? devnull : stderr)
                    end)

                worker_options = copy(run_options)
                delete!(worker_options, :allocation_artifacts)
                remote_eval_wait(Main, procs[i], :(global d = $worker_options))

                prepared_environment === nothing &&
                    _install_target!(procs[i], target, worker_options)

                haskey(allocation_artifacts, i) &&
                    _register_allocation_roots!(allocation_artifacts[i],
                        _allocation_roots(run_options, [worker_envs[i]]))

                # Resolve target and explicitly declared backends before importing
                # them into the fresh worker; imports cannot see transitive deps.
                remote_eval_wait(Main, procs[i], initpkg)

                run_options[:prep_result] = remote_eval_fetch(Main, procs[i], g)
                if qualification !== nothing
                    raw_evidence = remote_eval_fetch(Main, procs[i], qualification)
                    raw_evidence isa AbstractDict || throw(ArgumentError(
                        "qualification block must return a dictionary"))
                    qualification_evidence = Dict{String, Any}(
                        string(key) => value for (key, value) in pairs(raw_evidence))
                    qualification_evidence["check_configuration"] = deepcopy(config.check_configuration)
                    _finalize_qualification!(qualification_evidence)
                    failure = _qualification_failure_kind(qualification_evidence)
                    failure === nothing ||
                        throw(QualificationFailure(failure, qualification_evidence))
                end
                if collect_resources
                    worker_pid = Int(remote_eval_fetch(Main, procs[i], :(getpid())))
                    external_before = _external_memory_probe(procs[i], run_options)
                    process_before = process_memory_snapshot(worker_pid)
                    started_ns = time_ns()
                    run_options[:check_result] = remote_eval_fetch(Main, procs[i], h)
                    elapsed_seconds = Float64(time_ns() - started_ns) / 1.0e9
                    process_after = process_memory_snapshot(worker_pid)
                    external_after = _external_memory_probe(procs[i], run_options)
                    resource_envelope = ResourceEnvelope(elapsed_seconds, process_before,
                        process_after, external_before, external_after;
                        external_requested = haskey(di, :external_memory_probe))
                    _apply_resource_policy!(
                        qualification_evidence, resource_envelope, run_options)
                else
                    run_options[:check_result] = remote_eval_fetch(Main, procs[i], h)
                end
                stop_before_post(x) &&
                    _stop_check_worker!(reports, i, procs[i], shutdown_options)
                res = post(run_options, x) |> to_table
                x === :profile_alloc &&
                    (qualification_evidence["allocation_profile"] = run_options[:check_result].summary)
            else
                qualification_evidence["worker_shutdown"] = cache_receipts[i]
                if x === :profile_alloc
                    capture = allocation_caches[i]
                    res = to_table(capture.sites)
                    qualification_evidence["allocation_profile"] = capture.summary
                else
                    res = csv_to_table(cached_path)
                end
            end

            qualification_evidence["measurement_state_policy"] = get(
                run_options, :fresh_feature, false) ? "fresh" : "reuse"
            qualification_evidence["check_configuration"] = deepcopy(config.check_configuration)
            push!(results.tables, res)
            push!(results.pkgs, target.spec)
            push!(results.qualifications, qualification_evidence)
            push!(results.resource_envelopes, resource_envelope)
        end

    catch error
        backtrace = catch_backtrace()
        try
            finish(; primary_error = error)
        catch cleanup_error
            throw(_combine_check_cleanup_failure(error, backtrace, cleanup_error))
        end
        rethrow()
    end
    finish()
    _check_worker_qualification_identity(code_identity)
    for index in worker_indices
        results.qualifications[index]["worker_shutdown"] = Dict{String, Any}(
            "origin" => "current_run", "code_identity" => deepcopy(code_identity),
            "report" => _worker_shutdown_report_dict(reports[index]))
    end

    # These writes make a result externally reusable. They must follow every
    # worker close, backend hook, artifact restoration and private-root cleanup.
    for (k, t) in enumerate(results.tables)
        ps = results.pkgs[k]
        pkg = ps.name
        v = ps.version
        (isnothing(pkg) || v == "dev") && continue

        run = run_metadata(config, pkg, v, block1, block2, hwinfo)
        out = output_path(config.path, run.result_uuid)
        metadata = metadata_path(config.path)
        cached_paths[k] === nothing || continue
        recorded = metadata_has_result(metadata, run.result_uuid)
        table_to_csv(t, out)
        x === :profile_alloc && _write_allocation_cache(
            out, t, results.qualifications[k]["allocation_profile"])
        recorded || write_run_metadata(metadata, run)
        results.qualifications[k]["worker_shutdown"] = _write_worker_shutdown_receipt(
            config.path, run.result_uuid, out, reports[k], code_identity;
            allocation_profile = x === :profile_alloc)
    end

    return results
end

function check_function(config::Union{PerfConfig, CheckConfig}, block1, block2; kwargs...)
    return check_function(config.backend, config, block1, block2; kwargs...)
end

function check_function(x::Symbol, config::PerfConfig, block1, block2; kwargs...)
    x == config.backend ||
        throw(ArgumentError(
            "backend mismatch: macro requested $x but PerfConfig uses $(config.backend)"))
    return check_function(x, to_dict(config), block1, block2; kwargs...)
end

function check_function(x::Symbol, d::NamedTuple, block1, block2; kwargs...)
    return check_function(x, Dict{Symbol, Any}(pairs(d)), block1, block2; kwargs...)
end

function check_function(backends::AbstractVector,
        options::Union{Dict, NamedTuple, PerfConfig}, block1, block2; kwargs...)
    isempty(backends) && throw(ArgumentError("at least one check backend is required"))
    all(backend -> backend isa Symbol, backends) ||
        throw(ArgumentError("check backends must all be Symbols"))
    requested = Symbol[backend for backend in backends]
    options = options isa NamedTuple ? Dict{Symbol, Any}(pairs(options)) : options
    # Resolve every collector and validate every configuration before starting
    # the first worker. Preserve repeated requests and their original order.
    fallback = which(check, Tuple{Any, Any, Any})
    preferences = check_preferences()
    configs = map(requested) do backend
        which(check, Tuple{Dict{Symbol, Any}, Expr, typeof(Val(backend))}) == fallback &&
            throw(ArgumentError("check backend $backend is unavailable; load its collector package"))
        config = normalize_config(backend, options; preferences)
        _worker_shutdown_options(legacy_options(config))
        run_targets(config)
        config
    end
    return [check_function(backend, config, block1, block2; kwargs...)
            for (backend, config) in zip(requested, configs)]
end

"""
    @check backend config begin
        # preparation code
    end begin
        # measured code
    end

Run a performance check using `backend` and return a `CheckerResult`.
Alternatively, pass a nonempty vector of backend symbols to return a vector of
`CheckerResult`s in that order. All collectors and configurations are validated
before any worker starts. Repeated symbols perform separate checks; each check
uses the same preparation and measured blocks and retains its own cleanup.
Load optional collector packages before requesting their symbols (for example,
`BenchmarkTools` for `:benchmark` and `Chairmarks` for `:chairmark`). An error in
a check stops the sequence after that check's cleanup.

The public `config` argument is usually a `Dict`. PerfChecker merges it with
backend defaults, validates it with `normalize_config`, copies the environment
at `config[:path]`, launches isolated Julia workers, installs the requested
package versions, runs the two code blocks, and stores result tables plus
metadata.

Example:

```julia
using PerfChecker, BenchmarkTools, Chairmarks

config = Dict(:path => @__DIR__, :samples => 10, :evals => 1)

result = @check :benchmark config begin
    using Random
end begin
    sum(rand(Random.MersenneTwister(1), 1_000))
end

results = @check [:alloc, :benchmark, :chairmark] config begin
    using Random
end begin
    sum(rand(Random.MersenneTwister(1), 1_000))
end
```
"""
macro check(x, d, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        x = $(esc(x))
        d = $(esc(d))
        check_function(x, d, $block1, $block2)
    end
end

"""
    @check config begin
        # preparation code
    end begin
        # measured code
    end

Run a performance check from a `PerfConfig`.

This is equivalent to `@check config.backend Dict(config) ...`, but keeps the
backend and options bundled in one Julia object for scripts, REPL sessions, and
Pluto notebooks.
"""
macro check(config, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        config = $(esc(config))
        check_function(config, $block1, $block2)
    end
end

"""
    perf_table(...)

Reserved extension point for backend-specific tabular summaries.
"""
function perf_table end

"""
    perf_plot(...)

Reserved extension point for backend-specific plots.
"""
function perf_plot end

"""
    table_to_pie(table, ::Val{backend}; kwargs...)

Load `PerfCheckerMakie` to create a pie chart from a backend table. Implemented by the companion
package for allocation tables with `Val(:alloc)`. Sites below 5% of allocated
bytes are combined by default. Use `min_percentage=0` to show smaller sites;
`top=40` caps legend entries, including the combined remainder. Return a Makie
figure; an allocation table without sites logs an error and returns `nothing`.
The table must contain byte counts and filename/line columns. This visualizes
saved values without running a check or saving an image.
"""
function table_to_pie end

"""
    checkres_to_scatterlines(result::CheckerResult, ::Val{backend}; kwargs...)

Load `PerfCheckerMakie` and a backend to create an evolution figure from saved
`CheckerResult` tables. Dispatch is explicit: use `Val(:benchmark)`,
`Val(:chairmark)` or `Val(:alloc)`. Benchmark/Chairmarks views overlay version
minima normalized per metric (minimum = 1); allocation views aggregate by file.
Collector-specific keywords apply only to methods accepting them. Result tables
must align with package specs; no workload is run or image saved.
"""
function checkres_to_scatterlines end

"""
    checkres_to_pie(result::CheckerResult, ::Val{backend}; kwargs...)

Load `PerfCheckerMakie` to create pie charts from a `CheckerResult`. For allocation checks this returns
pairs mapping version labels to Makie figures. Forwards `min_percentage` and
`top` to [`table_to_pie`](@ref). Values can be `nothing` for empty tables.
This reads saved allocation tables and package labels without running workloads
or exporting figures; load a Makie backend for rendering.
"""
function checkres_to_pie end

"""
    saveplot(path, figure; overwrite=false, kwargs...)
    saveplot(directory, named_figures; format=:svg, overwrite=false, kwargs...)

Load `PerfCheckerMakie` for methods exporting existing Makie figures to explicit
SVG/PNG destinations. Load an export backend such as CairoMakie first:

```julia
using PerfChecker, PerfCheckerMakie, CairoMakie
figure = CairoMakie.Figure()
saveplot("example.svg", figure) # parent directory must exist
```

Existing files are preserved unless `overwrite=true`; directories are never
replaced. The companion's collection method accepts name/Figure pairs and
checks portable filenames and collisions before writing. Extra keywords go to
Makie's `save`. Core alone provides this generic without methods, so unsupported
calls raise `MethodError`. Exporting a figure does not rerun measurements.
"""
function saveplot end

"""
    checkres_to_boxplots(result::CheckerResult, ::Val{backend}; kwarg=:times)

Load `PerfCheckerMakie` to return a figure of version distributions from a
`CheckerResult` for `Val(:benchmark)` or `Val(:chairmark)`. `kwarg` is the
symbolic table column (default `:times`); values retain collector units.
Missing columns or misaligned package/table data raise normal access errors.
This reads saved samples without measuring, normalizing units or saving a file.
"""
function checkres_to_boxplots end

"""
    to_table(raw_result) -> TypedTables.Table

Convert a backend-specific raw result into a table stored by PerfChecker.
Backends extend this method for their raw result types. Core supplies methods
for allocation, Julia CPU/wall profile and explicit/interface network records;
optional benchmark collectors add their own raw-result methods. A table
preserves backend columns and units without attaching run-bundle provenance.
Unsupported raw types raise `MethodError`; no measurement or file write occurs.
"""
function to_table end

@testitem "Check API" tags=[:unit, :api] begin
    using PerfChecker

    config = PerfConfig(:benchmark; path = @__DIR__, samples = 1)
    @test (@macroexpand @check config begin
        nothing
    end begin
        nothing
    end) isa Expr
    normalized = PerfChecker.normalize_config(config)
    @test length(PerfChecker.run_targets(normalized)) == 1
end

@testitem "Malt worker version scope" tags=[:integration, :workers] begin
    using BenchmarkTools
    using Chairmarks
    using PerfChecker
    import Pkg

    worker_env = dirname(Base.active_project())
    chair = PerfConfig(:chairmark; path = worker_env, samples = 1,
        evals = 1, seconds = 0.01)
    chair_result = PerfChecker.check_function(
        chair, :(nothing), :(haskey(d, :current_version)))
    @test length(chair_result.tables) == 1

    benchmark = PerfConfig(:benchmark; path = worker_env, samples = 1,
        evals = 1, seconds = 0.01)
    benchmark_result = PerfChecker.check_function(
        benchmark, :(nothing), :(haskey(d, :current_version)))
    @test length(benchmark_result.tables) == 1

    mktempdir() do dir
        runner = joinpath(dir, "runner")
        source = joinpath(dir, "PerfCheckerWorkerFixture")
        mkpath(runner)
        mkpath(joinpath(source, "src"))
        write(joinpath(runner, "Project.toml"), """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
""")
        write(joinpath(source, "Project.toml"), """
name = "PerfCheckerWorkerFixture"
uuid = "8402b14d-c534-4a2b-88cc-18076cd850d7"
version = "0.1.0"
""")
        write(joinpath(source, "src", "PerfCheckerWorkerFixture.jl"), """
module PerfCheckerWorkerFixture
answer() = 42
end
""")

        development = PerfConfig(:benchmark; path = runner,
            devops = Pkg.PackageSpec(name = "PerfCheckerWorkerFixture", path = source),
            include_current = false, quiet = true, samples = 1, evals = 1,
            seconds = 0.01)
        development_result = PerfChecker.check_function(development,
            :(using PerfCheckerWorkerFixture), :(PerfCheckerWorkerFixture.answer()))
        @test length(development_result.tables) == 1
    end

    mktempdir() do dir
        runner = joinpath(dir, "runner")
        dependency = joinpath(dir, "PerfCheckerUnregisteredDependency")
        package = joinpath(dir, "PerfCheckerFederatedFixture")
        mkpath(runner)
        mkpath(joinpath(dependency, "src"))
        mkpath(joinpath(package, "src"))
        write(joinpath(runner, "Project.toml"), """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
""")
        write(joinpath(dependency, "Project.toml"), """
name = "PerfCheckerUnregisteredDependency"
uuid = "2f753ed5-e566-43ab-8854-88d35cd4e1e7"
version = "0.1.0"
""")
        write(joinpath(dependency, "src", "PerfCheckerUnregisteredDependency.jl"), """
module PerfCheckerUnregisteredDependency
answer() = 42
end
""")
        write(joinpath(package, "Project.toml"), """
name = "PerfCheckerFederatedFixture"
uuid = "90d876ee-8511-4c06-8f19-a6cd03998f87"
version = "0.1.0"

[deps]
PerfCheckerUnregisteredDependency = "2f753ed5-e566-43ab-8854-88d35cd4e1e7"
""")
        write(joinpath(package, "src", "PerfCheckerFederatedFixture.jl"), """
module PerfCheckerFederatedFixture
using PerfCheckerUnregisteredDependency
answer() = PerfCheckerUnregisteredDependency.answer()
end
""")

        development = PerfConfig(:benchmark; path = runner,
            devops = Pkg.PackageSpec(name = "PerfCheckerFederatedFixture", path = package),
            extra_devops = [Pkg.PackageSpec(path = dependency)],
            include_current = false, quiet = true, samples = 1, evals = 1,
            seconds = 0.01)
        development_result = PerfChecker.check_function(development,
            :(using PerfCheckerFederatedFixture),
            :(PerfCheckerFederatedFixture.answer()))
        @test length(development_result.tables) == 1
    end
end

@testitem "Worker manifests follow the Julia minor version" tags=[:unit, :workers] begin
    using PerfChecker

    mktempdir() do dir
        manifest = joinpath(dir, "Manifest.toml")
        write(manifest, "julia_version = \"9.9.1\"\nmanifest_format = \"2.0\"\n")
        @test PerfChecker._drop_incompatible_manifest!(dir; runtime = v"1.10.0")
        @test !isfile(manifest)

        write(manifest, "julia_version = \"1.10.12\"\nmanifest_format = \"2.0\"\n")
        @test !PerfChecker._drop_incompatible_manifest!(dir; runtime = v"1.10.0")
        @test isfile(manifest)
    end
end

@testitem "Orthogonal process resource envelope" tags=[:integration, :resources] begin
    using BenchmarkTools
    using PerfChecker

    config = PerfConfig(:benchmark; path = dirname(Base.active_project()), samples = 2,
        environment_excludes = [".lab"],
        evals = 1, seconds = 0.01, process_resources = true,
        external_memory_probe = :perf_external_memory,
        external_memory_required = true,
        resource_upper_limits = Dict(:external_live_delta_bytes => 0),
        require_external_balance = true, quiet = true)
    setup = quote
        const _perfchecker_external_live = Ref{Int}(0)
        const _perfchecker_external_allocated = Ref{Int}(0)
        const _perfchecker_external_freed = Ref{Int}(0)
        function perf_external_memory()
            return Dict{String, Any}(
                "schema_version" => "perfchecker-external-memory/1",
                "live_bytes" => _perfchecker_external_live[],
                "reserved_bytes" => 4096,
                "allocated_bytes_total" => _perfchecker_external_allocated[],
                "freed_bytes_total" => _perfchecker_external_freed[],
                "provider" => "fixture-ledger")
        end
    end
    workload = quote
        _perfchecker_external_live[] += 64
        _perfchecker_external_allocated[] += 64
        _perfchecker_external_live[] -= 64
        _perfchecker_external_freed[] += 64
        nothing
    end
    result = PerfChecker.check_function(config, setup, workload)
    @test length(result.resource_envelopes) == 1
    envelope = only(result.resource_envelopes)
    @test envelope isa ResourceEnvelope
    if Sys.islinux() || Sys.iswindows()
        @test envelope.process_before.status === :observed
        @test envelope.process_after.status === :observed
    else
        for snapshot in (envelope.process_before, envelope.process_after)
            @test snapshot.status === :unavailable
            @test snapshot.provider == "unavailable"
            @test !isempty(snapshot.message)
            @test all(isnothing,
                (snapshot.rss_bytes, snapshot.peak_rss_bytes, snapshot.private_bytes))
        end
    end
    @test envelope.external_before.live_bytes == 0
    @test envelope.external_after.live_bytes == 0
    metrics = resource_envelope_metrics(envelope)
    @test metrics[:external_live_delta_bytes] == 0
    @test metrics[:external_allocated_delta_bytes] > 0
    @test metrics[:external_allocated_delta_bytes] ==
          metrics[:external_freed_delta_bytes]
    @test only(result.qualifications)["performance"]["status"] == "passed"

    leak_workload = quote
        _perfchecker_external_live[] += 64
        _perfchecker_external_allocated[] += 64
        nothing
    end
    leaked = PerfChecker.check_function(config, setup, leak_workload)
    evaluation = only(leaked.qualifications)["resource_policy"]
    @test !resource_policy_passed(evaluation)
    @test evaluation["status"] == "failed"
    @test any(message -> occursin("unbalanced", message), evaluation["violations"])
    @test any(message -> occursin("live bytes grew", message), evaluation["violations"])
end
