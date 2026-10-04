using Test, PerfChecker

project = dirname(Base.active_project())
example = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios")
output = get(ENV, "PERFCHECKER_SHARED_REPORTS", mktempdir())

@testset "Injected defects and healthy analyzer controls" begin
    mktempdir() do directory
        source = joinpath(directory, "cases.jl")
        write(source,
            """
dynamic(p) = (prepare=()->Any[identity, 42], operation=x->x[1](x[2]), verify=(x,r)->r==42)
allocating(p) = (prepare=()->[1,2,3], operation=copy, verify=(x,r)->r==x && r!==x)
healthy(p) = (prepare=()->42, operation=identity, verify=(x,r)->r==42)
incorrect(p) = (prepare=()->42, operation=identity, verify=(x,r)->false)
""")
        specs = [ScenarioSpec(name; source, factory = name)
                 for name in ("dynamic", "allocating", "healthy", "incorrect")]
        catalog = ScenarioCatalog(example, specs)
        diagnosis = diagnose(catalog; project, tools = [:jet, :alloccheck], timeout = 300)
        @test all(record -> record["controller_loaded"] === false, diagnosis["records"])
        write_investigation_report(
            diagnosis, joinpath(output, "injected-diagnosis"); force = true)
        function record(name, tool)
            only(filter(
                r -> r["scenario"] == name && r["tool"] == tool, diagnosis["records"]))
        end
        @test record("dynamic", "jet")["status"] == "complete"
        @test any(f -> f["rule_id"] == "inference.runtime_dispatch",
            record("dynamic", "jet")["findings"])
        @test record("allocating", "alloccheck")["status"] == "complete"
        @test any(f -> f["rule_id"] == "allocation.potential",
            record("allocating", "alloccheck")["findings"])
        for tool in ("jet", "alloccheck")
            @test record("healthy", tool)["status"] == "complete"
            @test isempty(record("healthy", tool)["findings"])
            @test record("incorrect", tool)["status"] == "invalid"
            @test record("incorrect", tool)["correctness"] == "failed"
        end
        healthy = Dict("schema_version" => "perfchecker-diagnosis/1",
            "records" => [record("healthy", "jet"), record("healthy", "alloccheck")])
        @test isempty(advise(healthy)["recommendations"])
        @test all(r -> r["predicted_gain"] == "not_measured",
            advise(diagnosis)["recommendations"])
    end
end
