@testitem "Live callback measurements preserve actual samples lifecycle and qualification" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    prepared, verified, cleaned = Ref(0), Ref(0), Ref(0)
    case = (; prepare = () -> (prepared[] += 1; [3, 1, 2]),
        operation = values -> sort!(values),
        verify = (values, result) -> (verified[] += 1; result === values && values == [1, 2, 3]),
        cleanup = values -> (cleaned[] += 1; nothing))
    bundles = run_scenario(case; id="live_sort", samples=2,
        qualification=(; workload="test sorting"), qualification_limits="test eval context may lack file provenance")
    @test length(bundles) == 1
    bundle = only(bundles)
    raw = bundle.manifest["scenario_evidence"]
    @test raw["status"] == "complete"
    @test raw["correctness"] == "passed"
    @test length(raw["samples"]) == 2
    @test all(sample["time"] > 0 for sample in raw["samples"])
    @test count(row -> row["metric"] == "julia.wall.time", bundle.observations) == 2
    @test prepared[] == verified[] == cleaned[] >= 2
    @test bundle.manifest["live_qualification"]["scope"] == "in-process;not-isolated"
    @test all(occursin("live-inprocess", definition["context"]["measurement"])
        for definition in bundle.measurement_definitions)
    bad = merge(case, (; verify=(values,result)->false))
    failed = only(run_scenario(bad; id="failed_oracle", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "error"
    @test isempty(failed.observations)
    @test prepared[] == cleaned[]
    bad = merge(case, (; operation=values->error("operation failed")))
    failed = only(run_scenario(bad; id="failed_operation", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "error"
    @test prepared[] == cleaned[]
    unavailable = merge(case, (; availability=()->(;available=false, reason="test unavailable")))
    failed = only(run_scenario(unavailable; id="unavailable", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "unavailable"
    @test_throws ArgumentError run_scenario(case; id="bad", samples=0)
    @test_throws ArgumentError run_scenario(case; id="bad", collectors=())
    @test_throws ArgumentError run_scenario(case; id="bad", collectors=(:profile,))
    @test_throws ArgumentError run_scenario((; operation=identity); id="bad")
    # Failure must release the entry-point lock for subsequent independent work.
    @test only(run_scenario(case; id="recovered", samples=1,
        qualification_limits="test eval context")).manifest["scenario_evidence"]["status"] == "complete"
end

@testitem "Live callbacks detect source drift and reject nesting without generated source" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    mktempdir() do directory
        path = joinpath(directory, "declared-input.txt")
        write(path, "before")
        changed = Ref(false)
        cleaned = Ref(0)
        case = (; prepare=()->nothing,
            operation=state->begin
                if !changed[]
                    write(path, "after")
                    changed[] = true
                end
                4
            end,
            verify=(state,result)->result==4,
            cleanup=state->(cleaned[]+=1; nothing))
        bundle = only(run_scenario(case; id="drift", samples=1, source_files=(path,),
            qualification_limits="test callbacks are eval-defined"))
        @test bundle.manifest["scenario_evidence"]["status"] == "invalid"
        @test haskey(bundle.manifest["scenario_evidence"], "source_after")
        @test cleaned[] >= 1
    end
    inner = (;prepare=()->nothing, operation=identity, verify=(s,r)->true)
    outer = (; prepare=()->nothing,
        operation=state->run_scenario(inner; id="inner", samples=1, qualification_limits="test eval context"),
        verify=(s,r)->true)
    bundle = only(run_scenario(outer; id="outer", samples=1, qualification_limits="test eval context"))
    @test bundle.manifest["scenario_evidence"]["status"] == "error"
    @test occursin("nested live scenarios", bundle.manifest["scenario_evidence"]["message"])
end

@testitem "Live profile collectors retain raw evidence under explicit exclusive ownership" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    prepared, cleaned = Ref(0), Ref(0)
    case = (; prepare=()->(prepared[]+=1; Ref(0)),
        operation=state->begin
            values = zeros(Int, 32)
            state[] = sum(values) + 4
            sleep(0.003)
            state[]
        end,
        verify=(state,result)->state[]==result==4,
        cleanup=state->(cleaned[]+=1; nothing))
    bundles = run_scenario(case; id="live_profiles", collectors=(:profile,:profile_alloc),
        samples=2, exclusive_profiles=true, qualification_limits="test eval callback definitions")
    @test length(bundles) == 2
    @test all(b.manifest["scenario_evidence"]["status"]=="complete" for b in bundles)
    @test prepared[] == cleaned[]
    @test haskey(bundles[1].manifest["scenario_evidence"], "cpu_stacks")
    @test haskey(bundles[2].manifest["scenario_evidence"], "allocation_sites")
    @test haskey(bundles[2].manifest["scenario_evidence"], "allocation_profile")
    @test all(b.manifest["live_qualification"]["exclusive_profiles"] for b in bundles)
end
