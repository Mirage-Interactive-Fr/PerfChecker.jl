@testitem "Terminated workers release their connections" tags=[:unit, :worker_cleanup] begin
    using PerfChecker
    for _ in 1:6
        worker = PerfChecker.Worker(; exeflags = ["--threads=1", "--gcthreads=1"])
        @test PerfChecker.remote_eval_fetch(Main, worker, :(1 + 1)) == 2
        PerfChecker.safe_stop(worker)
        @test !Base.process_running(worker.proc)
        @test !isopen(worker.stdout)
        @test !isopen(worker.stderr)
        @test !isopen(worker.current_socket)
        PerfChecker.safe_stop(worker)
        @test !isopen(worker.stdout)
    end
end

@testitem "Abnormal worker exits prevent check publication and caching" tags=[
    :integration, :worker_cleanup] begin
    using PerfChecker

    mktempdir() do directory
        environment = joinpath(directory, "WorkerExitFixture")
        mkpath(joinpath(environment, "src"))
        write(joinpath(environment, "Project.toml"), """
            name = "WorkerExitFixture"
            uuid = "54c915f3-3693-44f8-bbae-25dbfa62867e"
            version = "0.1.0"
            """)
        write(joinpath(environment, "src", "WorkerExitFixture.jl"), """
            __precompile__(false)
            module WorkerExitFixture
            Base.@noinline allocate(values) = copy(values)
            end
            """)
        versions = [v"0.2.3", v"0.2.4"]
        # Registered labels exercise cache publication without installing packages
        # into the prepared fixture.
        config = PerfConfig(:profile_alloc; path = environment,
            prepared_environment = environment, targets = ["WorkerExitFixture"],
            pkgs = ("PatternFolds", :custom, versions, false), quiet = true,
            repeat = false, profile_repetitions = 1, sample_rate = 1.0)
        mode_file = joinpath(directory, "exit-mode")
        exit_log = joinpath(directory, "worker-exits")
        preparation = quote
            using WorkerExitFixture
            payload = collect(1:32)
            @assert WorkerExitFixture.allocate(payload) == payload
            version = d[:current_version]
            atexit() do
                open(io -> println(io, version), $exit_log, "a")
                version == $(last(versions)) || return
                mode = read($mode_file, String)
                mode == "error" && exit(17)
                if mode == "signal"
                    ccall(:kill, Cint, (Cint, Cint), getpid(), Base.SIGKILL)
                end
            end
        end
        operation = :(WorkerExitFixture.allocate(payload))
        function run_check()
            PerfChecker.check_function(config, preparation, operation)
        end
        metadata = PerfChecker.metadata_path(environment)
        paths = [
            PerfChecker.output_path(environment,
                PerfChecker.result_uuid(PerfChecker.normalize_config(config),
                    "PatternFolds", version, preparation, operation, PerfChecker.HwInfo()))
            for version in versions
        ]

        for mode in (Sys.isunix() ? ("error", "signal") : ("error",))
            write(mode_file, mode)
            failure = try
                run_check()
                nothing
            catch error
                error
            end
            @test failure isa ErrorException
            message = sprint(showerror, failure)
            @test occursin(mode == "error" ? "code 17 and signal 0" :
                           "signal $(Base.SIGKILL)", message)
            # The first target also completed. Neither target may be published.
            @test !isfile(metadata)
            @test all(path -> !isfile(path) &&
                !isfile(PerfChecker._allocation_cache_path(path)), paths)
        end

        write(mode_file, "normal")
        result = run_check()
        @test length(result.tables) == length(versions)
        @test all(table -> !isempty(table), result.tables)
        @test isfile(metadata)
        @test all(path -> isfile(path) &&
            isfile(PerfChecker._allocation_cache_path(path)), paths)

        exits = read(exit_log)
        write(mode_file, "error")
        cached = run_check()
        @test isequal(collect.(cached.tables), collect.(result.tables))
        @test read(exit_log) == exits
    end
end
