@testitem "Constructor cancellation preserves rollback and suite state" tags=[
    :integration, :worker_cleanup, :check_shutdown] begin
    using PerfChecker

    if !Sys.islinux()
        # The deterministic stop below is a Linux-only fault injection. It does
        # not claim qualification of native process control on other systems.
        @test_skip Sys.islinux()
    else
        script = raw"""
        using PerfChecker, Test, Dates
        import Malt

        @assert VERSION.major == 1 && VERSION.minor == 13
        @assert Sys.islinux() && Threads.nthreads() == 1

        function process_starttime(pid)
            path = "/proc/$(pid)/stat"
            isfile(path) || return nothing
            contents = read(path, String)
            fields = split(contents[findlast(==(')'), contents) + 2:end])
            parse(UInt64, fields[20])
        end

        function nested_startup_failures(error)
            error isa Malt.WorkerStartupException && return [error]
            if error isa PerfChecker.CheckCleanupFailure
                return reduce(vcat, nested_startup_failures.(error.errors);
                    init = Malt.WorkerStartupException[])
            end
            Malt.WorkerStartupException[]
        end

        function cancellation_case(block_manager)
            fixture = mktempdir(; prefix = "perfchecker-constructor-cancel-", cleanup = false)
            owned = Ref{Any}(nothing)
            identity = Ref{Any}(nothing)
            job = nothing
            observer = nothing
            manager = nothing
            release = Channel{Nothing}(1)
            manager_entered = Channel{Nothing}(1)
            private_root = nothing
            safe = false
            try
                source = mkpath(joinpath(fixture, "source"))
                seed = mkpath(joinpath(fixture, "seed"))
                write(joinpath(source, "Project.toml"),
                    "name = \"PrepCancellationFixture\"\n" *
                    "uuid = \"fab08b63-242a-4a89-a32c-5de2d4264d04\"\n" *
                    "version = \"0.1.0\"\n")
                seed_project = joinpath(seed, "Project.toml")
                write(seed_project, "[deps]\n")
                before_seed = read(seed_project)
                entrypoint = joinpath(source, "feature.jl")
                write(entrypoint, "perf_workload(_) = nothing\n")
                package = PackageSuite("PrepCancellationFixture"; source,
                    worker_environment = seed, versions = VersionNumber[],
                    features = [FeatureSpec(:first; backend = :alloc, entrypoint),
                        FeatureSpec(:second; backend = :alloc, entrypoint)])
                plan = plan_suite(SoftwareSuite(:preparation_cancellation, [package]);
                    profile = :quick)
                previous = lock(Malt._worker_states_lock) do
                    copy(Malt._worker_states)
                end
                entered = Channel{Any}(1)
                observer = @async begin
                    started = time_ns()
                    while time_ns() - started < UInt64(30_000_000_000)
                        added = lock(Malt._worker_states_lock) do
                            setdiff(Malt._worker_states, previous)
                        end
                        if !isempty(added)
                            state = only(added)
                            owned[] = state
                            pid = Int(state.proc_pid)
                            token = process_starttime(pid)
                            identity[] = (pid, token)
                            @assert token !== nothing && process_starttime(pid) == token
                            @assert Base.process_running(state.proc)
                            # Malt publishes this state then yields before it
                            # starts the port reader. J1 makes that a rendezvous.
                            @assert isempty(state.tasks)
                            println("PREPARATION_CANCEL_OWNED pid=", pid,
                                " starttime=", token, " blocked_manager=", block_manager)
                            flush(stdout)
                            # SIGSTOP is 19 on this explicitly guarded Linux
                            # fixture; production cancellation uses no signal ID.
                            kill(state.proc, Int32(19))
                            if block_manager
                                manager = Malt._track_task!(state, :fixture_manager) do
                                    put!(manager_entered, nothing)
                                    take!(release)
                                end
                            end
                            put!(entered, state)
                            return
                        end
                        yield()
                    end
                    error("constructor publication rendezvous timed out")
                end
                job = launch_suite(plan)
                @test timedwait(() -> isready(entered) || istaskdone(observer), 35) == :ok
                isready(entered) || fetch(observer)
                state = take!(entered)
                pid, token = identity[]
                @test process_starttime(pid) == token
                if block_manager
                    @test timedwait(() -> isready(manager_entered), 10) == :ok
                    take!(manager_entered)
                    @test !istaskdone(manager)
                end
                environment = only(filter(argument -> startswith(argument, "--project="),
                    state.proc.cmd.exec))[11:end]
                private_root = dirname(environment)
                @test startswith(basename(private_root), "perfchecker-prepared-")
                @test isdir(environment)
                @test cancel_suite!(job)
                @test !cancel_suite!(job)
                @test timedwait(() -> istaskdone(job.task), 40) == :ok
                wait(job.task)
                @test job.cancelled[]
                @test job.result[] === nothing
                @test read(seed_project) == before_seed
                @test !Base.process_running(state.proc)
                @test process_starttime(pid) === nothing
                observed = Malt._report(state)
                @test observed.process_exited
                @test observed.socket_closed && observed.stdout_closed && observed.stderr_closed
                @test observed.pending_replies == 0 && observed.active_senders == 0
                if block_manager
                    @test suite_job_status(job) === :failed
                    @test !observed.complete && !observed.tasks_done
                    @test !istaskdone(manager)
                    @test isdir(private_root)
                    failure = job.error[][1]
                    @test failure isa PerfChecker.CheckCleanupFailure
                    @test private_root in failure.directories
                    @test failure.primary !== nothing
                    startups = nested_startup_failures(failure)
                    @test !isempty(startups)
                    @test any(error -> error.cause isa InterruptException &&
                        !error.report.complete, startups)
                    @test_throws PerfChecker.CheckCleanupFailure wait_suite(job; strict = false)
                    put!(release, nothing)
                    wait(manager)
                    final = first(Malt._shutdown_state!(state; timeout = 10,
                        exit_timeout = 0, term_timeout = 0))
                    @test final.complete && final.tasks_done
                    @test all(task -> task.done, final.tasks)
                    # A later close does not upgrade the failed measurement.
                    @test suite_job_status(job) === :failed
                    rm(private_root; recursive = true, force = true)
                else
                    @test suite_job_status(job) === :cancelled
                    @test job.error[] === nothing
                    @test observed.complete && observed.tasks_done
                    @test !ispath(private_root)
                    @test_throws InterruptException wait_suite(job; strict = false)
                end
                @test !ispath(private_root)
                println("PREPARATION_CANCEL_TERMINAL pid=", pid,
                    " status=", suite_job_status(job), " complete=", Malt._report(state).complete)
                flush(stdout)
            finally
                # Release the actual owned task before joining or deleting its
                # inputs, even when an assertion or constructor operation fails.
                if manager !== nothing && !istaskdone(manager)
                    isready(release) || put!(release, nothing)
                    timedwait(() -> istaskdone(manager), 15)
                end
                state = owned[]
                if state !== nothing && private_root === nothing
                    arguments = filter(argument -> startswith(argument, "--project="),
                        state.proc.cmd.exec)
                    candidate = dirname(only(arguments)[11:end])
                    startswith(basename(candidate), "perfchecker-prepared-") &&
                        (private_root = candidate)
                end
                if state !== nothing && Base.process_running(state.proc)
                    pid, token = identity[]
                    process_starttime(pid) == token && kill(state.proc, Base.SIGKILL)
                    timedwait(() -> !Base.process_running(state.proc), 15)
                end
                if job !== nothing && !istaskdone(job.task)
                    cancel_suite!(job)
                    timedwait(() -> istaskdone(job.task), 25)
                end
                observer === nothing || istaskdone(observer) ||
                    timedwait(() -> istaskdone(observer), 35)
                if state !== nothing
                    final = first(Malt._shutdown_state!(state; timeout = 10,
                        exit_timeout = 0, term_timeout = 0))
                    safe = final.complete
                else
                    safe = true
                end
                safe &= job === nothing || istaskdone(job.task)
                safe &= observer === nothing || istaskdone(observer)
                if safe
                    private_root === nothing || rm(private_root; recursive = true, force = true)
                    rm(fixture; recursive = true, force = true)
                else
                    println("PREPARATION_CANCEL_RETAINED ", fixture)
                end
                close(release)
                close(manager_entered)
                println("PREPARATION_CANCEL_CLEAN safe=", safe,
                    " fixture_exists=", ispath(fixture))
                flush(stdout)
            end
            @test safe
            @test !ispath(fixture)
        end

        @testset "Constructor cancellation after real rollback" begin
            cancellation_case(false)
            cancellation_case(true)
        end
        """
        command = Cmd([Base.julia_cmd()[1], "--startup-file=no", "--threads=1",
            "--gcthreads=1", "--project=$(dirname(Base.active_project()))", "-e", script])
        passed = success(addenv(command, "JULIA_NUM_THREADS" => "1",
            "JULIA_NUM_GC_THREADS" => "1", "OPENBLAS_NUM_THREADS" => "1"))
        @test passed
    end
end
