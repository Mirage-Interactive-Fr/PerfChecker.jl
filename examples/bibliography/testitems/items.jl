# Reuse the pinned upstream tests and workload; do not copy their implementations.
@testitem "Bibliography format API" tags=[:shared] begin
    using Bibliography, BibInternal
    include(joinpath(pkgdir(Bibliography), "test", "api.jl"))
end

@testitem "Bibliography export workload" tags=[:perf_only] begin
    using Bibliography
    include(joinpath(pkgdir(Bibliography), "perf", "features", "export_bibtex.jl"))
    state = Base.invokelatest(perf_setup)
    exported = Base.invokelatest(perf_workload, state)
    @test occursin("lovelace2026", exported)
    @test occursin("A reusable performance contract", exported)
end
