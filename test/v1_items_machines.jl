@testitem "Machine transfer refuses misleading calibration" tags=[:unit, :v1] begin
    using PerfChecker
    base = machine_profile(; label = "target")
    @test base["spec_id"] == machine_profile(; label = "different host name")["spec_id"]
    @test only(similar_machines(base, [base]))["distance"] == 0
    context = Dict("suite_revision" => "rev1", "environment" => "deps1",
        "measurement" => "warm median", "unit" => "seconds", "resource_policy" => "one pinned CPU")
    target = Dict("machine" => base, "context" => context,
        "calibration" => Dict("a" => 2.0, "b" => 4.0, "c" => 6.0))
    function donor(label, scale)
        Dict("machine" => merge(base, Dict("label" => label)), "context" => copy(context),
            "calibration" => Dict(
                "a" => 1.0 / scale, "b" => 2.0 / scale, "c" => 3.0 / scale),
            "measurements" => Dict("heldout" => 10.0 / scale))
    end
    donors = [donor("one", 1), donor("two", 2)]
    result = estimate_performance(target, donors, "heldout")
    @test result["status"] == "estimated"
    @test result["estimate"] ≈ 20
    @test !result["ci_gate_eligible"]
    @test result["external_validation"] == "not_performed"
    @test estimate_performance(target, donors[1:1], "heldout")["status"] ==
          "insufficient_evidence"
    @test_throws ArgumentError estimate_performance(
        target, [donors[1], donors[1]], "heldout")
    @test_throws ArgumentError estimate_performance(target, donors, "a")
    bad = deepcopy(donors)
    bad[2]["calibration"]["c"] = 200
    @test estimate_performance(target, bad, "heldout")["status"] == "insufficient_evidence"
    bad = deepcopy(donors)
    bad[2]["context"]["environment"] = "other dependencies"
    @test estimate_performance(target, bad, "heldout")["status"] == "insufficient_evidence"
    badtarget = deepcopy(target)
    badtarget["calibration"]["b"] = NaN
    @test_throws ArgumentError estimate_performance(badtarget, donors, "heldout")
    @test_throws ArgumentError similar_machines(base, [base]; limit = 0)
end
