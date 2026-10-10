@testitem "Studio agents stop on interruption and preserve cleanup failures" tags=[
    :v1, :web, :agent_cleanup] begin
    using PerfChecker, PerfCheckerWeb, Oxygen, HTTP, Sockets
    import Pkg

    function fixture_suite(root)
        source = mkpath(joinpath(root, "AgentAllocationFixture"))
        environment = mkpath(joinpath(root, "environment"))
        write(joinpath(source, "Project.toml"), """
name = "AgentAllocationFixture"
uuid = "56241662-3cf8-4205-a54c-1d03b0367942"
version = "0.1.0"
""")
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        entrypoint = joinpath(source, "feature.jl")
        write(entrypoint, "perf_workload(_) = nothing\n")
        package = PackageSuite("AgentAllocationFixture"; source,
            worker_environment = environment, versions = VersionNumber[],
            features = [FeatureSpec(:allocation; backend = :alloc, entrypoint,
                options = Dict(:quiet => true, :repeat => false, :threads => 1))])
        return SoftwareSuite(:agent_cleanup, [package]), source, entrypoint
    end

    # Only the transport is a fixture: the agent still validates its real plan,
    # invokes run_suite and performs actual HTTP requests. Count any new claim
    # after a fatal exit, rather than relying on a particular polling interval.
    function with_agent_server(f, suite; stale_first = false, failure_gate = nothing)
        Oxygen.resetstate()
        prefix = "/test/agent-cleanup"
        api = Oxygen.router(prefix)
        plan = suite_plan_dict(plan_suite(suite; profile = :quick))
        calls = Dict("claim" => 0, "heartbeat" => 0, "complete" => 0, "fail" => 0)
        Oxygen.post(api("/agents/claim")) do _
            calls["claim"] += 1
            count = calls["claim"]
            count > (stale_first ? 2 : 1) && return HTTP.Response(204)
            selected = deepcopy(plan)
            stale_first && count == 1 && (selected["plan_revision"] = "stale")
            Oxygen.json(Dict("job_id" => "fixture-$count", "lease_token" => "lease",
                "plan" => selected, "overrides" => Dict()))
        end
        for action in ("heartbeat", "complete", "fail")
            Oxygen.post(api("/agents/$action")) do _
                calls[action] += 1
                action == "fail" && failure_gate !== nothing && take!(failure_gate)
                Oxygen.json(Dict("accepted" => true))
            end
        end
        listener = Sockets.listen(ip"127.0.0.1", 0)
        port = Int(last(Sockets.getsockname(listener)))
        close(listener)
        Oxygen.serve(; host = "127.0.0.1", port, async = true,
            show_banner = false, access_log = nothing)
        try
            f("http://127.0.0.1:$port$prefix", calls)
        finally
            if failure_gate !== nothing && !isready(failure_gate)
                put!(failure_gate, nothing)
            end
            Oxygen.terminate()
            Oxygen.resetstate()
        end
    end

    function worker_alive(pid)
        if Sys.iswindows()
            output = read(ignorestatus(`tasklist /FI $("PID eq $pid") /FO CSV /NH`), String)
            return occursin(",\"$pid\",", output)
        end
        state = strip(read(ignorestatus(`ps -p $pid -o stat=`), String))
        return !isempty(state) && !startswith(state, "Z")
    end

    # Fail a real filesystem cleanup without leaving a live process or changing
    # permissions. The test owns this nonempty directory and removes it finally.
    function fail_cleanup(inventory)
        try
            rm(inventory)
        catch error
            throw(PerfChecker.CheckCleanupFailure(Any[error], [inventory]))
        end
        error("fixture cleanup unexpectedly removed a nonempty directory")
    end

    @testset "once=false stops after a real Malt allocation check is interrupted" begin
        mktempdir() do root
            suite, source, entrypoint = fixture_suite(root)
            mkpath(joinpath(source, "src"))
            operation = joinpath(source, "src", "operation.jl")
            write(operation, "allocate() = copy(fill(1, 32))\n")
            write(joinpath(source, "src", "AgentAllocationFixture.jl"), """
__precompile__(false)
module AgentAllocationFixture
include("operation.jl")
end
""")
            foreign = operation * ".987654321.mem"
            unrelated = joinpath(source, "src", "notes.mem")
            write(foreign, "foreign allocation trace\r\n")
            write(unrelated, "user notes\n")
            marker = joinpath(root, "measuring")
            write(entrypoint, """
using AgentAllocationFixture
function perf_workload(_)
    AgentAllocationFixture.allocate()
    write($(repr(marker)), string(getpid()))
    sleep(120)
end
""")
            with_agent_server(suite) do base, calls
                captured = Ref{Any}(nothing)
                task = @async try
                    run_studio_agent(suite; server = base, token = "fixture",
                        agent_id = "fixture", once = false, poll_seconds = 0.01,
                        heartbeat_seconds = 0.05)
                catch error
                    captured[] = error
                end
                interrupted = false
                try
                    # A cold worker can resolve/compile before its workload
                    # starts. This is readiness, not a product timeout budget.
                    @test timedwait(() -> isfile(marker) || istaskdone(task), 180) == :ok
                    @test isfile(marker)
                    pid = parse(Int, read(marker, String))
                    @test worker_alive(pid)
                    schedule(task, InterruptException(); error = true)
                    interrupted = true
                    @test timedwait(() -> istaskdone(task), 45) == :ok
                    @test captured[] isa InterruptException
                    @test calls["claim"] == 1
                    @test calls["complete"] == 0
                    @test calls["fail"] == 0
                    @test !worker_alive(pid)
                    @test sort(PerfChecker.find_malloc_files([source])) ==
                          sort([foreign, unrelated])
                    @test read(foreign, String) == "foreign allocation trace\r\n"
                    @test read(unrelated, String) == "user notes\n"
                finally
                    # Never interrupt an in-progress cleanup twice. On the old
                    # bug, a second claim proves cleanup has already unwound
                    # and the agent is polling again; stop that idle poll only.
                    if !istaskdone(task) && (!interrupted || calls["claim"] > 1)
                        schedule(task, InterruptException(); error = true)
                    end
                    wait(task)
                end
            end
        end
    end

    @testset "incomplete cleanup is fatal without a leaked worker" begin
        mktempdir() do root
            suite, _, _ = fixture_suite(root)
            inventory = mkpath(joinpath(root, "retained-inventory"))
            retained = joinpath(inventory, "journal")
            write(retained, "owned cleanup inventory\n")
            executor = (_...) -> fail_cleanup(inventory)
            try
                with_agent_server(suite) do base, calls
                    captured = Ref{Any}(nothing)
                    task = @async try
                        run_studio_agent(suite; server = base, token = "fixture",
                            agent_id = "fixture", executor, once = false,
                            poll_seconds = 0.01, heartbeat_seconds = 0.05)
                    catch error
                        captured[] = error
                    end
                    try
                        @test timedwait(() -> istaskdone(task), 15) == :ok
                        @test captured[] isa PerfChecker.CheckCleanupFailure
                        @test captured[].directories == [inventory]
                        @test occursin(inventory, sprint(showerror, captured[]))
                        @test read(retained, String) == "owned cleanup inventory\n"
                        @test calls["claim"] == 1
                        @test calls["complete"] == 0
                        @test calls["fail"] == 0
                    finally
                        istaskdone(task) ||
                            schedule(task, InterruptException(); error = true)
                        wait(task)
                    end
                end
            finally
                rm(inventory; recursive = true, force = true)
            end
            @test !ispath(inventory)
        end
    end

    @testset "ordinary lease failure still permits the next job" begin
        mktempdir() do root
            suite, _, _ = fixture_suite(root)
            executed = Ref(0)
            executor = function (_...)
                executed[] += 1
                PerfChecker.CheckerResult(
                    [PerfChecker.Table(filename = ["fixture.jl"], bytes = [8])],
                    nothing, [:alloc], [Pkg.PackageSpec(name = "AgentAllocationFixture")])
            end
            with_agent_server(suite; stale_first = true) do base, calls
                @test run_studio_agent(suite; server = base, token = "fixture",
                    agent_id = "fixture", executor, once = false, max_jobs = 2,
                    heartbeat_seconds = 0.05) == 2
                @test calls["claim"] == 2
                @test calls["fail"] == 1
                @test calls["complete"] == 1
                @test executed[] == 1
            end
        end
    end

    @testset "interruption while reporting an ordinary failure stops the agent" begin
        mktempdir() do root
            suite, _, _ = fixture_suite(root)
            gate = Channel{Nothing}(1)
            executed = Ref(false)
            executor = function (_...)
                executed[] = true
                error("a second lease must never execute after interruption")
            end
            with_agent_server(suite; stale_first = true, failure_gate = gate) do base, calls
                captured = Ref{Any}(nothing)
                task = @async try
                    run_studio_agent(suite; server = base, token = "fixture",
                        agent_id = "fixture", executor, once = false, max_jobs = 2,
                        poll_seconds = 0.01, heartbeat_seconds = 0.05)
                catch error
                    captured[] = error
                end
                try
                    # The server has accepted POST/fail but has not answered.
                    # Interrupt the real Downloads request, not its executor.
                    @test timedwait(() -> calls["fail"] == 1 || istaskdone(task), 15) == :ok
                    @test calls["fail"] == 1
                    @test !istaskdone(task)
                    schedule(task, InterruptException(); error = true)
                    @test timedwait(() -> istaskdone(task), 15) == :ok
                    @test captured[] isa InterruptException
                    @test calls["claim"] == 1
                    @test calls["complete"] == 0
                    @test !executed[]
                finally
                    isready(gate) || put!(gate, nothing)
                    istaskdone(task) || schedule(task, InterruptException(); error = true)
                    wait(task)
                end
            end
        end
    end

    @testset "local cancellation cannot hide the cleanup error and inventory" begin
        mktempdir() do root
            Oxygen.resetstate()
            suite, _, _ = fixture_suite(root)
            inventory = mkpath(joinpath(root, "retained-inventory"))
            retained = joinpath(inventory, "journal")
            write(retained, "owned cleanup inventory\n")
            started = Ref(false)
            executor = function (_...)
                started[] = true
                try
                    sleep(120)
                finally
                    fail_cleanup(inventory)
                end
            end
            prefix = "/test/local-cleanup"
            register_oxygen_routes!(suite; prefix, executor,
                reports_root = joinpath(root, "reports"))
            decode(response) = PerfChecker._json_parse(String(response.body))
            function request(method, path, payload = nothing)
                Oxygen.internalrequest(
                    HTTP.Request(
                    method, prefix * path, ["Content-Type" => "application/json"],
                    payload === nothing ? "" : PerfChecker._canonical_json(payload)))
            end
            plan = decode(request("GET", "/suite-plan"))
            launched = decode(request("POST",
                "/jobs",
                Dict(
                    "profile" => "quick", "plan_revision" => plan["plan_revision"],
                    "selected_run_ids" => [only(plan["runs"])["id"]])))
            id = launched["job_id"]
            state() = decode(request("GET", "/jobs?id=$id"))
            try
                @test timedwait(() -> started[], 15) == :ok
                @test decode(request("POST", "/jobs/cancel", Dict("job_id" => id)))["cancelled"]
                @test timedwait(() -> state()["worker_state"] == "failed", 15) == :ok
                @test timedwait(() -> state()["state"] == "failed", 15) == :ok
                final = state()
                @test final["worker_state"] == "failed"
                @test occursin("PerfChecker cleanup incomplete", final["message"])
                @test occursin(inventory, final["message"])
                @test !final["reports_ready"]
                @test read(retained, String) == "owned cleanup inventory\n"
            finally
                # Wait for the controller's finalizer before deleting its owned
                # fixture files, including when an assertion fails.
                request("POST", "/jobs/cancel", Dict("job_id" => id))
                @test timedwait(
                    () -> state()["worker_state"] in ("failed", "cancelled"), 45) == :ok
                rm(inventory; recursive = true, force = true)
                Oxygen.resetstate()
            end
        end
    end
end
