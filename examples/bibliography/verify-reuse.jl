using Test, PerfChecker, Serialization

# Run in .controller/items, which contains the three pinned target packages.
# Validate the reuse assumption independently of stochastic profiler samples.
suite = load_software_suite(joinpath(@__DIR__, "suite.jl"))
plan = filter_suite_plan(plan_suite(suite; profile = :quick); backends = :profile)
snapshot(value) = (io = IOBuffer(); serialize(io, value); take!(io))
@testset "Bibliography profile inputs remain unchanged" begin
    @test length(plan.runs) == 7
    for run in plan.runs
        owner = Module(gensym(:BibliographyWorkload))
        Base.include(owner, run.variant.entrypoint)
        state = Base.invokelatest(() -> getfield(owner, :perf_setup)())
        before = snapshot(state)
        file_before = state isa AbstractString && isfile(state) ? read(state) : nothing
        for _ in 1:2
            Base.invokelatest(() -> getfield(owner, :perf_workload)(state))
            @test snapshot(state) == before
            file_before === nothing || @test read(state) == file_before
        end
    end
end
