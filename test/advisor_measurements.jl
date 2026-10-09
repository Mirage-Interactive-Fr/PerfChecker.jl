@testitem "Selected measurement context preserves units, scope and record semantics" tags=[
    :unit, :advisor] begin
    using PerfChecker
    function bundle(backend, column; values = [2, 4], scope = "workload", suffix = "")
        id, unit = PerfChecker._measurement_definition(backend, column)
        definition = PerfChecker._definition_dict(id * suffix, unit, backend)
        observations = [Dict{String, Any}("case_id" => "case", "target_id" => "target",
                            "measurement_definition" => id * suffix, "metric" => definition["metric"],
                            "unit" => unit, "value" => value, "sample_index" => index,
                            "scope" => scope, "aggregation" => "sample",
                            "attributes" => Dict(
                                "table_index" => 1, "source_file" => "PRIVATE_PATH"))
                        for (index, value) in enumerate(values)]
        RunBundle(
            Dict{String, Any}("run_id" => "run", "attempt_id" => "attempt",
                "state" => "complete", "qualification" => Dict("correctness" => "passed")),
            [definition], observations, Dict{String, Any}[], Dict{String, Any}[])
    end
    for (backend, column, unit, semantics, scope) in (
        (:benchmark, :times, "ns", "operation_measurement", "workload"),
        (:chairmark, :times, "s", "operation_measurement", "workload"),
        (:alloc, :bytes, "By", "allocation_site", "workload"),
        (:profile_alloc, :bytes, "By", "allocation_profile_record", "workload"),
        (:profile, :samples, "1", "profile_frame", "workload"),
        (:wall_profile, :samples, "1", "profile_frame", "workload"),
        (:network, :operations_per_second, "1/s", "operation_measurement", "workload"),
        (:network_interface, :bytes_received, "By",
            "host_interface_capture", "host_interface"),
        (:network_isolated, :workload_seconds, "s",
            "isolated_worker_group_capture", "isolated_worker_group"))
        candidate = bundle(backend, column; scope)
        row = only(PerfChecker._advice_measurement_summaries(candidate))
        @test row["unit"] == unit && row["collector"] == string(backend)
        @test row["record_semantics"] == semantics && row["scope"] == scope
        @test row["record_count"] == 2 && !haskey(row, "samples")
        @test (row["minimum"], row["median"], row["maximum"]) == (2, 3, 4)
        @test row["correctness"] == "passed" && row["bundle_status"] == "complete"
        @test !occursin("PRIVATE_PATH", string(row))
        advice = Dict("schema_version" => "perfchecker-advice/1",
            "recommendations" => [], "measurement_summaries" => [row])
        @test PerfChecker._advisor_evidence(advice, AdvisorConfig()) == [row]
    end
    # These Int64 observation/transport boundaries must also work on 32-bit Julia.
    max_safe = Int64(9_007_199_254_740_991)
    @test PerfChecker._ADVICE_MAX_SAFE_INTEGER === max_safe
    boundary = bundle(:benchmark, :memory; values = Int64[0, 42, max_safe, max_safe + 1])
    boundary_row = only(PerfChecker._advice_measurement_summaries(boundary))
    @test boundary_row["record_count"] == 3
    @test boundary_row["minimum"] == 0 && boundary_row["median"] == 42 &&
          boundary_row["maximum"] == max_safe
    @test length(boundary.observations) == 4 &&
          boundary.observations[4]["value"] == max_safe + 1
    transported = deepcopy(boundary_row)
    transported["record_count"] = Int32(100)
    transported["minimum"], transported["median"], transported["maximum"] = Int64(0),
    Int64(42), max_safe
    boundary_advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [], "measurement_summaries" => [transported])
    @test PerfChecker._advisor_evidence(boundary_advice, AdvisorConfig()) == [transported]
    for key in ("record_count", "maximum")
        unsafe = deepcopy(transported)
        unsafe[key] = max_safe + 1
        @test_throws ArgumentError PerfChecker._advisor_measurement_row(unsafe)
    end
    for backend in (:benchmark, :chairmark, :profile_alloc, :profile, :wall_profile)
        column = backend in (:profile, :wall_profile) ? :samples :
                 backend == :profile_alloc ? :bytes : :times
        row = only(PerfChecker._advice_measurement_summaries(
            bundle(backend, column; suffix = "/fresh-state-evals1-v1")))
        @test endswith(row["measurement_definition"], "/fresh-state-evals1-v1")
    end
    source = bundle(:benchmark, :memory; values = [42, 42])
    push!(source.observations, deepcopy(first(source.observations)))
    @test only(PerfChecker._advice_measurement_summaries(source))["record_count"] == 2
    source.observations[end]["value"] = 43
    @test_throws ArgumentError PerfChecker._advice_measurement_summaries(source)
    # The same sample index in another saved table is a distinct measurement.
    source.observations[end]["attributes"]["table_index"] = 2
    @test only(PerfChecker._advice_measurement_summaries(source))["record_count"] == 3
    for values in ([NaN, Inf, -Inf], [true, false], [big(2)^60])
        @test isempty(PerfChecker._advice_measurement_summaries(bundle(
            :benchmark, :times; values)))
    end
    for invalid in (
        "/private/source", "C:\\private\\source", "C:private", "a/../b",
        "C:/private/source", "contains spaces", repeat("é", 257))
        candidate = bundle(:benchmark, :times)
        candidate.observations[1]["case_id"] = invalid
        candidate.observations[2]["case_id"] = invalid
        @test isempty(PerfChecker._advice_measurement_summaries(candidate))
    end
    source = bundle(:profile_alloc, :bytes)
    definition = only(source.measurement_definitions)
    definition["id"] = "julia.alloc.bytes/shared-profile-independent-totals/" *
                       repeat("a", 64)
    definition["context"] = Dict("collector" => "profile_alloc", "source" => "PRIVATE_PATH")
    for observation in source.observations
        observation["measurement_definition"] = definition["id"]
        observation["aggregation"] = "independent_operation_total"
        observation["scope"] = "whole_operation"
    end
    row = only(PerfChecker._advice_measurement_summaries(source))
    @test row["record_semantics"] == row["aggregation"] == "independent_operation_total"
    @test row["record_count"] == 2 && !haskey(row, "samples")
    profile = bundle(:profile_alloc, :bytes; values = fill(16, 8))
    zero_total = deepcopy(source.observations[1])
    zero_total["value"] = 0
    mixed = RunBundle(source.manifest,
        vcat(profile.measurement_definitions, source.measurement_definitions),
        vcat(profile.observations, [zero_total]), Dict{String, Any}[], Dict{String, Any}[])
    separate = PerfChecker._advice_measurement_summaries(mixed)
    @test length(separate) == 2
    total_row = only(filter(
        row -> row["aggregation"] == "independent_operation_total", separate))
    profile_row = only(filter(row -> row["aggregation"] == "sample", separate))
    @test total_row["record_count"] == 1 && total_row["median"] == 0
    @test profile_row["record_count"] == 8 && profile_row["median"] == 16
    @test profile_row["record_semantics"] == "allocation_profile_record"
    for (id, canonical) in PerfChecker._ADVICE_MEASUREMENT_DEFINITIONS
        startswith(id, "network.") ||
            canonical.collector in ("network", "network_interface", "network_isolated") ||
            continue
        candidate_definition = PerfChecker._definition_dict(
            id, canonical.unit, Symbol(canonical.collector))
        @test PerfChecker._advice_measurement_definition(candidate_definition) == canonical
        candidate_definition["unit"] = "unknown"
        @test PerfChecker._advice_measurement_definition(candidate_definition) === nothing
    end
    for policy in ("fresh", "reuse"),
        (metric, unit) in (("julia.alloc.bytes", "By"), ("julia.alloc.count", "1"))

        id = "$metric/profile-independent-totals-v1/$policy"
        candidate_definition = PerfChecker._definition_dict(id, unit, :profile_alloc)
        @test PerfChecker._advice_measurement_definition(candidate_definition).unit == unit
        @test PerfChecker._advice_record_semantics(
            id, "profile_alloc", "independent_operation_total") ==
              "independent_operation_total"
        @test PerfChecker._advice_record_semantics(id, "profile_alloc", "sample") ===
              nothing
    end
end

@testitem "Suite context keeps comparisons distinct and qualifies the matching case and target" tags=[
    :unit, :advisor] begin
    using PerfChecker
    definition = PerfChecker._definition_dict(
        "julia.wall.time/benchmarktools-v1", "ns", :benchmark)
    observations = [Dict{String, Any}(
                        "case_id" => "suite/package/$case", "target_id" => target,
                        "measurement_definition" => definition["id"], "metric" => definition["metric"], "unit" => "ns",
                        "value" => value, "scope" => "workload",
                        "aggregation" => "sample", "sample_index" => 1,
                        "comparison_key" => comparison, "attributes" => Dict("table_index" => 1))
                    for (case, target, comparison, value) in (
        ("fast", "dev", "fast-v1", 1), ("fast", "dev", "fast-v2", 2),
        ("slow", "dev", "slow-v1", 100), ("fast", "1.0.0", "fast-v1", 4))]
    qualification(case, target, status) = Dict(
        "case_id" => "suite/package/$case", "target_id" => target,
        "evidence" => Dict("correctness" => Dict("status" => status)))
    manifest = Dict{String, Any}(
        "run_id" => "run", "attempt_id" => "attempt", "state" => "failed",
        "run_qualifications" => [
            qualification("fast", "dev", "passed"), qualification("slow", "dev", "failed"),
            qualification("fast", "1.0.0", "failed")])
    bundle = RunBundle(
        manifest, [definition], observations, Dict{String, Any}[], Dict{String, Any}[])
    rows = PerfChecker._advice_measurement_summaries(bundle)
    @test length(rows) == 4 && all(row -> row["record_count"] == 1, rows)
    @test length(unique(row["id"] for row in rows)) == 4
    fast = filter(
        row -> row["case_id"] == "suite/package/fast" && row["target_id"] == "dev", rows)
    @test all(
        row -> row["correctness"] == "passed" &&
                   row["correctness_scope"] == "case_target" &&
                   row["bundle_status"] == "failed",
        fast)
    @test Set(row["median"] for row in fast) == Set([1, 2])
    @test length(unique(row["comparison_fingerprint"] for row in fast)) == 2
    @test !occursin("fast-v", string(rows))
    @test PerfChecker._advice_measurement_summaries(RunBundle(
        manifest, [definition], reverse(observations),
        Dict{String, Any}[], Dict{String, Any}[])) == rows
    push!(manifest["run_qualifications"], qualification("fast", "dev", "failed"))
    ambiguous = filter(
        row -> row["case_id"] == "suite/package/fast" && row["target_id"] == "dev",
        PerfChecker._advice_measurement_summaries(bundle))
    @test all(
        row -> row["correctness"] == "not_checked" &&
            row["correctness_scope"] == "ambiguous_case_target",
        ambiguous)
    advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [], "measurement_summaries" => ambiguous)
    @test PerfChecker._advisor_evidence(advice, AdvisorConfig()) == ambiguous
    reordered = Dict{String, Any}(reverse(collect(first(ambiguous))))
    @test PerfChecker._advisor_measurement_row(reordered) == first(ambiguous)
    @test PerfChecker._content_digest(Dict("a" => 1, "b" => 2)) ==
          PerfChecker._content_digest(Dict("b" => 2, "a" => 1))
end

@testitem "Real saved BenchmarkTools suite projects memory once per observation" tags=[
    :integration, :advisor] begin
    using PerfChecker, BenchmarkTools, HTTP, Sockets
    mktempdir() do root
        entrypoint = joinpath(root, "workload.jl")
        write(entrypoint,
            "perf_setup() = [3, 1, 2]\nperf_workload(state) = sort!(state)\nperf_oracle(state, result) = result === state && state == [1, 2, 3]\n")
        feature = FeatureSpec(
            :sort; entrypoint, backend = :benchmark, oracle = OracleSpec(),
            options = Dict(
                :samples => 100, :seconds => 1.0, :quiet => true, :repeat => false))
        package = PackageSuite("PerfChecker"; source = pkgdir(PerfChecker),
            worker_environment = dirname(Base.active_project()),
            versions = VersionNumber[], include_dev = true, features = [feature])
        result = run_suite(
            SoftwareSuite(:advisor_measurements, [package]); profile = :quick)
        @test suite_passed(result)
        table = only(only(result.runs).result.tables)
        @test :memory in propertynames(table) && :bytes_or_memory in propertynames(table)
        @test table.memory == table.bytes_or_memory && length(table.times) == 100
        saved = read_run_bundle(only(write_suite_reports(
            result, joinpath(root, "reports"); formats = (:bundle,))))
        rows = PerfChecker._advice_measurement_summaries(saved)
        @test length(rows) == 4
        @test all(
            row -> row["record_count"] == 100 && row["correctness"] == "passed" &&
                       row["correctness_scope"] == "case_target",
            rows)
        memory = only(filter(row -> row["metric"] == "julia.alloc.bytes", rows))
        @test memory["record_count"] == 100 && memory["unit"] == "By"
        @test all(row -> row["case_id"] == "advisor_measurements/PerfChecker/sort", rows)
        # Simulate an old exporter retaining the alias, using its real values
        # and record identity. The projection still counts the source observations once.
        aliases = deepcopy(filter(
            row -> row["metric"] == "julia.alloc.bytes", saved.observations))
        append!(saved.observations, aliases)
        @test only(filter(row -> row["metric"] == "julia.alloc.bytes",
            PerfChecker._advice_measurement_summaries(saved)))["record_count"] == 100
        # Export the same measured result with explicitly chosen, valid long
        # run identifiers. Only export metadata changes, never the measurements.
        long_export = PerfChecker._suite_run_bundle(result;
            run_id = repeat("r", 256), attempt_id = repeat("a", 256))
        budget_bundle = read_run_bundle(write_run_bundle(
            long_export, joinpath(root, "budget-bundle")))
        budget_advice = advise(budget_bundle)
        @test isempty(budget_advice["recommendations"])
        encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
        @test all(row -> row["record_count"] == 100 && length(encode([row])) > 1000,
            budget_advice["measurement_summaries"])
        @test all(
            row -> row["run_id"] == repeat("r", 256) &&
                row["attempt_id"] == repeat("a", 256),
            budget_advice["measurement_summaries"])
        socket = listen(ip"127.0.0.1", 0)
        port = getsockname(socket)[2]
        close(socket)
        checking, inspected = Ref(false), Ref(false)
        server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
            body = PerfChecker._json_parse(String(request.body))
            body["method"] == "notifications/initialized" && return HTTP.Response(202)
            response = if body["method"] == "initialize"
                Dict("protocolVersion" => "2025-11-25",
                    "capabilities" => Dict("tools" => Dict()),
                    "serverInfo" => Dict("name" => "budget-test", "version" => "1"))
            elseif body["method"] == "tools/list"
                Dict("resultType" => "complete",
                    "tools" => [Dict("name" => "advise",
                        "inputSchema" => Dict("type" => "object",
                            "properties" => Dict("prompt" => Dict("type" => "string")),
                            "required" => ["prompt"]))])
            else
                prompt = body["params"]["arguments"]["prompt"]
                if checking[]
                    transmitted = PerfChecker._json_parse(last(split(
                        prompt, "\n\nPerfChecker evidence:\n")))
                    @test isempty(transmitted["evidence"])
                    @test occursin(
                        "no measurement summaries were sent in this request", prompt)
                    @test occursin(
                        "Do not infer that the saved report contains no measurements",
                        prompt)
                    @test !occursin(
                        "this attached report contains no usable measurement summaries",
                        prompt)
                    @test !occursin("no saved measurements were attached", prompt)
                    inspected[] = true # These checks run before the provider reply.
                end
                Dict("resultType" => "complete",
                    "content" => [Dict("type" => "text",
                        "text" => "The request contains no projected measurements.")])
            end
            if body["method"] == "tools/list" && haskey(body["params"], "_meta")
                merge!(response, Dict("ttlMs" => 0, "cacheScope" => "private"))
            end
            HTTP.Response(200, ["Content-Type" => "application/json"],
                encode(Dict("jsonrpc" => "2.0", "id" => body["id"], "result" => response)))
        end
        try
            config = AdvisorConfig(
                protocol = :mcp_http, endpoint = "http://127.0.0.1:$port/mcp",
                mcp_tool = "advise", max_evidence_chars = 1000, timeout = 120)
            Base.invokelatest(advisor_transport, Val(:mcp_http), config,
                Dict("messages" => [Dict("content" => "budget readiness")]))
            checking[] = true
            reply = chat_advice(
                [Dict("role" => "user", "content" => "What can these results establish?")];
                config, advice = budget_advice)
            @test reply["status"] == "complete" && inspected[]
            @test isempty(reply["evidence_ids"]) && reply["evidence_truncated"]
            @test reply["fallback"] == budget_advice
        finally
            close(server)
        end
    end
end

@testitem "Advisor measurement projection has one exact Unicode limit and rejects collisions" tags=[
    :unit, :advisor] begin
    using PerfChecker
    definition = PerfChecker._definition_dict(
        "julia.wall.time/benchmarktools-v1", "ns", :benchmark)
    observations = [Dict{String, Any}(
                        "case_id" => repeat("é", 256), "target_id" => "target$i",
                        "measurement_definition" => definition["id"], "metric" => definition["metric"],
                        "unit" => "ns", "value" => i, "scope" => "workload", "aggregation" => "sample")
                    for i in 1:3]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "run", "attempt_id" => "attempt",
            "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[],
        Dict{String, Any}[])
    rows = PerfChecker._advice_measurement_summaries(bundle)
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    full_length = length(encode(rows))
    @test full_length >= 1000 && ncodeunits(encode(rows)) > full_length
    advice = Dict{String, Any}(
        "schema_version" => "perfchecker-advice/1", "recommendations" => [],
        "measurement_summaries" => rows)
    @test PerfChecker._advisor_evidence(
        advice, AdvisorConfig(max_evidence_chars = full_length)) == rows
    bounded = PerfChecker._advisor_evidence(
        advice, AdvisorConfig(max_evidence_chars = full_length - 1))
    @test length(bounded) == 2 && length(encode(bounded)) <= full_length - 1
    combined = deepcopy(advice)
    combined["recommendations"] = [Dict("id" => "finding", "rule_id" => "rule",
        "hypothesis" => "observed", "action" => "inspect", "validation" => "repeat")]
    @test PerfChecker._advisor_evidence(
        combined, AdvisorConfig(max_evidence_chars = full_length)) == rows
    @test length(PerfChecker._advisor_evidence(combined, AdvisorConfig())) == 4
    private = deepcopy(advice)
    private["measurement_summaries"][1]["source"] = "PRIVATE_PATH"
    @test !occursin(
        "PRIVATE_PATH", encode(PerfChecker._advisor_evidence(private, AdvisorConfig())))
    duplicate = deepcopy(advice)
    push!(duplicate["measurement_summaries"], deepcopy(first(rows)))
    @test PerfChecker._advisor_evidence(duplicate, AdvisorConfig()) == rows
    duplicate["measurement_summaries"][end]["maximum"] = 100
    @test_throws ArgumentError PerfChecker._advisor_evidence(duplicate, AdvisorConfig())
    @test_throws ArgumentError PerfChecker._advisor_evidence(
        duplicate, AdvisorConfig(max_evidence_chars = 1000))
    collision = deepcopy(advice)
    collision["recommendations"] = [Dict("id" => first(rows)["id"], "rule_id" => "rule",
        "hypothesis" => "observed", "action" => "inspect", "validation" => "repeat")]
    @test_throws ArgumentError PerfChecker._advisor_evidence(collision, AdvisorConfig())
    for (key, value) in (("unit", "s"), ("collector", "unknown"),
        ("record_semantics", "independent_operation_total"),
        ("id", "forged"), ("comparison_fingerprint", "bad"), ("bundle_status", "passed"),
        ("correctness_scope", "unknown"), ("record_count", true), ("minimum", big(2)^60))
        malformed = deepcopy(advice)
        malformed["measurement_summaries"][1][key] = value
        @test_throws ArgumentError PerfChecker._advisor_evidence(malformed, AdvisorConfig())
    end
    payload = Dict("cards" => [Dict(
        "evidence_id" => first(rows)["id"], "explanation" => "Recorded duration.")])
    @test PerfChecker._validate_narrative(payload, [row["id"] for row in rows])["experiment_id"] ==
          "stop"
    @test_throws ArgumentError PerfChecker._validate_narrative(payload, ["other"])
end
