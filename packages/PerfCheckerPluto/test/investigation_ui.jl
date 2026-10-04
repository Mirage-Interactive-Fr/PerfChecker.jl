@testitem "Investigation views and asynchronous UI contract" tags=[:unit, :shared_scenarios] begin
    using PerfChecker, PerfCheckerPluto
    root = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios")
    catalog = load_scenario_catalog(joinpath(root, "scenarios.toml"))
    first = catalog.scenarios[1]
    selected = select_scenarios(
        catalog, [Dict("id" => first.id, "implementation" => first.implementation)])
    @test length(selected.scenarios) == 1
    @test_throws ArgumentError select_scenarios(
        catalog, [Dict("id" => "inferred", "implementation" => "default")])
    mktempdir() do directory
        job = launch_investigation(:discover; root, reports = directory)
        status = wait_investigation(job)
        @test status["status"] == "complete"
        @test investigation_status(job)["elapsed_seconds"] == status["elapsed_seconds"]
        @test length(status["result"]["declared"]) == 3
        @test isfile(joinpath(directory, "discovery.json"))
        view = investigation_view(status["result"])
        @test occursin("proposed", sprint(show, MIME"text/plain"(), view))
        @test occursin("<article", sprint(show, MIME"text/html"(), view))
        malicious = Dict("schema_version" => "perfchecker-advice/1",
            "recommendations" => [Dict(
                "scenario" => "<script>alert(1)</script>", "implementation" => "cpu", "hypothesis" => "<b>untrusted</b>",
                "action" => "inspect", "validation" => "verify")])
        html = sprint(show, MIME"text/html"(), investigation_view(malicious))
        @test !occursin("<script>", html)
        @test occursin("&lt;script&gt;", html)
        notebook = write_investigation_notebook(
            joinpath(directory, "investigate.jl"); root,
            catalog = joinpath(root, "scenarios.toml"))
        @test occursin("CounterButton", read(notebook, String))
        @test occursin("last_launch", read(notebook, String))
        @test_throws ArgumentError write_investigation_notebook(notebook; root)
    end
    job = launch_investigation(:run; root, catalog = selected, project = root)
    cancel!(job)
    status = wait_investigation(job)
    @test status["status"] == "cancelled"
    @test only(status["result"]["runs"])["qualification"]["correctness"] == "not_checked"
end
