@testitem "Allocation cache payloads bind the acquired shutdown receipt" tags=[
    :integration, :profile_cache_integrity] begin
    using PerfChecker, SHA, TOML

    function file_state(directory)
        Dict(relpath(joinpath(parent, file), directory) => begin
                 path = joinpath(parent, file)
                 info = stat(path)
                 (read(path), info.mode, info.mtime, info.ctime)
             end
        for (parent, _, files) in walkdir(directory) for file in files)
    end

    mktempdir() do directory
        environment = joinpath(directory, "CacheIntegrityFixture")
        mkpath(joinpath(environment, "src"))
        write(joinpath(environment, "Project.toml"), """
name = "CacheIntegrityFixture"
uuid = "952f3c73-71f9-4e30-80e0-f3a87fb0ef54"
version = "0.1.0"

[compat]
julia = "1.10"
""")
        write(joinpath(environment, "src", "CacheIntegrityFixture.jl"), """
__precompile__(false)
module CacheIntegrityFixture
Base.@noinline allocate(values) = copy(values)
end
""")
        # Registered labels exercise the real publication/cache path. The
        # prepared fixture is explicit and does not qualify PatternFolds itself.
        config = PerfConfig(:profile_alloc; path = environment,
            prepared_environment = environment, targets = ["CacheIntegrityFixture"],
            pkgs = ("PatternFolds", :custom, [v"0.2.4"], false), quiet = true,
            repeat = false, profile_repetitions = 1, sample_rate = 1.0)
        preparation = quote
            using CacheIntegrityFixture
            payload = collect(1:32)
            warm = CacheIntegrityFixture.allocate(payload)
            @assert warm == payload && warm !== payload
        end
        operation = :(CacheIntegrityFixture.allocate(payload))
        original = PerfChecker.check_function(config, preparation, operation)
        @test length(original.tables) == 1
        @test !isempty(only(original.tables))
        acquired = only(original.qualifications)["worker_shutdown"]
        @test acquired["origin"] == "current_run"
        receipt_path = acquired["receipt_path"]
        csv = PerfChecker.cached_output_path(PerfChecker.normalize_config(config),
            "PatternFolds", v"0.2.4", preparation, operation, PerfChecker.HwInfo())
        sidecar = PerfChecker._allocation_cache_path(csv)
        csv_bytes, sidecar_bytes, receipt_bytes = read(csv), read(sidecar),
        read(receipt_path)
        receipt = PerfChecker._json_parsefile(receipt_path)
        @test receipt["csv_sha256"] == bytes2hex(sha256(csv_bytes))
        @test receipt["allocation_profile_sha256"] == bytes2hex(sha256(sidecar_bytes))
        report = receipt["report"]
        @test report["complete"] === true
        @test report["process_exited"] === true
        @test report["exitcode"] == 0
        @test report["termsignal"] == 0
        @test report["tasks_done"] === true
        println("PROFILE_CACHE_FRESH_WORKER pid=", report["pid"], " reaped=true")
        Sys.islinux() && @test !ispath("/proc/$(report["pid"])")

        function reuse()
            # Every actual Worker constructor would fail its zero startup budget.
            # Cache acceptance or rejection must finish before that admission.
            withenv("JULIA_WORKER_TIMEOUT" => "0") do
                PerfChecker.check_function(config, preparation, operation)
            end
        end
        before = file_state(environment)
        reused = reuse()
        @test isequal(collect(only(reused.tables)), collect(only(original.tables)))
        @test only(reused.qualifications)["allocation_profile"] ==
              only(original.qualifications)["allocation_profile"]
        @test only(reused.qualifications)["worker_shutdown"]["origin"] == "qualified_cache"
        @test isequal(file_state(environment), before)

        for mutation in (:sites, :summary, :missing_payload, :legacy_receipt,
            :wrong_digest, :csv_bytes)
            try
                if mutation in (:sites, :summary)
                    document = TOML.parse(String(copy(sidecar_bytes)))
                    if mutation === :sites
                        @test !isempty(document["sites"])
                        document["sites"][1]["filename"] = "valid-toml-but-wrong-source.jl"
                        document["sites"][1]["stack"] = ["valid unrelated stack"]
                    else
                        document["summary"]["profile_evaluations"] += 1
                    end
                    open(io -> TOML.print(io, document; sorted = true), sidecar, "w")
                    # The defect concerns valid payloads, not parser rejection or
                    # a changed result UUID/schema. Keep all other data intact.
                    parsed = TOML.parsefile(sidecar)
                    @test parsed["schema_version"] == document["schema_version"]
                    @test parsed["result_uuid"] == document["result_uuid"]
                    @test PerfChecker._read_allocation_cache(csv) !== nothing
                elseif mutation === :missing_payload
                    rm(sidecar)
                elseif mutation === :legacy_receipt
                    document = deepcopy(receipt)
                    delete!(document, "allocation_profile_sha256")
                    PerfChecker._write_json(receipt_path, document; canonical = true)
                elseif mutation === :wrong_digest
                    document = deepcopy(receipt)
                    document["allocation_profile_sha256"] = repeat("0", 64)
                    PerfChecker._write_json(receipt_path, document; canonical = true)
                else
                    open(io -> write(io, '\n'), csv, "a")
                end
                before = file_state(environment)
                failure = try
                    reuse()
                    nothing
                catch error
                    error
                end
                @test failure isa PerfChecker.HistoricalCacheUnqualified
                @test failure.path == csv
                @test !isempty(failure.reason)
                @test isequal(file_state(environment), before)
                # Deliberate historical reading remains available without
                # fabricating a successful shutdown qualification.
                @test !isempty(PerfChecker.csv_to_table(csv))
            finally
                # Restore only data and evidence produced by the real first run.
                write(csv, csv_bytes)
                write(sidecar, sidecar_bytes)
                write(receipt_path, receipt_bytes)
            end
        end
    end
end
