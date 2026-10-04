@testitem "Oxygen runs the same native test item selection" tags=[:v1, :web] begin
    using PerfChecker, PerfCheckerWeb, TestItemRunner, Oxygen, HTTP
    mktempdir() do root
        write(joinpath(root, "items.jl"), """
        using TestItems
        @testitem "web item" begin
            @test 2 + 2 == 4
        end
        @testitem "functional only" tags=[:test_only] begin
            error("must not run")
        end
        """)
        prefix = "/v1-testitems-check"
        register_testitem_routes!(root; prefix, reports_root = joinpath(root, "results"))
        function request(method, route, body = "", headers = Pair{String, String}[])
            Oxygen.internalrequest(HTTP.Request(method, prefix * route, headers, body))
        end
        page = String(request("GET", "/").body)
        token = match(r"data-token=\"([^\"]+)\"", page).captures[1]
        @test occursin(prefix * "/assets/items.js", page)
        @test request("GET", "/assets/items.js").status == 200
        listing = PerfChecker._json_parse(String(request("GET", "/items").body))
        @test length(listing["items"]) == 1
        body = PerfChecker._canonical_json(Dict("ids" => [only(listing["items"])["id"]]))
        @test request("POST", "/run", body).status == 403
        headers = ["Content-Type" => "application/json", "X-PerfChecker-CSRF" => token]
        @test request("POST", "/run", "{\"ids\":[]}", headers).status == 400
        @test request("POST", "/run", body, headers).status == 202
        state() = PerfChecker._json_parse(String(request("GET", "/state").body))
        @test timedwait(() -> state()["status"] != "running", 120; pollint = 0.1) == :ok
        result = state()
        @test result["status"] == "complete"
        @test result["result"]["passed"]
        @test only(result["result"]["runs"])["item"]["name"] == "web item"
    end
end
