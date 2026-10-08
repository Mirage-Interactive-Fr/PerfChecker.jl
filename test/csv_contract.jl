@testitem "CSV exports preserve measured values and replace existing files" tags=[:csv_contract] begin
    using PerfChecker, CSV
    expected = get(ENV, "PERFCHECKER_EXPECT_CSV_VERSION", "")
    isempty(expected) || @test string(Base.pkgversion(CSV)) == expected
    mktempdir() do directory
        path = joinpath(directory, "nested", "measurements.csv")
        original = PerfChecker.Table(
            time = [1.25, -0.0, NaN],
            bytes = Int64[0, Int64(typemax(Int32)) + 1, 192],
            label = Union{Missing, String}[
                "measurement é, \"quoted\"", "first\nsecond", missing],
            passed = [true, false, true])
        @test table_to_csv(original, path) == path
        restored = csv_to_table(path)
        @test propertynames(restored) == propertynames(original)
        @test all(isequal.(restored.time, original.time))
        @test restored.bytes == original.bytes
        @test eltype(restored.bytes) <: Integer
        @test all(isequal.(restored.label, original.label))
        @test all(value -> ismissing(value) || value isa AbstractString, restored.label)
        @test restored.passed == original.passed
        replacement = PerfChecker.Table(time = [4.5], bytes = Int64[64])
        table_to_csv(replacement, path)
        reloaded = csv_to_table(path)
        @test propertynames(reloaded) == (:time, :bytes)
        @test length(reloaded) == 1
        @test reloaded.time == replacement.time
        @test reloaded.bytes == replacement.bytes
        @test !occursin("quoted", read(path, String))
        @test_throws Exception csv_to_table(joinpath(directory, "absent.csv"))
    end
end

@testitem "Run metadata appends one header and retains quoted fields and UUIDs" tags=[:csv_contract] begin
    using PerfChecker, CSV, UUIDs
    expected = get(ENV, "PERFCHECKER_EXPECT_CSV_VERSION", "")
    isempty(expected) || @test string(Base.pkgversion(CSV)) == expected
    mktempdir() do directory
        path = PerfChecker.metadata_path(directory)
        config = PerfChecker.normalize_config(:alloc,
            Dict(:path => directory, :tags => [:normal, Symbol("é,\n\"quoted\"")]))
        first_run = PerfChecker.run_metadata(config, "Example", v"0.5.5",
            :(nothing), :(1 + 1), PerfChecker.HwInfo())
        second_run = PerfChecker.run_metadata(config, "Example", v"0.5.5",
            :(nothing), :(2 + 2), PerfChecker.HwInfo())
        @test PerfChecker.write_run_metadata(path, first_run) === first_run
        @test PerfChecker.write_run_metadata(path, second_run) === second_run
        @test count(startswith("backend,"), split(read(path, String), '\n')) == 1
        rows = CSV.read(path, PerfChecker.Table)
        @test length(rows) == 2
        @test all(value -> value isa AbstractString, rows.package)
        @test rows.package == ["Example", "Example"]
        @test rows.tags == fill(PerfChecker.tags_to_string(config.tags), 2)
        @test string.(rows.result_uuid) ==
              string.([first_run.result_uuid, second_run.result_uuid])
        @test rows.threads == fill(config.threads, 2)
        @test PerfChecker.metadata_has_result(path, first_run.result_uuid)
        @test PerfChecker.metadata_has_result(path, second_run.result_uuid)
        @test !PerfChecker.metadata_has_result(path, uuid4())
        @test !PerfChecker.metadata_has_result(joinpath(directory, "absent.csv"), uuid4())
        malformed = joinpath(directory, "unrecognized.csv")
        for contents in ("", "other,result_uuid\nx,$(first_run.result_uuid)\n",
            "backend,package\nalloc,Example\n", "backend,result_uuid\nalloc,\n")
            write(malformed, contents)
            @test !PerfChecker.metadata_has_result(malformed, first_run.result_uuid)
        end
    end
end

@testitem "Legacy measurement cache reads CSV values without executing workload" tags=[:csv_contract] begin
    using PerfChecker, CSV
    expected = get(ENV, "PERFCHECKER_EXPECT_CSV_VERSION", "")
    isempty(expected) || @test string(Base.pkgversion(CSV)) == expected
    mktempdir() do directory
        write(joinpath(directory, "Project.toml"), "[deps]\n")
        options = Dict(:path => directory, :quiet => true,
            :pkgs => ("Example", :custom, [v"0.5.5"], false))
        config = PerfChecker.normalize_config(:benchmark, options)
        setup = :(error("cached setup must not execute"))
        workload = :(error("cached workload must not execute"))
        metadata = PerfChecker.run_metadata(config, "Example", v"0.5.5",
            setup, workload, PerfChecker.HwInfo())
        output = PerfChecker.output_path(directory, metadata.result_uuid)
        table = PerfChecker.Table(time = [1.5, 2.5], bytes = Int64[192, 64])
        table_to_csv(table, output)
        PerfChecker.write_run_metadata(PerfChecker.metadata_path(directory), metadata)
        csv_before = read(output)
        metadata_before = read(PerfChecker.metadata_path(directory))
        result = PerfChecker.check_function(:benchmark, options, setup, workload)
        @test length(result.tables) == 1
        @test only(result.tables).time == table.time
        @test only(result.tables).bytes == table.bytes
        @test read(output) == csv_before
        @test read(PerfChecker.metadata_path(directory)) == metadata_before
        @test isempty(filter(name -> endswith(name, ".mem"), readdir(directory)))
    end
end
