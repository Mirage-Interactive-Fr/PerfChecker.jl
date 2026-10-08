@testitem "Check lists validate before starting workers" tags=[:unit, :check_lists] begin
    using PerfChecker

    mktempdir() do directory
        marker = joinpath(directory, "started")
        options = Dict(:path => directory, :marker => marker)
        preparation = :(write(d[:marker], "worker started"))
        for backends in (Symbol[], [:alloc, :chairs], [:alloc, "benchmark"])
            @test_throws ArgumentError PerfChecker.check_function(
                backends, options, preparation, :(nothing))
            @test !isfile(marker)
        end
        @test_throws ArgumentError PerfChecker.check_function([:alloc],
            Dict(:path => directory, :threads => 0), preparation, :(nothing))
        @test !isfile(marker)
        config = PerfConfig(:alloc; path = directory, marker)
        @test_throws ArgumentError PerfChecker.check_function(
            [:alloc, :profile], config, preparation, :(nothing))
        @test !isfile(marker)
        @test options == Dict(:path => directory, :marker => marker)
    end
end

@testitem "Check lists preserve order, blocks and worker cleanup" tags=[
    :integration, :check_lists] begin
    using PerfChecker, BenchmarkTools, Chairmarks
    import Pkg

    mktempdir() do directory
        environment = joinpath(directory, "environment")
        mkpath(joinpath(environment, "src"))
        write(joinpath(environment, "Project.toml"), """
name = "PerfCheckerListFixture"
uuid = "94e47c8b-7a3a-4a52-ac28-2d26d8297413"
version = "0.1.0"

[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
Chairmarks = "0ca39b1e-fe0b-4e98-acfc-b1656634c4de"
""")
        source = joinpath(environment, "src", "PerfCheckerListFixture.jl")
        write(source, """
__precompile__(false)
module PerfCheckerListFixture
allocate(payload) = copy(payload)
end
""")
        preserved = source * ".987654321.mem"
        original = "pre-existing allocation trace\r\n"
        write(preserved, original)
        journal = joinpath(directory, "workers")
        options = Dict(:path => environment, :quiet => true, :samples => 1,
            :evals => 1, :seconds => 0.01, :repeat => false,
            :targets => ["PerfCheckerListFixture"], :payload => [17, 23, 41],
            :journal => journal)
        if Sys.islinux()
            options[:expected_affinity] = strip(only(filter(
                line -> startswith(line, "Cpus_allowed_list:"),
                readlines("/proc/self/status"))))
        end
        before = deepcopy(options)
        preparation = quote
            using PerfCheckerListFixture
            @assert d[:payload] == [17, 23, 41]
            if Sys.islinux()
                @assert strip(only(filter(line -> startswith(line, "Cpus_allowed_list:"),
                    readlines("/proc/self/status")))) == d[:expected_affinity]
            end
            open(d[:journal], "a") do io
                println(io, getpid(), '\t', dirname(Base.active_project()))
            end
        end
        workload = :(PerfCheckerListFixture.allocate(d[:payload]))
        backends = [:chairmark, :benchmark, :alloc, :benchmark]
        results = @check backends options begin
            using PerfCheckerListFixture
            @assert d[:payload] == [17, 23, 41]
            if Sys.islinux()
                @assert strip(only(filter(line -> startswith(line, "Cpus_allowed_list:"),
                    readlines("/proc/self/status")))) == d[:expected_affinity]
            end
            open(d[:journal], "a") do io
                println(io, getpid(), '\t', dirname(Base.active_project()))
            end
        end begin
            PerfCheckerListFixture.allocate(d[:payload])
        end
        @test length(results) == 4
        @test all(
            result -> result isa PerfChecker.CheckerResult && length(result.tables) == 1,
            results)
        @test :bytes in propertynames(only(results[1].tables))
        @test :memory in propertynames(only(results[2].tables))
        @test :filename in propertynames(only(results[3].tables))
        @test :memory in propertynames(only(results[4].tables))
        @test sum(only(results[3].tables).bytes) > 0
        @test options == before
        workers = split.(readlines(journal), '\t')
        @test length(workers) == 4
        @test length(unique(first.(workers))) == 4
        @test all(row -> !ispath(row[2]), workers)
        if Sys.islinux()
            @test all(row -> !ispath("/proc/" * row[1]), workers)
        end
        @test read(preserved, String) == original
        @test sort([joinpath(root, file) for (root, _, files) in walkdir(environment)
                    for file in files if endswith(file, ".mem")]) == [preserved]

        rm(journal)
        failing = quote
            @assert d[:payload] == [17, 23, 41]
            error("list workload failure")
        end
        failure = try
            PerfChecker.check_function([:alloc, :benchmark], options, preparation, failing)
            nothing
        catch error
            error
        end
        @test failure isa Exception
        @test occursin("list workload failure", sprint(showerror, failure))
        failed_workers = split.(readlines(journal), '\t')
        @test length(failed_workers) == 1
        @test !ispath(only(failed_workers)[2])
        Sys.islinux() && @test !ispath("/proc/" * only(failed_workers)[1])
        @test read(preserved, String) == original
        @test sort([joinpath(root, file) for (root, _, files) in walkdir(environment)
                    for file in files if endswith(file, ".mem")]) == [preserved]
    end
end
