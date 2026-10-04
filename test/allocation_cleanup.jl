@testitem "Allocation cleanup owns only its worker traces" tags=[
    :integration, :allocation_cleanup] begin
    using PerfChecker
    import Pkg

    mktempdir() do directory
        environment = joinpath(directory, "environment")
        source = joinpath(directory, "PerfCheckerAllocationFixture")
        mkpath(environment)
        mkpath(joinpath(source, "src"))
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        write(joinpath(source, "Project.toml"), """
name = "PerfCheckerAllocationFixture"
uuid = "ce59c047-c922-4f2c-814b-1a4dc48c4c30"
version = "0.1.0"
""")
        module_file = joinpath(source, "src", "PerfCheckerAllocationFixture.jl")
        operation_file = joinpath(source, "src", "operation.jl")
        write(module_file,
            """
__precompile__(false)
module PerfCheckerAllocationFixture
include("operation.jl")
end
""")
        write(operation_file, "allocate() = copy(fill(1, 4096))\n")
        foreign = operation_file * ".987654321.mem"
        unrelated = joinpath(source, "src", "notes.mem")
        write(foreign, "999999999 allocate() = nothing\n")
        write(unrelated, "user allocation notes\n")
        original = "pre-existing trace, preserved byte for byte\r\n"
        gate = joinpath(directory, "baseline-start")
        baseline_code = "using Profile; while !isfile($(repr(gate))); sleep(0.01); end; " *
                        "include($(repr(operation_file))); allocate(); Profile.clear_malloc_data(); allocate()"
        process = run(
            Cmd([Base.julia_cmd()[1], "--startup-file=no",
                "--track-allocation=user", "-e", baseline_code]);
            wait = false)
        baseline_artifacts = PerfChecker._allocation_artifacts((; proc = process),
            joinpath(directory, "baseline-journal"))
        baseline = try
            PerfChecker._register_allocation_roots!(baseline_artifacts,
                [source, Sys.STDLIB])
            touch(gate)
            wait(process)
            @test success(process)
            read(operation_file * ".$(baseline_artifacts.pid).mem", String)
        finally
            Base.process_running(process) && kill(process)
            wait(process)
            PerfChecker._cleanup_allocation_artifacts!(baseline_artifacts)
        end
        # Identical bytes can be a stale trace or a real current measurement.
        # Exercise both states with Julia's actual allocation tracker.
        rm(gate)
        process = run(
            Cmd([Base.julia_cmd()[1], "--startup-file=no",
                "--track-allocation=user", "-e", baseline_code]);
            wait = false)
        identical_artifacts = PerfChecker._allocation_artifacts((; proc = process),
            joinpath(directory, "identical-journal"))
        identical_file = operation_file * ".$(identical_artifacts.pid).mem"
        write(identical_file, baseline)
        try
            PerfChecker._register_allocation_roots!(identical_artifacts,
                [source, Sys.STDLIB])
            options = Dict{Symbol, Any}(:check_result => ([source], [source]),
                :allocation_artifacts => identical_artifacts,
                :targets => ["PerfCheckerAllocationFixture"])
            @test_throws ErrorException PerfChecker.post(options, Val(:alloc))
            touch(gate)
            wait(process)
            @test success(process)
            @test read(identical_file, String) == baseline
            current = PerfChecker.post(options, Val(:alloc))
            @test !isempty(current)
            @test any(row -> occursin("operation", row.filename), current)
        finally
            Base.process_running(process) && kill(process)
            wait(process)
            PerfChecker._cleanup_allocation_artifacts!(identical_artifacts)
        end
        @test read(identical_file, String) == baseline
        rm(identical_file)
        config = PerfConfig(:alloc; path = environment, quiet = true, repeat = false,
            targets = ["PerfCheckerAllocationFixture"],
            extra_devops = [Pkg.PackageSpec(path = source)])

        for outcome in (:success, :identical_trace, :preparation_error, :measurement_error,
            :preparation_interrupt, :interrupt)
            previous = outcome === :identical_trace ? baseline : original
            marker = joinpath(directory, "worker-$(outcome)")
            setup = quote
                # Use the worker's actual PID to exercise a reused trace filename.
                write($operation_file * "." * string(getpid()) * ".mem", $previous)
                using PerfCheckerAllocationFixture
                write($marker, string(getpid()))
                $(outcome === :preparation_interrupt ? :(sleep(120)) : :(nothing))
                $(outcome === :preparation_error ? :(error("preparation fixture failure")) :
                  :(nothing))
            end
            workload = quote
                PerfCheckerAllocationFixture.allocate()
                write($marker, string(getpid()))
                write($(marker * "-measuring"), string(getpid()))
                $(outcome === :measurement_error ? :(error("measurement fixture failure")) :
                  outcome === :interrupt ? :(sleep(120)) : :(nothing))
            end
            if outcome in (:success, :identical_trace)
                result = PerfChecker.check_function(config, setup, workload)
                @test length(result.tables) == 1
                @test !isempty(only(result.tables))
                @test all(bytes -> bytes < 999999999, only(result.tables).bytes)
                @test any(file -> occursin("operation", file), only(result.tables).filename)
            elseif outcome in (:preparation_interrupt, :interrupt)
                captured = Ref{Any}(nothing)
                task = @async try
                    PerfChecker.check_function(config, setup, workload)
                catch error
                    captured[] = error
                end
                try
                    waiting_marker = outcome === :interrupt ? marker * "-measuring" : marker
                    @test timedwait(() -> isfile(waiting_marker) || istaskdone(task), 90) ==
                          :ok
                    @test isfile(waiting_marker)
                    istaskdone(task) || schedule(task, InterruptException(); error = true)
                    @test timedwait(() -> istaskdone(task), 45) == :ok
                    @test captured[] isa InterruptException
                finally
                    istaskdone(task) || schedule(task, InterruptException(); error = true)
                    wait(task)
                end
            else
                @test_throws Exception PerfChecker.check_function(config, setup, workload)
            end
            preserved = filter(
                file -> startswith(file, basename(operation_file) * ".") &&
                            endswith(file, ".mem") && file != basename(foreign),
                readdir(dirname(operation_file)))
            @test length(preserved) == 1
            @test read(joinpath(dirname(module_file), only(preserved)), String) == previous
            @test read(foreign, String) == "999999999 allocate() = nothing\n"
            @test read(unrelated, String) == "user allocation notes\n"
            @test only(PerfChecker.find_malloc_files([source]) ∩ [foreign]) == foreign
            @test length(PerfChecker.find_malloc_files([source])) == 3
            rm(joinpath(dirname(module_file), only(preserved)))
        end

        # Exercise the public asynchronous API used by interface runners. A
        # cancellation must stop this check and prevent the following feature.
        marker = joinpath(directory, "suite-measuring")
        unexpected = joinpath(directory, "suite-next-feature")
        entrypoint = joinpath(source, "allocation-feature.jl")
        following = joinpath(source, "following-feature.jl")
        write(entrypoint, """
write($(repr(operation_file)) * "." * string(getpid()) * ".mem", $(repr(original)))
using PerfCheckerAllocationFixture
function perf_workload(_)
    PerfCheckerAllocationFixture.allocate()
    write($(repr(marker)), string(getpid()))
    sleep(120)
end
""")
        write(following, "perf_workload(_) = write($(repr(unexpected)), \"unexpected\")\n")
        features = [
            FeatureSpec(:allocating; backend = :alloc, entrypoint,
                options = Dict(
                    :repeat => false, :targets => ["PerfCheckerAllocationFixture"])),
            FeatureSpec(:following; backend = :alloc, entrypoint = following)]
        package = PackageSuite("PerfCheckerAllocationFixture"; source,
            worker_environment = environment, versions = VersionNumber[], features)
        plan = plan_suite(SoftwareSuite(:allocation_cleanup, [package]); profile = :quick)
        job = launch_suite(plan)
        try
            @test timedwait(() -> isfile(marker) || istaskdone(job.task), 90) == :ok
            @test isfile(marker)
            @test cancel_suite!(job)
            @test timedwait(() -> istaskdone(job.task), 45) == :ok
            @test_throws InterruptException wait_suite(job)
            @test suite_job_dict(job)["status"] == "cancelled"
            @test !isfile(unexpected)
            pid = parse(Int, read(marker, String))
            @test read(operation_file * ".$pid.mem", String) == original
            @test length(PerfChecker.find_malloc_files([source])) == 3
        finally
            istaskdone(job.task) || cancel_suite!(job)
            wait(job.task)
        end

        ready = Ref(false)
        executor = function (_...)
            ready[] = true
            try
                sleep(120)
            finally
                throw(PerfChecker.CheckCleanupFailure(
                    Any[ErrorException("trace cannot be removed")], ["private inventory"]))
            end
        end
        failed = launch_suite(plan; executor)
        @test timedwait(() -> ready[], 5) == :ok
        @test cancel_suite!(failed)
        @test timedwait(() -> istaskdone(failed.task), 5) == :ok
        @test_throws PerfChecker.CheckCleanupFailure wait_suite(failed)
        snapshot = suite_job_dict(failed)
        @test snapshot["status"] == "failed"
        @test occursin("trace cannot be removed", snapshot["message"])
        @test occursin("private inventory", snapshot["message"])
    end
end

@testitem "Allocation cleanup preserves traces through path aliases" tags=[
    :unit, :allocation_cleanup] begin
    using PerfChecker
    mktempdir() do directory
        root = realpath(mkpath(joinpath(directory, "source")))
        alias = if Sys.iswindows()
            # Windows aliases are case insensitive, including realpath's
            # expansion of short directory names used by the VS Code host.
            uppercase(root)
        else
            link = joinpath(directory, "source-alias")
            symlink(root, link; dir_target = true)
            link
        end
        @test alias != root
        @test realpath(alias) == root
        original = joinpath(root, "operation.jl.123.mem")
        aliased = joinpath(alias, basename(original))
        bytes = Vector{UInt8}(codeunits("previous bytes\r\n"))
        write(original, bytes)
        info = stat(original)
        journal = joinpath(directory, "journal")
        # Reproduce an older worker journal spelling which differs from the
        # parent inventory. Recovery must use one physical-file identity.
        open(journal, "w") do io
            write(io, Int64(ncodeunits(aliased)))
            write(io, aliased)
            write(io, Int64(length(bytes)))
            write(io, bytes)
            write(io, UInt64(info.mode & 0o777))
            write(io, Float64(info.mtime))
            write(io, Float64(info.ctime))
        end
        artifacts = PerfChecker.AllocationArtifacts(123, [root],
            Dict{String, PerfChecker.AllocationSnapshot}(), journal)
        write(original, "current measurement\n")
        PerfChecker._cleanup_allocation_artifacts!(artifacts)
        @test read(original) == bytes
        @test collect(keys(artifacts.preserved)) == [original]
        @test PerfChecker._allocation_files([alias, root], 123) == [original]
        PerfChecker._cleanup_allocation_artifacts!(artifacts)
        @test read(aliased) == bytes
    end
end

@testitem "Allocation cleanup restores snapshots and is idempotent" tags=[
    :unit, :allocation_cleanup] begin
    using PerfChecker
    import TOML
    mktempdir() do directory
        original_file = joinpath(directory, "original.jl.123.mem")
        created_file = joinpath(directory, "created.jl.123.mem")
        foreign_file = joinpath(directory, "foreign.jl.456.mem")
        write(original_file, "original bytes\r\n")
        write(foreign_file, "other worker\n")
        artifacts = PerfChecker.AllocationArtifacts(123, String[],
            Dict{String, PerfChecker.AllocationSnapshot}(), joinpath(directory, "journal"))
        PerfChecker._register_allocation_roots!(artifacts, [directory])
        write(original_file, "overwritten by Julia\n")
        write(created_file, "this worker\n")
        # Registering an existing root again must not claim new worker traces as
        # pre-existing. A killed writer can also leave a partial journal tail.
        PerfChecker._register_allocation_roots!(artifacts, [directory])
        open(artifacts.journal, "a") do io
            write(io, Int64(5))
            write(io, UInt8('x'))
        end
        PerfChecker._cleanup_allocation_artifacts!(artifacts)
        PerfChecker._cleanup_allocation_artifacts!(artifacts)
        @test read(original_file, String) == "original bytes\r\n"
        @test !isfile(created_file)
        @test read(foreign_file, String) == "other worker\n"
        mode = UInt(stat(original_file).mode & 0o777)
        chmod(original_file, 0o444)
        PerfChecker._cleanup_allocation_artifacts!(artifacts)
        @test UInt(stat(original_file).mode & 0o777) == mode

        # A filesystem error must retain actual recovery bytes on disk, not
        # depend on the controller's in-memory snapshots remaining alive.
        rm(original_file)
        mkdir(original_file)
        @test_logs (:warn, "Could not clean allocation trace") begin
            @test_throws CompositeException PerfChecker._cleanup_allocation_artifacts!(artifacts)
        end
        PerfChecker._retain_allocation_inventory!(artifacts)
        inventory = TOML.parsefile(joinpath(directory, "allocation-inventory.toml"))
        recovered = PerfChecker.AllocationArtifacts(inventory["worker_pid"],
            String.(inventory["roots"]), Dict{String, PerfChecker.AllocationSnapshot}(),
            joinpath(directory, inventory["journal"]))
        @test isempty(recovered.preserved)
        rm(original_file; recursive = true)
        PerfChecker._cleanup_allocation_artifacts!(recovered)
        @test read(original_file, String) == "original bytes\r\n"
        @test UInt(stat(original_file).mode & 0o777) == mode
        @test read(foreign_file, String) == "other worker\n"
    end
end

@testitem "Check cleanup reports inventory IO failures" tags=[:unit, :allocation_cleanup] begin
    using PerfChecker
    mktempdir() do directory
        retained = joinpath(directory, "retained")
        completed = joinpath(directory, "completed")
        mkpath(retained)
        mkpath(completed)
        original = joinpath(retained, "source.jl.123.mem")
        write(original, "saved original bytes\n")
        artifacts = PerfChecker.AllocationArtifacts(123, String[],
            Dict{String, PerfChecker.AllocationSnapshot}(), joinpath(retained, "journal"))
        PerfChecker._register_allocation_roots!(artifacts, [retained])
        # A directory is a portable obstruction to opening the TOML file.
        mkdir(joinpath(retained, "allocation-inventory.toml"))
        failure = @test_logs (:warn, "Could not save allocation inventory metadata") (
            :warn, "PerfChecker cleanup incomplete; private inventory retained") begin
            try
                PerfChecker._cleanup_check_directories!(
                    Dict(1 => retained, 2 => completed),
                    Dict(1 => artifacts), Set([1]), Any[])
            catch error
                error
            end
        end
        @test failure isa PerfChecker.CheckCleanupFailure
        @test length(failure.errors) == 1
        @test failure.directories == [retained]
        @test isfile(artifacts.journal)
        @test !ispath(completed)
        @test occursin("allocation-inventory.toml", sprint(showerror, failure))
    end
end

@testitem "Allocation inventory survives controller exit" tags=[
    :integration, :allocation_cleanup] begin
    using PerfChecker
    import TOML
    mktempdir() do directory
        environment = joinpath(directory, "environment")
        mkpath(environment)
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        source = joinpath(directory, "operation.jl")
        write(source, "allocate() = copy(fill(1, 4096))\n")
        original = "original trace survives controller exit\r\n"
        marker = joinpath(directory, "retained-path")
        preparation = quote
            trace = $source * "." * string(getpid()) * ".mem"
            write(trace, $original)
            include($source)
            rm(trace)
            mkdir(trace)
        end
        measurement = :(allocate())
        controller = quote
            using PerfChecker
            config = PerfConfig(:alloc; path = $environment, quiet = true, repeat = false,
                targets = ["unloaded allocation fixture"])
            try
                PerfChecker.check_function(config, Meta.parse($(string(preparation))),
                    Meta.parse($(string(measurement))))
                error("expected real cleanup failure")
            catch failure
                failure isa PerfChecker.CheckCleanupFailure || rethrow()
                write($marker, only(failure.directories))
            end
        end
        retained = nothing
        try
            command = Cmd([Base.julia_cmd()[1], "--startup-file=no",
                "--code-coverage=none", "--track-allocation=none",
                "--project=$(dirname(Base.active_project()))", "-e", string(controller)])
            @test success(run(command))
            retained = read(marker, String)
            @test isdir(retained)
            inventory = TOML.parsefile(joinpath(retained, "allocation-inventory.toml"))
            recovered = PerfChecker.AllocationArtifacts(inventory["worker_pid"],
                String.(inventory["roots"]), Dict{String, PerfChecker.AllocationSnapshot}(),
                joinpath(retained, inventory["journal"]))
            @test isempty(recovered.preserved)
            trace = source * ".$(recovered.pid).mem"
            @test isdir(trace)
            rm(trace; recursive = true)
            PerfChecker._cleanup_allocation_artifacts!(recovered)
            @test read(trace, String) == original
            @test read(source, String) == "allocate() = copy(fill(1, 4096))\n"
        finally
            # The failure directory deliberately survives the child controller;
            # this second process owns its recovery and eventual removal.
            retained === nothing && isfile(marker) && (retained = read(marker, String))
            retained === nothing || rm(retained; recursive = true, force = true)
        end
    end
end
