using Test, PerfChecker, JET, AllocCheck, SnoopCompile

include("shared_analyzers.jl")

@testset "SnoopCompile lifecycle and correctness" begin
    @test isfile(joinpath(pkgdir(PerfChecker), "providers", "SnoopCompile", "adapter.jl"))
    mktempdir() do directory
        source = joinpath(directory, "cases.jl")
        write(source, """
        healthy(p) = (prepare=()->[1,2,3], operation=sum, verify=(x,r)->r==6)
        incorrect(p) = (prepare=()->[1,2,3], operation=sum, verify=(x,r)->false)
        """)
        catalog = ScenarioCatalog(directory,
            [ScenarioSpec(name; source, factory = name)
             for name in ("healthy", "incorrect")])
        result = diagnose(catalog; project = dirname(Base.active_project()),
            tools = [:snoopcompile], timeout = 180)
        healthy = only(filter(r -> r["scenario"] == "healthy", result["records"]))
        incorrect = only(filter(r -> r["scenario"] == "incorrect", result["records"]))
        @test healthy["status"] == "complete"
        @test healthy["correctness"] == "passed"
        @test healthy["controller_loaded"] === false
        @test healthy["measurements"]["inference_seconds"] >= 0
        @test incorrect["status"] == "invalid"
        @test incorrect["correctness"] == "failed"
    end
end
