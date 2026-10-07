@testitem "Exact profile source boundaries and virtual sources" tags=[:profile_contract] begin
    using PerfChecker
    const Runtime = PerfChecker.PerfCheckerProfileRuntime
    mktempdir() do directory
        root = joinpath(directory, "Package", "src")
        @test Runtime.source_in_roots(joinpath(root, "child", "work.jl"), [root])
        @test Runtime.source_in_roots(joinpath(root, "..", "src", "work.jl"), [root])
        @test !Runtime.source_in_roots(root * "-extra/work.jl", [root])
        @test !Runtime.source_in_roots(joinpath(directory, "Package", "other.jl"), [root])
        for source in ("", "none", "string", "REPL", "REPL[3]")
            @test !Runtime.source_in_roots(source, [pwd()])
        end
        if Sys.iswindows()
            @test !Runtime.within_root("Z:\\outside\\work.jl", "C:\\Package\\src")
        end
        frames = [(file = Symbol(root * "-extra/work.jl"), line = 9, from_c = false)]
        positions = Runtime.allocation_source_positions(frames, [root])
        @test isempty(positions)
        # An actual allocation capture outside the exact target scope retains its
        # measured whole-operation totals but produces no invented target site.
        summary = Runtime.allocation_summary(total_bytes = 64, total_allocations = 1,
            sampled_allocations = 1, source_allocations = 1,
            retained_allocations = length(positions), retained_bytes = 0,
            sample_rate = 1.0, profile_evaluations = 1, weight_semantics = "sampled")
        @test summary["status"] == "outside_target_scope"
        @test summary["total_bytes"] == 64
    end
end

@testitem "Allocation capture statuses preserve independent totals" tags=[:profile_contract] begin
    using PerfChecker
    const Runtime = PerfChecker.PerfCheckerProfileRuntime
    defaults = (total_bytes = 64, total_allocations = 2, sampled_allocations = 0,
        retained_allocations = 0, source_allocations = 0, retained_bytes = 0,
        sample_rate = 0.00001, profile_evaluations = 3, weight_semantics = "sampled")
    sparse = Runtime.allocation_summary(; defaults...)
    @test sparse["status"] == "no_samples"
    @test sparse["total_bytes"] == 64
    @test sparse["total_allocations"] == 2
    @test sparse["total_measurement_evaluations"] == 2
    @test sparse["bytes_measurement_evaluations"] == 1
    @test sparse["count_measurement_evaluations"] == 1
    zero = Runtime.allocation_summary(;
        merge(defaults,
            (total_bytes = 0, total_allocations = 0))...)
    @test zero["status"] == "zero_allocations"
    unknown = Runtime.allocation_summary(; merge(defaults, (sampled_allocations = 2,))...)
    @test unknown["status"] == "unattributed_samples"
    counted = Runtime.allocation_summary(;
        merge(defaults,
            (sampled_allocations = 1, source_allocations = 1, retained_allocations = 1))...)
    @test counted["status"] == "complete"
    @test occursin("zero sampled byte weight", counted["message"])
    @test_throws ArgumentError Runtime.allocation_summary(;
        merge(defaults,
            (retained_allocations = 1,))...)
    @test_throws ArgumentError Runtime.allocation_summary(;
        merge(defaults,
            (retained_bytes = 4,))...)
    @test_throws ArgumentError Runtime.allocation_summary(;
        merge(defaults,
            (sample_rate = 0.0,))...)

    # Cumulative bytes can exceed Int32 without any individual allocation doing
    # so. Inject sizes; this regression never reserves gigabytes of memory.
    grouped = Dict(:first => (typemax(Int32), Int32(1)),
        :second => (typemax(Int32), Int32(1)))
    bytes, count = Runtime.allocation_sample_totals(grouped)
    @test bytes == 2 * Int64(typemax(Int32))
    @test bytes isa Int64
    @test count == 2
    @test count isa Int64

    definitions, observations, diagnostics = Dict{String, Dict{String, Any}}(),
    Dict{String, Any}[], Dict{String, Any}[]
    PerfChecker._append_allocation_profile_records!(definitions, observations,
        diagnostics, sparse, "fresh", Dict("case_id" => "case"), "comparison")
    @test [o["value"] for o in observations] == [64, 2]
    @test all(o -> o["aggregation"] == "independent_operation_total", observations)
    @test all(o -> !haskey(o["attributes"], "source_file"), observations)
    @test only(diagnostics)["rule_id"] == "allocation.profile.no_samples"
    @test only(diagnostics)["severity"] == "warning"
end

@testitem "Allocation profiles complete in real top-level workers" tags=[
    :integration, :profile_contract, :profile_worker] begin
    using PerfChecker
    import Pkg

    mktempdir() do directory
        environment = joinpath(directory, "environment")
        source = joinpath(directory, "PerfCheckerProfileFixture")
        mkpath(environment)
        mkpath(joinpath(source, "src"))
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        write(joinpath(source, "Project.toml"), """
name = "PerfCheckerProfileFixture"
uuid = "70b37676-3d7a-4fd4-b094-f9bfb6c5dcf3"
version = "0.1.0"
""")
        operation = joinpath(source, "src", "PerfCheckerProfileFixture.jl")
        write(operation, """
__precompile__(false)
module PerfCheckerProfileFixture
allocate(values) = copy(values)
end
""")
        @testset "fresh=$fresh" for fresh in (false, true)
            worker_marker = joinpath(directory, "worker-$(fresh)")
            lifecycle = joinpath(directory, "lifecycle-$(fresh)")
            setup = quote
                using PerfCheckerProfileFixture
                write($worker_marker, string(getpid()))
                function perf_setup()
                    open($lifecycle, "a") do io
                        println(io, "prepare")
                    end
                    fill(1, 32)
                end
                perf_workload(values) = PerfCheckerProfileFixture.allocate(values)
                perf_oracle(values, result) = result == values && result !== values
                function perf_cleanup(values)
                    open($lifecycle, "a") do io
                        println(io, "cleanup")
                    end
                end
            end
            config = PerfConfig(:profile_alloc; path = environment, quiet = true,
                targets = ["PerfCheckerProfileFixture"],
                extra_devops = [Pkg.PackageSpec(path = source)],
                fresh_feature = fresh, feature_oracle = "perf_oracle",
                profile_repetitions = 2, sample_rate = 1.0)
            # Use the production Malt.eval route: an extra let/function around
            # check() would conceal top-level loop scope failures.
            result = PerfChecker.check_function(config, setup,
                :(PerfCheckerProfileFixture.allocate(fill(1, 32))))
            @test parse(Int, read(worker_marker, String)) != getpid()
            table = only(result.tables)
            summary = only(result.qualifications)["allocation_profile"]
            @test summary["status"] == "complete"
            @test summary["total_bytes"] > 0
            @test summary["total_allocations"] > 0
            @test summary["sampled_allocations"] > 0
            @test summary["source_allocations"] > 0
            @test summary["retained_allocations"] > 0
            @test summary["profile_evaluations"] == 2
            @test !isempty(table)
            @test sum(table.bytes) > 0
            @test sum(table.allocs) > 0
            @test any(row -> row.filename == operation, table)
            @test all(row -> !isempty(row.stack), table)
            if fresh
                entries = readlines(lifecycle)
                @test count(==("prepare"), entries) == 5
                @test count(==("cleanup"), entries) == 5
            end
        end
        @test isempty(PerfChecker.find_malloc_files([source]))
    end
end

@testitem "Zero-allocation operations succeed in both profile APIs" tags=[:profile_contract] begin
    using PerfChecker
    expression = PerfChecker.check(PerfChecker.default_options(Val(:profile_alloc)),
        quote
            nothing
        end, Val(:profile_alloc))
    Core.eval(Main, :(import Profile))
    isdefined(Main, :PerfCheckerProfileRuntime) || Core.eval(Main,
        :(include($(joinpath(pkgdir(PerfChecker), "src", "profile_runtime.jl")))))
    capture_function = Core.eval(Main, quote
        () -> begin
            $expression
        end
    end)
    capture = Base.invokelatest(capture_function)
    @test isempty(PerfChecker.to_table(capture))
    @test capture.summary["status"] == "zero_allocations"
    @test capture.summary["total_bytes"] == capture.summary["total_allocations"] == 0
    excluded_expression = PerfChecker.check(
        merge(PerfChecker.default_options(Val(:profile_alloc)),
            Dict(:targets => ["TestItems"])),
        :(zeros(UInt8, 1024)), Val(:profile_alloc))
    excluded = Core.eval(Main, quote
        let
            $excluded_expression
        end
    end)
    @test isempty(PerfChecker.to_table(excluded))
    @test excluded.summary["status"] == "outside_target_scope"
    @test excluded.summary["total_bytes"] > 0
    @test excluded.summary["total_allocations"] > 0

    prepared, cleaned = Ref(0), Ref(0)
    case = (prepare = () -> (prepared[] += 1; nothing), operation = _ -> nothing,
        verify = (_, result) -> result === nothing, cleanup = _ -> (cleaned[] += 1))
    raw = PerfChecker.SharedScenarioRuntime.execute_loaded(case, "profile_alloc", 2)
    @test raw["status"] == "complete"
    @test raw["allocation_profile"]["status"] == "zero_allocations"
    @test isempty(raw["allocation_sites"])
    @test prepared[] == cleaned[] == 5 # warmup, two independent totals, two profiles
end

@testitem "Legacy allocation cache hit preserves measured totals without execution" tags=[:profile_contract] begin
    using PerfChecker
    mktempdir() do directory
        write(joinpath(directory, "Project.toml"), "[deps]\n")
        options = Dict(:path => directory, :quiet => true,
            :sample_rate => 0.00001,
            :pkgs => ("Example", :custom, [v"0.5.5"], false))
        config = PerfChecker.normalize_config(:profile_alloc, options)
        setup, workload = :(error("cache setup executed")),
        :(error("cache workload executed"))
        metadata = PerfChecker.run_metadata(config, "Example", v"0.5.5",
            setup, workload, PerfChecker.HwInfo())
        output = PerfChecker.output_path(directory, metadata.result_uuid)
        summary = PerfChecker.PerfCheckerProfileRuntime.allocation_summary(
            total_bytes = 64, total_allocations = 2, sampled_allocations = 0,
            source_allocations = 0, retained_allocations = 0, retained_bytes = 0,
            sample_rate = 0.00001, profile_evaluations = 1, weight_semantics = "sampled")
        table = PerfChecker.to_table(PerfChecker.ProfileAllocSite[])
        PerfChecker.table_to_csv(table, output)
        PerfChecker._write_allocation_cache(output, table, summary)
        PerfChecker.write_run_metadata(PerfChecker.metadata_path(directory), metadata)
        result = PerfChecker.check_function(:profile_alloc, options, setup, workload)
        @test isempty(only(result.tables))
        @test only(result.qualifications)["allocation_profile"] == summary
        @test only(result.qualifications)["allocation_profile"]["total_bytes"] == 64
    end
end

@testitem "Allocation cache retains empty evidence and typed stacks" tags=[:profile_contract] begin
    using PerfChecker
    using TOML
    const Runtime = PerfChecker.PerfCheckerProfileRuntime
    mktempdir() do directory
        path = joinpath(directory, "f45bd5c4-426a-4c53-b04a-df80ecb1c66c.csv")
        summary = Runtime.allocation_summary(total_bytes = 32, total_allocations = 1,
            sampled_allocations = 0, source_allocations = 0, retained_allocations = 0,
            retained_bytes = 0, sample_rate = 0.00001, profile_evaluations = 1,
            weight_semantics = "sampled")
        sites = PerfChecker.ProfileAllocSite[]
        table = PerfChecker.to_table(sites)
        PerfChecker.table_to_csv(table, path)
        @test PerfChecker._read_allocation_cache(path) === nothing # old cache is a miss
        PerfChecker._write_allocation_cache(path, table, summary)
        cached = PerfChecker._read_allocation_cache(path)
        @test cached.summary == summary
        @test cached.sites == sites
        @test eltype(cached.sites) == PerfChecker.ProfileAllocSite
        sites = PerfChecker.ProfileAllocSite[(bytes = 32.0, allocs = 1.0,
            filename = "/source/work.jl", line = 8, stack = ["work (/source/work.jl:8)"])]
        summary = Runtime.allocation_summary(total_bytes = 32, total_allocations = 1,
            sampled_allocations = 1, source_allocations = 1, retained_allocations = 1,
            retained_bytes = 32, sample_rate = 1.0, profile_evaluations = 1,
            weight_semantics = "sampled")
        PerfChecker._write_allocation_cache(path, PerfChecker.to_table(sites), summary)
        @test PerfChecker._read_allocation_cache(path).sites == sites
        document = TOML.parsefile(PerfChecker._allocation_cache_path(path))
        document["result_uuid"] = "different"
        open(io -> TOML.print(io, document), PerfChecker._allocation_cache_path(path), "w")
        @test PerfChecker._read_allocation_cache(path) === nothing
        @test readdir(directory) ==
              [basename(path), basename(PerfChecker._allocation_cache_path(path))]
    end
end
