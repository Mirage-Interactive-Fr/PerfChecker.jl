using Test, PerfChecker, PerfCheckerWeb, Oxygen, HTTP

root = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios")
catalog = load_scenario_catalog(joinpath(root, "scenarios.toml"))
store = mktempdir()
prefix = "/setup-ui"
register_oxygen_routes!(
    catalog; prefix, reports_root = store, project = dirname(Base.active_project()))
getpage(route) = Oxygen.internalrequest(HTTP.Request("GET", prefix * route))
token = match(r"data-token=\"([^\"]+)\"", String(getpage("/").body)).captures[1]
function postsetup(input; authenticated = true)
    headers = ["Content-Type" => "application/json"]
    authenticated && push!(headers, "X-PerfChecker-CSRF" => token)
    Oxygen.internalrequest(HTTP.Request("POST", prefix * "/advisor-action", headers,
        sprint(io -> PerfChecker.JSON.print(io, input))))
end
@testset "Advisor setup studio UI" begin
    @test getpage("/advisor").status == 200
    for file in ("advisor-panel.js", "advisor-panel.css", "advisor-web.js")
        @test getpage("/assets/" * file).status == 200
    end
    @test getpage("/advisor-settings").status == 403
    @test postsetup(
        Dict("action" => "save", "config" => nothing); authenticated = false).status == 403
    config = Dict("protocol" => "mcp_http", "endpoint" => "http://127.0.0.1:8083/mcp",
        "mcp_tool" => "ask", "instructions" => "Préserver l’API")
    @test postsetup(Dict("action" => "save", "config" => config)).status == 200
    saved = PerfChecker._json_parsefile(joinpath(store, "advisor-settings.json"))
    @test saved["enabled"]
    @test saved["config"]["instructions"] == "Préserver l’API"
    @test !saved["investigates"]
    @test postsetup(Dict(
        "action" => "save", "config" => config, "investigates" => true)).status == 400
    @test postsetup(Dict("action" => "save",
        "config" => merge(config, Dict("endpoint" => "http://example.com/mcp")))).status ==
          400
    @test postsetup(Dict("action" => "save", "config" => nothing)).status == 200
    @test !PerfChecker._json_parsefile(joinpath(store, "advisor-settings.json"))["enabled"]
end
