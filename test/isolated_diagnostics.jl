@testitem "Diagnostic workers do not depend on the controller package" tags=[
    :unit, :memory_diagnostics, :worker_environment] begin
    using PerfChecker, Profile, SHA
    mktempdir() do directory
        write(joinpath(directory, "Project.toml"), "[deps]\n")
        source = joinpath(directory, "case.jl")
        write(source, "healthy(p)=(prepare=()->[1,2,3],operation=sum,verify=(s,r)->r==6)\n")
        catalog = ScenarioCatalog(
            directory, [ScenarioSpec("healthy"; source, factory = "healthy")])
        ambient = joinpath(directory, "ambient")
        mkpath(joinpath(ambient, "JET", "src"))
        write(joinpath(ambient, "JET", "src", "JET.jl"), "module JET\nend\n")
        load_path = join(("@", ambient, "@stdlib"), Sys.iswindows() ? ';' : ':')
        result = withenv("JULIA_LOAD_PATH" => load_path) do
            diagnose(catalog; project = directory,
                tools = [:latency, :gc, :memory, :heap, :jet], timeout = 120,
                reports = joinpath(directory, "reports"))
        end
        for record in result["records"]
            @test record["controller_loaded"] === false
            if record["tool"] == "jet"
                @test record["status"] == "unavailable"
                @test record["correctness"] == "not_checked"
                @test occursin("absent from the diagnostic environment", record["message"])
            elseif record["tool"] == "heap" &&
                   !(isdefined(Profile, :take_heap_snapshot) &&
                     hasmethod(Profile.take_heap_snapshot, Tuple{String}, (:redact_data,)))
                @test record["status"] == "unavailable"
            else
                @test record["status"] == "complete"
                @test record["correctness"] == "passed"
                if record["tool"] == "heap"
                    artifact = only(record["artifacts"])
                    @test artifact["redacted"] === true
                    @test artifact["sha256"] ==
                          bytes2hex(open(SHA.sha256, artifact["path"]))
                end
            end
        end
    end
end
