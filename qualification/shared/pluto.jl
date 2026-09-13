using Test, PerfChecker, PerfCheckerPluto, Pluto

@testset "Pluto package integration" begin
    @test parentmodule(PerfCheckerPluto) === PerfCheckerPluto
    mktempdir() do directory
        notebook = prepare_pluto_dashboard(joinpath(directory, "dashboard.jl"))
        @test isfile(notebook)
        @test occursin("Pluto.jl notebook", read(notebook, String))
    end
end
