@testitem "Check publication follows worker and callback qualification" tags=[
    :integration, :worker_cleanup, :check_shutdown] begin
    using PerfChecker, Sockets, SHA
    import Malt

    # These are genuine backend extension points, not a fake Worker/provider.
    # The empty prepared environment avoids package installation; the measured
    # operation is only a fixture needed to reach orchestration and shutdown.
    @eval PerfChecker begin
        const _shutdown_contract_events = Dict{String, Vector{Any}}()
        prep(::Dict, block::Expr, ::Val{:shutdown_contract}) = block
        check(::Dict, block::Expr, ::Val{:shutdown_contract}) = block
        stop_before_post(::Val{:shutdown_contract}) = true
        function post(options::Dict, ::Val{:shutdown_contract})
            events = _shutdown_contract_events[options[:shutdown_case]]
            prepared = options[:prep_result]
            cache_root = options[:path]
            push!(events,
                (kind = :post, pid = prepared.pid,
                    environment = prepared.environment,
                    exited = !Sys.islinux() || !ispath("/proc/$(prepared.pid)"),
                    unpublished = !isdir(joinpath(cache_root, "output")) &&
                                  !isfile(metadata_path(cache_root))))
            get(options, :shutdown_post_error, false) && error("fixture-post-failure")
            return ProfileSample[]
        end
        function cleanup(options::Dict, ::Val{:shutdown_contract})
            events = _shutdown_contract_events[options[:shutdown_case]]
            target = get(options, :current_version, nothing)
            prepared = get(options, :prep_result, nothing)
            push!(events, (kind = :cleanup, target = target, prepared = prepared))
            get(options, :shutdown_hook_errors, false) &&
                error("fixture-cleanup-" * string(target))
            return nothing
        end
    end

    function leaves(error)
        error isa CompositeException && return reduce(vcat, leaves.(error.exceptions);
            init = Any[])
        error isa PerfChecker.CheckCleanupFailure &&
            return reduce(vcat, leaves.(error.errors); init = Any[])
        return Any[error]
    end
    function publication(directory)
        output = joinpath(directory, "output")
        return (isdir(output) ? sort(readdir(output)) : String[],
            isfile(PerfChecker.metadata_path(directory)))
    end
    function tree_state(directory)
        state = Dict{String, Any}()
        for (parent, _, files) in walkdir(directory)
            state[relpath(parent, directory)] = (:directory, filemode(parent))
            for name in files
                path = joinpath(parent, name)
                info = stat(path)
                state[relpath(path, directory)] = (
                    read(path), info.mode, info.mtime, info.ctime)
            end
        end
        state
    end
    function cache_call(config, preparation, block; observed = Any[])
        key = PerfChecker.to_dict(config)[:shutdown_case]
        PerfChecker._shutdown_contract_events[key] = observed
        println(stderr, "CACHE_WITHOUT_WORKER_BEGIN pid=", getpid())
        flush(stderr)
        try
            # Malt's public constructor reads this default and rejects zero
            # before spawning. check_function does not override connect_timeout.
            # A mistaken replay therefore fails distinctly, without a test mock.
            result = withenv("JULIA_WORKER_TIMEOUT" => "0") do
                PerfChecker.check_function(config, preparation, block)
            end
            return result, observed
        finally
            println(stderr, "CACHE_WITHOUT_WORKER_END pid=", getpid())
            flush(stderr)
            delete!(PerfChecker._shutdown_contract_events, key)
        end
    end
    function check_fresh_cache(config, preparation, block, original, worker_pids)
        options = PerfChecker.to_dict(config)
        environment = options[:path]
        normalized = PerfChecker.normalize_config(config)
        csvs = [PerfChecker.cached_output_path(normalized, "PatternFolds", version,
                    preparation, block, PerfChecker.HwInfo())
                for version in (v"0.2.1", v"0.2.4")]
        @test all(path -> path isa String && isfile(path), csvs)
        receipts = [joinpath(environment, "metadata", "worker-shutdown",
                        first(splitext(basename(path))) * ".json") for path in csvs]
        @test all(isfile, receipts)
        csv_bytes = read.(csvs)
        receipt_bytes = read.(receipts)
        for (csv, receipt) in zip(csvs, receipts)
            record = PerfChecker._json_parsefile(receipt)
            @test record["schema_version"] == "perfchecker-worker-shutdown/1"
            @test record["result_uuid"] == first(splitext(basename(csv)))
            @test record["csv_sha256"] == bytes2hex(sha256(read(csv)))
            @test !isempty(record["observed_at_utc"])
            @test record["code_identity"] isa AbstractDict
            @test occursin(r"^[0-9a-f]{64}$", record["code_identity_sha256"])
            report = record["report"]
            @test report["pid"] in worker_pids
            @test report["complete"] === true
            @test report["process_exited"] === true
            @test report["exitcode"] == 0
            @test report["termsignal"] == 0
            @test report["tasks_done"] === true
            @test report["socket_closed"] === true
            @test report["stdout_closed"] === true
            @test report["stderr_closed"] === true
            @test report["active_senders"] == 0
            @test report["pending_replies"] == 0
            @test report["failed_replies"] == 0
            @test isempty(report["errors"])
            @test !isempty(report["tasks"])
            @test all(task -> task["done"] === true && task["failed"] === false,
                report["tasks"])
        end
        snapshot = tree_state(environment)
        reused, events = cache_call(config, preparation, block)
        @test collect.(reused.tables) == collect.(original.tables)
        @test length(reused.tables) == 2
        @test all(record -> record["worker_shutdown"]["origin"] == "qualified_cache",
            reused.qualifications)
        @test all(record -> isfile(record["worker_shutdown"]["receipt_path"]),
            reused.qualifications)
        @test all(event -> event.kind === :cleanup && event.prepared === nothing, events)
        @test isequal(tree_state(environment), snapshot)

        for mutation in (:missing, :invalid_receipt, :csv_digest, :mixed_uncached)
            try
                if mutation === :missing
                    rm(first(receipts))
                elseif mutation === :invalid_receipt
                    write(first(receipts), "{}\n")
                elseif mutation === :csv_digest
                    # A semantically harmless blank line still changes the exact
                    # published CSV. The receipt authenticates these bytes too.
                    open(first(csvs), "a") do io
                        write(io, '\n')
                    end
                else
                    # Index 1 needs a worker; index 2 has bad historical evidence.
                    # All cached indices must be checked before creating index 1.
                    rm(first(csvs))
                    write(last(receipts), "{}\n")
                end
                before = tree_state(environment)
                events = Any[]
                failure = try
                    cache_call(config, preparation, block; observed = events)
                    nothing
                catch error
                    error
                end
                @test failure isa PerfChecker.HistoricalCacheUnqualified
                @test !isempty(failure.path)
                @test !isempty(failure.reason)
                @test all(event -> event.kind === :cleanup && event.prepared === nothing,
                    events)
                @test isequal(tree_state(environment), before)
            finally
                # Restore only bytes written by the actual qualified first run;
                # this never manufactures a receipt for an old or failed worker.
                for (path, bytes) in zip(csvs, csv_bytes)
                    isfile(path) && read(path) == bytes || write(path, bytes)
                end
                for (path, bytes) in zip(receipts, receipt_bytes)
                    isfile(path) && read(path) == bytes || write(path, bytes)
                end
            end
        end
    end
    preparation = :((pid = getpid(), environment = dirname(Base.active_project())))

    mktempdir() do directory
        for scenario in (:normal, :post_error, :hook_errors, :primary_and_shutdown)
            environment = joinpath(directory, string(scenario))
            mkdir(environment)
            write(joinpath(environment, "Project.toml"), "[deps]\n")
            key = string(scenario)
            events = Any[]
            PerfChecker._shutdown_contract_events[key] = events
            config = PerfConfig(:shutdown_contract; path = environment,
                prepared_environment = environment, quiet = true, repeat = false,
                # Existing registry labels exercise two cache identities. The
                # prepared fixture deliberately installs/imports neither package.
                pkgs = ("PatternFolds", :custom, [v"0.2.1", v"0.2.4"], false),
                shutdown_case = key, shutdown_post_error = scenario === :post_error,
                shutdown_hook_errors = scenario === :hook_errors)
            block = scenario === :primary_and_shutdown ?
                    quote
                atexit(() -> exit(17))
                error("fixture-primary-failure")
            end : quote
                nothing
            end
            result = nothing
            failure = nothing
            try
                result = PerfChecker.check_function(config, preparation, block)
            catch error
                failure = error
            finally
                delete!(PerfChecker._shutdown_contract_events, key)
            end
            retained = failure isa PerfChecker.CheckCleanupFailure ?
                       copy(failure.directories) : String[]
            try
                posts = filter(event -> event.kind === :post, events)
                hooks = filter(event -> event.kind === :cleanup, events)
                if scenario === :normal
                    @test failure === nothing
                    @test length(result.tables) == 2
                    @test length(result.pkgs) == 2
                    @test length(posts) == 2
                    @test length(hooks) == 3
                    @test count(event -> event.target === nothing, hooks) == 1
                    @test sort([event.target for event in hooks if event.target !== nothing]) ==
                          [v"0.2.1", v"0.2.4"]
                    @test length(first(publication(environment))) == 2
                    @test last(publication(environment))
                    check_fresh_cache(config, preparation, block, result,
                        [event.pid for event in posts])
                else
                    @test result === nothing
                    @test failure !== nothing
                    @test publication(environment) == (String[], false)
                    messages = sprint(showerror, failure)
                    if scenario === :post_error
                        @test occursin("fixture-post-failure", messages)
                        @test !isempty(hooks)
                    elseif scenario === :hook_errors
                        @test length(posts) == 2
                        @test length(hooks) == 3
                        @test length(leaves(failure)) >= 3
                        for suffix in ("nothing", "0.2.1", "0.2.4")
                            @test occursin("fixture-cleanup-" * suffix, messages)
                        end
                    else
                        @test occursin("fixture-primary-failure", messages)
                        @test occursin("17", messages)
                        @test length(leaves(failure)) >= 2
                        @test isempty(posts)
                        @test !isempty(hooks)
                    end
                end
                for event in posts
                    @test event.exited
                    @test event.unpublished
                end
                # Returned fixture values are immutable PID/path scalars, never
                # Worker/Task references. Only explicitly retained environments
                # may remain until this fixture releases its recovery ownership.
                prepared = [event.prepared for event in hooks if event.prepared !== nothing]
                for observation in prepared
                    if dirname(observation.environment) in retained
                        @test isdir(observation.environment)
                    else
                        @test !ispath(observation.environment)
                    end
                    Sys.islinux() && @test !ispath("/proc/$(observation.pid)")
                end
            finally
                # A failed user cleanup hook deliberately retains its own worker
                # environment. This fixture owns and removes that recovery data
                # only after checking the failure and observing all callbacks.
                for root in retained
                    startswith(basename(root), "perfchecker-check-") ||
                        error("unexpected retained fixture path")
                    rm(root; recursive = true, force = true)
                end
            end
        end

        # A real TCP rendezvous proves the remote operation has started. No
        # additional RPC changes which request is active before cancellation.
        environment = joinpath(directory, "cancelled")
        mkdir(environment)
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        key = "cancelled"
        events = Any[]
        PerfChecker._shutdown_contract_events[key] = events
        listener = listen(ip"127.0.0.1", 0)
        port = Int(last(getsockname(listener)))
        accepted = @async accept(listener)
        connection = nothing
        task = nothing
        config = PerfConfig(:shutdown_contract; path = environment,
            prepared_environment = environment, quiet = true, repeat = false,
            control_port = port, shutdown_case = key, shutdown_hook_errors = true)
        try
            task = @async try
                PerfChecker.check_function(config,
                    quote
                        using Sockets
                        (pid = getpid(), environment = dirname(Base.active_project()))
                    end,
                    quote
                        connection = connect(ip"127.0.0.1", d[:control_port])
                        try
                            println(connection, getpid())
                            flush(connection)
                            read(connection, UInt8)
                        finally
                            close(connection)
                        end
                    end)
            catch error
                error
            end
            @test timedwait(() -> istaskdone(accepted) || istaskdone(task), 60) == :ok
            @test !istaskdone(task)
            connection = fetch(accepted)
            worker_pid = parse(Int, readline(connection))
            @test worker_pid != getpid()
            schedule(task, InterruptException(); error = true)
            @test timedwait(() -> istaskdone(task), 60) == :ok
            failure = fetch(task)
            @test failure isa PerfChecker.CheckCleanupFailure
            @test any(error -> error isa InterruptException, leaves(failure))
            @test occursin("fixture-cleanup-nothing", sprint(showerror, failure))
            @test count(event -> event.kind === :cleanup, events) == 2
            @test all(event -> event.kind !== :post, events)
            @test publication(environment) == (String[], false)
            for event in events
                event.kind === :cleanup && event.prepared !== nothing || continue
                @test dirname(event.prepared.environment) in failure.directories
                @test isdir(event.prepared.environment)
            end
            Sys.islinux() && @test !ispath("/proc/$worker_pid")
        finally
            connection === nothing || close(connection)
            close(listener)
            wait(accepted)
            if task !== nothing && !istaskdone(task)
                schedule(task, InterruptException(); error = true)
                wait(task)
            end
            if task !== nothing && istaskdone(task)
                failure = fetch(task)
                if failure isa PerfChecker.CheckCleanupFailure
                    for root in failure.directories
                        startswith(basename(root), "perfchecker-check-") ||
                            error("unexpected retained cancellation fixture path")
                        rm(root; recursive = true, force = true)
                    end
                end
            end
            delete!(PerfChecker._shutdown_contract_events, key)
        end

        environment = joinpath(directory, "incomplete")
        mkdir(environment)
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        key = "incomplete"
        events = Any[]
        PerfChecker._shutdown_contract_events[key] = events
        failure = nothing
        try
            config = PerfConfig(:shutdown_contract; path = environment,
                prepared_environment = environment, quiet = true, repeat = false,
                shutdown_case = key,
                worker_shutdown = (timeout = 0.0, exit_timeout = 0.0, term_timeout = 0.0))
            result = try
                PerfChecker.check_function(config, preparation, quote
                    nothing
                end)
            catch error
                failure = error
                nothing
            end
            @test result === nothing
            @test failure isa PerfChecker.CheckCleanupFailure
            @test any(error -> error isa Malt.ShutdownIncompleteException, leaves(failure))
            @test !isempty(failure.retained_workers)
            @test !isempty(failure.directories)
            @test all(isdir, failure.directories)
            @test all(event -> event.kind !== :post, events)
            @test publication(environment) == (String[], false)
            for worker in failure.retained_workers
                running = Base.process_running(worker.proc)
                @test running
                @test any(entry -> !istaskdone(last(entry)), worker.state.tasks)
            end
        finally
            if failure isa PerfChecker.CheckCleanupFailure
                # An incomplete report is recovery ownership, not PASS. Retain
                # the actual handles until a later full shutdown really joins
                # every task, then release this fixture's diagnostic directories.
                for worker in failure.retained_workers
                    report = PerfChecker.safe_stop(worker)
                    @test report.complete
                    @test report.exitcode == 0
                    @test report.termsignal == 0
                    @test isempty(report.errors)
                    @test isempty(worker.expected_replies)
                    @test all(entry -> istaskdone(last(entry)), worker.state.tasks)
                    Sys.islinux() && @test !ispath("/proc/$(report.pid)")
                end
                for root in failure.directories
                    startswith(basename(root), "perfchecker-check-") ||
                        error("unexpected retained incomplete fixture path")
                    rm(root; recursive = true, force = true)
                end
            end
            delete!(PerfChecker._shutdown_contract_events, key)
        end
    end
end

@testitem "Invalid shutdown options are rejected before worker preparation" tags=[
    :unit, :worker_cleanup, :check_shutdown] begin
    using PerfChecker

    mktempdir() do directory
        write(joinpath(directory, "Project.toml"), "[deps]\n")
        marker = joinpath(directory, "unexpected-preparation")
        invalid = Any[nothing, (), (timeout = -1.0,), (timeout = NaN,),
            (timeout = Inf,), (timeout = true,), (timeout = floatmax(Float64),),
            (exit_timeout = -1.0,), (exit_timeout = false,), (term_timeout = NaN,),
            (term_timeout = -1.0,), (close_unmonitored = false,),
            (close_unmonitored = true,), Dict("timeout" => 1.0),
            Dict(:unknown => 0.0)]
        for setting in invalid
            config = PerfConfig(:alloc; path = directory, quiet = true,
                prepared_environment = directory, worker_shutdown = setting)
            snapshot = deepcopy(PerfChecker.to_dict(config))
            @test_throws ArgumentError PerfChecker.check_function(config,
                :(touch($marker)), quote
                    nothing
                end)
            @test !isfile(marker)
            @test isequal(PerfChecker.to_dict(config), snapshot)
            @test !isdir(joinpath(directory, "output"))
            @test !isfile(PerfChecker.metadata_path(directory))
        end
    end
end

@testmodule ShutdownCollectorContracts begin
    using PerfChecker, Test

    function exercise_collectors(backends)
        mktempdir() do directory
            environment = joinpath(directory, "LifecycleCollectorFixture")
            mkpath(joinpath(environment, "src"))
            write(joinpath(environment, "Project.toml"), """
    name = "LifecycleCollectorFixture"
    uuid = "ad320fd7-1f76-4c3b-9240-dd579b81b8fd"
    version = "0.1.0"

    [compat]
    julia = "1.10"
    """)
            source = joinpath(environment, "src", "LifecycleCollectorFixture.jl")
            write(source, """
    __precompile__(false)
    module LifecycleCollectorFixture
    allocate(values) = copy(values)
    Base.@noinline function cpu(values)
        result = 0.0
        for index in 1:4096
            result = sin(result + values[mod1(index, length(values))])
        end
        result
    end
    end
    """)
            foreign_trace = source * ".987654321.mem"
            foreign_bytes = "foreign allocation trace, preserved\r\n"
            write(foreign_trace, foreign_bytes)
            preparation = quote
                using LifecycleCollectorFixture
                payload = collect(1:32)
                # Compilation is preparation, not the target of this collector test.
                copied = LifecycleCollectorFixture.allocate(payload)
                @assert copied == payload && copied !== payload
                @assert isfinite(LifecycleCollectorFixture.cpu(payload))
            end
            for backend in backends
                operation = backend === :profile ?
                            :(LifecycleCollectorFixture.cpu(payload)) :
                            :(LifecycleCollectorFixture.allocate(payload))
                config = PerfConfig(backend; path = environment,
                    prepared_environment = environment, quiet = true, repeat = false,
                    threads = 1, targets = ["LifecycleCollectorFixture"],
                    profile_seconds = 0.05, profile_delay = 0.001,
                    profile_buffer = 100_000, profile_repetitions = 1, sample_rate = 1.0)
                result = PerfChecker.check_function(config, preparation, operation)
                @test length(result.tables) == 1
                @test length(result.qualifications) == 1
                @test length(result.pkgs) == 1
                if backend === :alloc
                    @test !isempty(only(result.tables))
                    @test sum(row -> row.bytes, only(result.tables)) > 0
                    @test any(
                        row -> endswith(row.filename, "LifecycleCollectorFixture.jl"),
                        only(result.tables))
                elseif backend === :profile_alloc
                    summary = only(result.qualifications)["allocation_profile"]
                    @test summary["status"] == "complete"
                    @test summary["total_bytes"] > 0
                    @test summary["total_allocations"] > 0
                    @test summary["retained_allocations"] > 0
                    @test summary["profile_evaluations"] == 1
                    @test !isempty(only(result.tables))
                else
                    @test !isempty(only(result.tables))
                    @test all(row -> row.samples > 0, only(result.tables))
                end
                @test read(foreign_trace, String) == foreign_bytes
                @test filter(name -> endswith(name, ".mem"), readdir(dirname(source))) ==
                      [basename(foreign_trace)]
            end
            # This is a functional collector smoke, not a performance comparison:
            # neither timings nor sample counts are compared to historical campaigns.
            @test !isdir(joinpath(environment, "output"))
            @test !isfile(PerfChecker.metadata_path(environment))
        end
    end
end

@testitem "Exit-flushed allocations survive strict shutdown" tags=[
    :integration, :worker_cleanup, :check_shutdown, :alloc_shutdown] setup=[
    ShutdownCollectorContracts] begin
    ShutdownCollectorContracts.exercise_collectors((:alloc,))
end

@testitem "CPU and allocation profiles survive strict shutdown" tags=[
    :integration, :worker_cleanup, :check_shutdown, :profile_shutdown] setup=[
    ShutdownCollectorContracts] begin
    ShutdownCollectorContracts.exercise_collectors((:profile, :profile_alloc))
end
