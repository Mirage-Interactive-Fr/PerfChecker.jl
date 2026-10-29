using Test, TOML, PerfCheckerQualification

collection = load_collection(joinpath(@__DIR__, "../collection.toml"))
revision = repeat("a", 40)
function plan(paths; kwargs...)
    qualification_plan(collection, paths; revision, campaign = "unit-test", kwargs...)
end
function receipt(plan, lane)
    Dict{String, Any}(
        "schema" => "perfchecker-qualification-receipt/1", "lane" => lane["id"],
        "plan_id" => plan["id"], "revision" => plan["revision"], "status" => "passed",
        "os" => lane["os"], "runtime" => lane["julia"] * ".0",
        "dirty" => false, "environments" => [Dict("label" => "test fixture")],
        "external_revision" => collection["sources"]["vscode"]["revision"])
end

@testset "SDK Julia 1.13 keeps the complete declared matrix" begin
    # This oracle names the intended suites and OS coverage independently of
    # the planner's loops and routine filter. A version-label migration must
    # not silently discard contracts, adapters or Windows core coverage.
    expected_os = Dict(
        "analyzers" => ["ubuntu-latest", "windows-latest"],
        "advisor_http1" => ["ubuntu-latest", "windows-latest"],
        "advisor_http2" => ["ubuntu-latest", "windows-latest"],
        "contracts" => ["ubuntu-latest", "windows-latest"],
        "core" => ["ubuntu-latest", "windows-latest"],
        "docs" => ["ubuntu-latest"],
        "legacy_interfaces" => ["ubuntu-latest", "windows-latest"],
        "legacy_protocol" => ["ubuntu-latest"],
        "native" => ["ubuntu-latest", "windows-latest"],
        "plots" => ["ubuntu-latest"],
        "pluto" => ["ubuntu-latest", "windows-latest"],
        "shared" => ["ubuntu-latest", "windows-latest"],
        "style" => ["ubuntu-latest"],
        "supposition" => ["ubuntu-latest", "windows-latest"],
        "tachikoma" => ["ubuntu-latest"],
        "vscode" => ["ubuntu-latest", "windows-latest"],
        "web" => ["ubuntu-latest", "windows-latest"])
    expected_full = Set((suite, os, "1.13")
    for (suite, oses) in expected_os for os in oses)
    complete = plan([]; full = true)
    actual = Set((lane["suite"], lane["os"], lane["julia"]) for lane in complete["lanes"])
    @test Set(keys(collection["suites"])) == Set(keys(expected_os))
    @test actual == expected_full
    @test complete["full"]
    @test length(complete["lanes"]) == length(actual) == 29
    @test length(unique(lane["id"] for lane in complete["lanes"])) == 29

    expected_routine = Set((suite, "ubuntu-latest", "1.13")
    for suite in ("analyzers", "contracts", "core", "native", "plots", "pluto", "shared",
        "style", "supposition", "tachikoma", "vscode", "web"))
    push!(expected_routine, ("core", "windows-latest", "1.13"))
    routine = plan([]; full = true, profile = "routine")
    @test Set((lane["suite"], lane["os"], lane["julia"])
    for lane in routine["lanes"]) == expected_routine
    @test length(routine["lanes"]) == 13
    @test length(unique(lane["id"] for lane in routine["lanes"])) == 13
    @test !routine["full"]
end

@testset "Routine checks and independent documentation" begin
    routine = plan([]; full = true, profile = "routine")
    @test !routine["full"]
    @test length(routine["lanes"]) < length(plan([]; full = true)["lanes"])
    @test !any(
        l -> l["suite"] in ("docs", "advisor_http1", "advisor_http2",
            "legacy_interfaces", "legacy_protocol"),
        routine["lanes"])
    @test any(l -> l["suite"] == "core" && l["os"] == "windows-latest", routine["lanes"])
    @test all(l -> l["julia"] == "1.13", routine["lanes"])
    @test only(filter(l -> l["suite"] == "supposition", routine["lanes"]))["os"] ==
          "ubuntu-latest"
    @test Set(l["os"]
    for l in plan([]; full = true)["lanes"]
    if l["suite"] == "supposition") == Set(["ubuntu-latest", "windows-latest"])
    core_project = TOML.parsefile(joinpath(@__DIR__, "../../Project.toml"))
    @test !haskey(core_project["extras"], "Supposition")
    @test "Supposition" ∉ core_project["targets"]["test"]
    @test haskey(core_project["weakdeps"], "Supposition")
    @test "PropCheck" ∈ core_project["targets"]["test"]
    @test_throws ErrorException validate_receipts(
        routine, [receipt(routine, l) for l in routine["lanes"]]; require_full = true)
    docs = plan([]; full = true, profile = "documentation")
    @test !docs["full"]
    @test only(docs["lanes"])["suite"] == "docs"
end

@testset "Impact closure and conservative fallback" begin
    @test impacted_components(collection, ["packages/PerfCheckerWeb/src/studio.jl"]) ==
          ["docs", "web"]
    @test impacted_components(collection, ["website/src/index.md"]) == ["docs"]
    @test impacted_components(
        collection, ["packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl"]) ==
          ["docs", "tachikoma"]
    terminal = plan(["packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl"])
    @test Set((lane["os"], lane["julia"])
    for lane in terminal["lanes"] if lane["suite"] == "tachikoma") ==
          Set([("ubuntu-latest", "1.13")])
    @test collection["components"]["tachikoma"]["depends"] == ["core", "contracts", "plots"]
    @test any(lane -> lane["suite"] == "contracts", terminal["lanes"])
    terminal_routine = plan(["packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl"];
        profile = "routine")
    @test Set((lane["os"], lane["julia"])
    for lane in terminal_routine["lanes"] if lane["suite"] == "tachikoma") ==
          Set([("ubuntu-latest", "1.13")])
    @test impacted_components(collection, ["src/check.jl"]) ==
          sort!(collect(keys(collection["components"])))
    @test plan(["schemas/new.json"])["full"]
    @test plan(["unmapped/new.jl"])["full"]
    @test plan(["Project.toml"])["full"]
    @test plan(["packages/PerfCheckerWeb/src/studio.jl", "src/check.jl"])["full"]
    @test impacted_components(
        collection, ["packages\\PerfCheckerPluto\\src\\PerfCheckerPluto.jl"]) ==
          ["docs", "pluto"]
    @test impacted_components(collection, String[]; changed_components = ["vscode"]) ==
          ["docs", "vscode"]
    @test_throws ErrorException impacted_components(
        collection, []; changed_components = ["typo"])
    @test any(l -> l["suite"] == "contracts", plan(["website/src/index.md"])["lanes"])
    @test !any(l -> l["suite"] == "analyzers",
        plan(["packages/PerfCheckerWeb/src/studio.jl"])["lanes"])
    @test plan(["src/check.jl"])["id"] == plan(["schemas/new.json"])["id"]
    changed = deepcopy(collection)
    changed["sources"]["vscode"]["revision"] = repeat("b", 40)
    @test qualification_plan(changed, []; revision, full = true)["id"] !=
          plan([]; full = true)["id"]
    @test qualification_plan(collection, []; revision, full = true)["id"] !=
          qualification_plan(collection, []; revision, full = true)["id"]
end

@testset "Publication requires complete exact evidence" begin
    complete = plan([]; full = true)
    receipts = [receipt(complete, l) for l in complete["lanes"]]
    @test validate_receipts(complete, receipts; require_full = true)["publishable"]
    patch_receipts = deepcopy(receipts)
    patch_receipts[1]["runtime"] = "1.13.1"
    @test validate_receipts(complete, patch_receipts; require_full = true)["publishable"]
    @test_throws ErrorException validate_receipts(complete, receipts[2:end])
    @test_throws ErrorException validate_receipts(complete, [receipts; receipts[1]])
    for (field, value) in [("status", "skipped"), ("status", "failed"), ("plan_id", "old"),
        ("revision", repeat("b", 40)), ("os", "other"), ("runtime", "2.0.0"),
        ("runtime", "1.12.7"), ("runtime", "1.14.0"), ("runtime", "1.13.0-DEV.1"),
        ("lane", "unknown"), ("schema", "old")]
        invalid = deepcopy(receipts)
        invalid[1][field] = value
        @test_throws ErrorException validate_receipts(complete, invalid)
    end
    invalid = deepcopy(receipts)
    invalid[1]["dirty"] = true
    @test !validate_receipts(complete, invalid)["publishable"]
    @test_throws ErrorException validate_receipts(complete, invalid; require_full = true)
    invalid = deepcopy(receipts)
    invalid[1]["environments"] = []
    @test_throws ErrorException validate_receipts(complete, invalid)
    invalid = deepcopy(receipts)
    only(filter(r -> startswith(r["lane"], "vscode-ubuntu"), invalid))["external_revision"] = repeat(
        "b", 40)
    @test_throws ErrorException validate_receipts(complete, invalid)
    partial = plan(["website/src/index.md"])
    partial_receipts = [receipt(partial, l) for l in partial["lanes"]]
    @test !validate_receipts(partial, partial_receipts)["publishable"]
    @test_throws ErrorException validate_receipts(
        partial, partial_receipts; require_full = true)
    @test_throws ErrorException validate_receipts(plan([]), [])
    unsupported_plan = deepcopy(complete)
    unsupported_plan["lanes"][1]["julia"] = "1"
    @test_throws ErrorException validate_receipts(unsupported_plan, receipts)
end

@testset "Configuration and artifact integrity" begin
    mktempdir() do directory
        path = joinpath(directory, "collection.toml")
        cyclic = deepcopy(collection)
        cyclic["components"]["core"]["depends"] = ["web"]
        write_toml(path, cyclic)
        @test_throws ErrorException load_collection(path)
        moving = deepcopy(collection)
        moving["sources"]["vscode"]["revision"] = "main"
        write_toml(path, moving)
        @test_throws ErrorException load_collection(path)
        for selectors in (["1.10"], ["1.12"], ["1"], ["release"], ["rc"], ["nightly"],
            ["1.13", "nightly"], ["1.13", "1.13"], String[])
            unsupported = deepcopy(collection)
            unsupported["suites"]["core"]["julias"] = selectors
            write_toml(path, unsupported)
            @test_throws ErrorException load_collection(path)
            @test_throws ErrorException qualification_plan(
                unsupported, []; revision, full = true)
            @test_throws ErrorException qualification_plan(unsupported, []; revision,
                full = true, profile = "routine")
        end
        write_toml(path, collection)
        @test load_collection(path) == collection
        before = tree_digest(directory)
        write(joinpath(directory, "extra.txt"), "changed")
        @test tree_digest(directory) != before
        @test file_digest(path) == file_digest(path)
    end
    @test json(Dict("b" => [true, "\n\"\\"], "a" => 1)) ==
          "{\"a\":1,\"b\":[true,\"\\u000a\\\"\\\\\"]}"
end
