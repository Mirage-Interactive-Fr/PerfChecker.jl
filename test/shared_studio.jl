using Test, PerfChecker, PerfCheckerWeb, Oxygen, HTTP, Sockets

root = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios")
project = dirname(Base.active_project())
catalog = load_scenario_catalog(joinpath(root, "scenarios.toml"))
reports = get(ENV, "PERFCHECKER_SHARED_REPORTS", mktempdir())
prefix = "/test/scenarios"
register_oxygen_routes!(catalog; prefix, project, reports_root = reports)
get_response(route) = Oxygen.internalrequest(HTTP.Request("GET", prefix * route))
decode_response(response) = PerfChecker._json_parse(String(response.body))
page = get_response("/")
token = match(r"data-token=\"([^\"]+)\"", String(page.body)).captures[1]
function post_response(route, body; authenticated = true)
    Oxygen.internalrequest(HTTP.Request("POST", prefix * route,
        authenticated ?
        ["Content-Type" => "application/json", "X-PerfChecker-CSRF" => token] :
        ["Content-Type" => "application/json"],
        sprint(io -> PerfChecker.JSON.print(io, body))))
end
function completed(id; timeout = 180)
    started = time()
    while time() - started < timeout
        status = decode_response(get_response("/job?id=" * id))
        status["status"] != "running" && return status
        sleep(0.05)
    end
    error("studio job exceeded test deadline")
end

@testset "Shared scenario web studio" begin
    @test page.status == 200
    @test length(decode_response(get_response("/catalog"))["scenarios"]) == 3
    @test get_response("/assets/investigations.js").status == 200
    @test decode_response(get_response("/catalog"))["advisor"] == "disabled"
    @test post_response("/launch", Dict("action" => "narrate")).status == 400
    for action in ("tools", "sync")
        launched = decode_response(post_response("/launch", Dict("action" => action)))
        @test completed(launched["id"])["status"] == "complete"
        @test get_response("/evidence?id=" * launched["id"] * "&format=markdown").status ==
              200
    end
    @test post_response(
        "/launch", Dict("action" => "discover"); authenticated = false).status == 403
    @test post_response("/launch", Dict("action" => "run", "selection" => [])).status == 400
    discovery = decode_response(post_response("/launch", Dict("action" => "discover")))
    @test completed(discovery["id"])["status"] == "complete"
    @test get_response("/evidence?id=" * discovery["id"]).status == 200
    scenario = catalog.scenarios[1]
    selection = [Dict("id" => scenario.id, "implementation" => scenario.implementation)]
    payload = Dict(
        "action" => "run", "selection" => selection, "samples" => 2, "timeout" => 120)
    launched = post_response("/launch", payload)
    @test launched.status == 202
    @test post_response("/launch", payload).status == 409
    measured = completed(decode_response(launched)["id"])
    @test measured["status"] == "complete"
    @test all(
        r -> r["qualification"]["correctness"] == "passed", measured["result"]["runs"])
    @test !isempty(first(measured["result"]["runs"])["summaries"])
    @test get_response("/evidence?id=" * measured["id"] * "&format=markdown").status == 200
    @test occursin("median", String(get_response("/evidence?id=" * measured["id"]).body))
    advised = post_response("/advise", Dict("id" => measured["id"]))
    @test advised.status == 200
    @test decode_response(advised)["schema_version"] == "perfchecker-advice/1"
    @test get_response("/evidence?id=" * measured["id"] * "&advice=true").status == 200
    @test post_response("/compare",
        Dict("baseline" => measured["id"], "candidate" => measured["id"])).status == 200
    payload["action"] = "diagnose"
    payload["tools"] = ["latency"]
    launched = decode_response(post_response("/launch", payload))
    @test post_response("/cancel", Dict("id" => launched["id"])).status == 200
    @test completed(launched["id"])["status"] == "cancelled"
    @test get_response("/evidence?id=../outside").status == 400
    payload["tools"] = ["memory", "heap"]
    diagnosed = completed(decode_response(post_response("/launch", payload))["id"])
    @test all(r["status"] == "complete" for r in diagnosed["result"]["records"])
    @test occursin(
        "reachable state", String(get_response("/evidence?id=" * diagnosed["id"]).body))
    artifact_url = "/artifact?id=" * diagnosed["id"] * "&index=1"
    artifact = only(last(diagnosed["result"]["records"])["artifacts"])
    listener = Sockets.listen(ip"127.0.0.1", 0)
    port = Int(last(Sockets.getsockname(listener)))
    close(listener)
    Oxygen.serve(;
        host = "127.0.0.1", port, async = true, show_banner = false, access_log = nothing)
    try
        url = "http://127.0.0.1:$port$prefix"
        downloaded = joinpath(reports, "downloaded.heapsnapshot")
        response = open(downloaded, "w") do output
            HTTP.get(url * artifact_url; response_stream = output, status_exception = false)
        end
        @test response.status == 200
        @test bytes2hex(open(PerfChecker.SHA.sha256, downloaded)) == artifact["sha256"]
        @test HTTP.get(url * "/artifact?id=" * diagnosed["id"] * "&index=0";
            status_exception = false).status == 400
        open(io -> write(io, "modified"), artifact["path"], "a")
        @test HTTP.get(url * artifact_url; status_exception = false).status == 400
    finally
        Oxygen.terminate()
    end
    @test_throws ArgumentError serve_suite(catalog; host = "0.0.0.0")
end

if get(ENV, "PERFCHECKER_UI_PREVIEW", "false") == "true"
    Oxygen.serve(; host = "127.0.0.1", port = 8098, async = true)
    write(joinpath(pkgdir(PerfChecker), ".lab", "ui-server.pid"), string(getpid()))
    wait(Condition())
end
