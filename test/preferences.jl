@testitem "Persistent check preferences and precedence" tags=[:unit, :config, :preferences] begin
    using PerfChecker
    import Pkg, Preferences, TOML

    previous_project = Base.active_project()
    previous_load_path = copy(LOAD_PATH)
    mktempdir() do directory
        local_project = joinpath(directory, "local")
        inherited_project = joinpath(directory, "inherited")
        workload = joinpath(directory, "workload")
        for path in (local_project, inherited_project, workload)
            mkpath(path)
            write(joinpath(path, "Project.toml"), "[deps]\n")
        end
        write(joinpath(workload, "Project.toml"),
            "name = \"PreferenceFixture\"\nuuid = \"d39d587d-7ad5-46b0-86ae-70609d058e52\"\nversion = \"0.1.0\"\n")
        try
            empty!(LOAD_PATH)
            append!(LOAD_PATH, ["@", inherited_project, "@stdlib"])
            Pkg.activate(inherited_project; io = devnull)
            set_check_preferences!(threads = 2, repeat = false, quiet = true)
            Preferences.set_preferences!(PerfChecker, "unrelated" => "preserve";
                force = true)
            inherited_before = read(joinpath(inherited_project, "LocalPreferences.toml"))
            Pkg.activate(local_project; io = devnull)
            @test check_preferences() ==
                  Dict(:threads => 2, :repeat => false, :quiet => true)
            @test !isfile(joinpath(local_project, "LocalPreferences.toml"))

            resolved = PerfChecker.normalize_config(:network, Dict(:path => workload))
            @test resolved.threads == 2
            @test !resolved.repeat
            @test all(==("preferences"), values(resolved.check_configuration["origins"]))
            explicit = PerfChecker.normalize_config(:network,
                Dict(:path => workload, :threads => 2, :repeat => false, :quiet => true))
            @test explicit.config_hash == resolved.config_hash
            @test all(==("explicit"), values(explicit.check_configuration["origins"]))
            @test PerfChecker.normalize_config(:network,
                Dict(:path => workload, :threads => Int32(2))).config_hash ==
                  resolved.config_hash

            set_check_preferences!(threads = 1, export_prefs = true)
            @test check_preferences()[:threads] == 1
            @test TOML.parsefile(joinpath(local_project, "Project.toml"))[
                "preferences"]["PerfChecker"]["check_threads"] == 1
            set_check_preferences!(threads = 2)
            @test check_preferences()[:threads] == 2
            reset_check_preferences!(:threads)
            @test check_preferences()[:threads] == 1
            reset_check_preferences!(:threads; block_inheritance = true)
            @test !haskey(check_preferences(), :threads)
            @test PerfChecker.normalize_config(:network,
                Dict(:path => workload)).threads == 1
            reset_check_preferences!(:threads)
            @test check_preferences()[:threads] == 1
            reset_check_preferences!(:threads; export_prefs = true)
            @test check_preferences()[:threads] == 2

            set_check_preferences!(threads = 1)
            @test resolved.threads == 2 # a previously resolved check is immutable
            changed = PerfChecker.normalize_config(:network, Dict(:path => workload))
            @test changed.config_hash != resolved.config_hash
            @test PerfChecker.normalize_config(:network,
                Dict(:path => workload, :threads => 2)).config_hash == resolved.config_hash
            returned = check_preferences()
            returned[:threads] = 99
            @test check_preferences()[:threads] == 1

            local_before = read(joinpath(local_project, "LocalPreferences.toml"))
            for invalid in (true, 0, -1, 1.5, "2", big(typemax(Int)) + 1)
                @test_throws ArgumentError set_check_preferences!(threads = invalid)
                @test_throws ArgumentError PerfChecker.normalize_config(:network,
                    Dict(:path => workload, :threads => invalid))
            end
            for key in (:repeat, :quiet), invalid in (0, 1, "true", nothing)
                @test_throws ArgumentError set_check_preferences!(; key => invalid)
                @test_throws ArgumentError PerfChecker.normalize_config(:network,
                    Dict(:path => workload, key => invalid))
            end
            @test_throws ArgumentError set_check_preferences!(path = directory)
            @test_throws ArgumentError reset_check_preferences!(:path)
            @test read(joinpath(local_project, "LocalPreferences.toml")) == local_before

            # Direct Preferences.jl edits are validated too, rather than silently
            # coercing a corrupted persisted value when the next check starts.
            Preferences.set_preferences!(PerfChecker, "check_repeat" => "false";
                force = true)
            @test_throws ArgumentError check_preferences()
            @test_throws ArgumentError PerfChecker.normalize_config(:network,
                Dict(:path => workload))
            reset_check_preferences!(:repeat)
            @test check_preferences()[:repeat] == false

            source = joinpath(directory, "feature.jl")
            write(source, "perf_workload() = (bytes_sent=1, operations=1)\n")
            feature = FeatureSpec(:network; backend = :network, entrypoint = source)
            package = PackageSuite("PreferenceFixture"; source = workload,
                worker_environment = workload, versions = VersionNumber[], features = [feature])
            planned = only(plan_suite(SoftwareSuite(:preferences, [package])).runs)
            settings = check_preferences()
            suite_config = PerfChecker._run_config(planned, Dict();
                resolve_preferences = true, preferences = settings)
            @test suite_config.options[:quiet]
            @test suite_config.check_configuration["origins"]["quiet"] == "preferences"
            @test PerfChecker.normalize_config(suite_config) === suite_config
            @test PerfChecker.normalize_config(:network, suite_config) === suite_config
            @test_throws ArgumentError PerfChecker.normalize_config(:profile, suite_config)
            # Both default preflight providers resolve and validate shared settings
            # before any worker, including invalid explicit values.
            @test_throws ArgumentError PerfChecker._default_preflight_resolver(
                planned, Dict(:threads => 0))
            @test_throws ArgumentError PerfChecker._default_preflight_probe_runner(
                planned, Dict(:quiet => "true"))
            suite_override = PerfChecker._run_config(planned, Dict(:quiet => false);
                resolve_preferences = true, preferences = settings)
            @test !suite_override.options[:quiet]
            @test suite_override.check_configuration["origins"]["quiet"] == "explicit"
            suite_default = PerfChecker._run_config(planned, Dict();
                resolve_preferences = true, preferences = Dict{Symbol, Any}())
            @test suite_default.options[:quiet]
            @test suite_default.check_configuration["origins"]["quiet"] == "default"
            set_check_preferences!(quiet = false)
            @test suite_config.options[:quiet] # the suite's frozen snapshot survives edits
            @test settings[:quiet]

            # A new Julia process imports the installed package before activating
            # the preference-only fixture, so this needs no registry or network.
            code = "using PerfChecker; import Pkg; " *
                   "Pkg.activate($(repr(local_project)); io=devnull); " *
                   "empty!(LOAD_PATH); append!(LOAD_PATH, $(repr(["@", inherited_project, "@stdlib"]))); " *
                   "p=check_preferences(); print(p[:threads], \",\", p[:repeat], \",\", p[:quiet])"
            command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --gcthreads=1 --project=$(dirname(previous_project)) -e $code`
            output = read(
                addenv(command,
                    "JULIA_LOAD_PATH" => join(
                        previous_load_path, Sys.iswindows() ? ';' : ':'),
                    "JULIA_PKG_PRECOMPILE_AUTO" => "0", "OPENBLAS_NUM_THREADS" => "1"),
                String)
            @test output == "1,false,false"
            @test read(joinpath(inherited_project, "LocalPreferences.toml")) ==
                  inherited_before
        finally
            Pkg.activate(previous_project; io = devnull)
            empty!(LOAD_PATH)
            append!(LOAD_PATH, previous_load_path)
        end
    end
    @test Base.active_project() == previous_project
    @test LOAD_PATH == previous_load_path
end

@testitem "A real suite freezes preferences across workers" tags=[
    :integration, :config, :preferences] begin
    using PerfChecker
    import Pkg

    previous_project = Base.active_project()
    previous_load_path = copy(LOAD_PATH)
    mktempdir() do directory
        preferences = joinpath(directory, "preferences")
        workload = joinpath(directory, "workload")
        source = joinpath(directory, "PreferenceFixture")
        for path in (preferences, workload)
            mkpath(path)
            write(joinpath(path, "Project.toml"), "[deps]\n")
        end
        mkpath(joinpath(source, "src"))
        write(joinpath(source, "Project.toml"),
            "name = \"PreferenceFixture\"\nuuid = \"d39d587d-7ad5-46b0-86ae-70609d058e52\"\nversion = \"0.1.0\"\n")
        write(joinpath(source, "src", "PreferenceFixture.jl"),
            "module PreferenceFixture\nend\n")
        entrypoint = joinpath(source, "feature.jl")
        write(entrypoint, """
        perf_setup() = Ref(0)
        function perf_workload(calls)
            calls[] += 1
            (bytes_sent=Threads.nthreads(), bytes_received=calls[], operations=getpid())
        end
        """)
        try
            empty!(LOAD_PATH)
            append!(LOAD_PATH, ["@", "@stdlib"])
            Pkg.activate(preferences; io = devnull)
            set_check_preferences!(threads = 2, repeat = false, quiet = true)
            features = [FeatureSpec(id; backend = :network, entrypoint,
                            options = Dict(:network_repetitions => 1))
                        for id in (:first, :second)]
            package = PackageSuite("PreferenceFixture"; source,
                worker_environment = workload, versions = VersionNumber[], features)
            plan = plan_suite(
                SoftwareSuite(:frozen_preferences, [package]); profile = :quick)
            @test length(plan.runs) == 2
            changed = Ref(false)
            callback = progress -> begin
                if progress["completed"] == 1 && !changed[]
                    set_check_preferences!(threads = 1, repeat = true, quiet = false)
                    changed[] = true
                end
            end
            results = run_suite(plan; progress_callback = callback)
            @test changed[]
            @test length(results.runs) == 2
            for run in results.runs
                @test run.status == :pass
                run.result === nothing && continue
                @test only(only(run.result.tables).bytes_sent) == 2
                @test only(only(run.result.tables).bytes_received) == 1 # no warmup
                snapshot = run.qualification["check_configuration"]
                @test snapshot["values"] ==
                      Dict("threads" => 2, "repeat" => false, "quiet" => true)
                @test all(==("preferences"), values(snapshot["origins"]))
                @test snapshot["config_hash"] isa String
                if Sys.isunix()
                    pid = Int(only(only(run.result.tables).operations))
                    @test ccall(:kill, Cint, (Cint, Cint), pid, 0) == -1
                    @test Base.Libc.errno() == Base.Libc.ESRCH
                end
            end
            @test check_preferences() ==
                  Dict(:threads => 1, :repeat => true, :quiet => false)
            @test readdir(workload) == ["Project.toml"]
        finally
            Pkg.activate(previous_project; io = devnull)
            empty!(LOAD_PATH)
            append!(LOAD_PATH, previous_load_path)
        end
    end
    @test Base.active_project() == previous_project
    @test LOAD_PATH == previous_load_path
end
