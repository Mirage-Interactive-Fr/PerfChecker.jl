@testitem "Studio notebook API executes discovery measurement and diagnosis" tags=[
    :integration, :vscode_notebook] begin
    using PerfChecker
    mktempdir() do root
        write(joinpath(root, "cases.jl"), """
        make_case(p) = (prepare = () -> [3, 1, 2], operation = sort!,
            verify = (state, result) -> result === state && result == [1, 2, 3])
        """)
        catalog_path = joinpath(root, "scenarios.toml")
        write(catalog_path, """
        schema_version = "perfchecker-scenario-catalog/1"
        root = "."
        [[scenarios]]
        id = "notebook-sort"
        source = "cases.jl"
        factory = "make_case"
        collectors = ["benchmark"]
        """)
        discovery = discover(root)
        @test discovery["schema_version"] == "perfchecker-discovery/1"
        @test investigation_view(discovery) isa InvestigationView
        catalog = load_scenario_catalog(catalog_path)
        target_project = dirname(Base.active_project())
        bundles = run_scenarios(
            catalog; project = target_project, samples = 3, timeout = 90)
        @test bundles isa Vector{RunBundle} && length(bundles) == 1
        @test bundle_passed(only(bundles))
        shown = String[]
        foreach(bundle -> push!(shown, sprint(show, MIME"text/plain"(), bundle)), bundles)
        @test length(shown) == 1 && !isempty(only(shown))
        diagnosis = diagnose(
            catalog; project = target_project, tools = [:jet], timeout = 120)
        @test diagnosis["schema_version"] == "perfchecker-diagnosis/1"
        @test length(diagnosis["records"]) == 1
        # Optional JET can be unavailable; the notebook must still display a faithful result.
        @test only(diagnosis["records"])["status"] in ("complete", "unavailable")
        advice = advise(diagnosis)
        @test advice["schema_version"] == "perfchecker-advice/1"
        @test investigation_view(advice) isa InvestigationView
    end
end
