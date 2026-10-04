@testitem "Public API has local documentation" tags=[:unit, :documentation] begin
    using PerfChecker
    metadata = Base.Docs.meta(PerfChecker)
    exported = filter(!=(:PerfChecker), names(PerfChecker))
    undefined = filter(name -> !isdefined(PerfChecker, name), exported)
    undocumented = filter(
        name -> !haskey(metadata, Base.Docs.Binding(PerfChecker, name)), exported)
    @test isempty(undefined)
    @test isempty(undocumented)
end
