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
        "os" => lane["os"], "runtime" => lane["julia"] == "1" ? "1.13.0" :
                                         lane["julia"] * ".0",
        "dirty" => false, "environments" => [Dict("label" => "test fixture")],
        "external_revision" => collection["sources"]["vscode"]["revision"])
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
    @test any(l -> l["suite"] == "core" && l["julia"] == "1.10", routine["lanes"])
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
    @test_throws ErrorException validate_receipts(complete, receipts[2:end])
    @test_throws ErrorException validate_receipts(complete, [receipts; receipts[1]])
    for (field, value) in [("status", "skipped"), ("status", "failed"), ("plan_id", "old"),
        ("revision", repeat("b", 40)), ("os", "other"), ("runtime", "2.0.0"),
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
