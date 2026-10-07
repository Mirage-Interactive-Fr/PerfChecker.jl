@testitem "Property corpora and backend architecture" tags=[:unit, :corpus] begin
    using PerfChecker, PropCheck

    @test Base.get_extension(PerfChecker, :SuppositionExt) === nothing
    error = try
        freeze_supposition_corpus("unused.json", nothing)
        nothing
    catch exception
        exception
    end
    @test error isa ArgumentError
    @test occursin("64-bit Julia", sprint(showerror, error))
    @test occursin(Sys.WORD_SIZE == 32 ? "freeze_propcheck_corpus" : "Load Supposition",
        sprint(showerror, error))

    mktempdir() do dir
        path = joinpath(dir, "corpus.json")
        first = freeze_propcheck_corpus(path, PropCheck.itype(Int8); count = 4, seed = 7)
        corpus = read_property_corpus(first)
        @test corpus["producer"] == "PropCheck.jl"
        @test corpus["count"] == 4
        @test corpus["metadata"]["seed"] == 7
        @test all(x -> typemin(Int8) <= x <= typemax(Int8), corpus["cases"])
        second = freeze_propcheck_corpus(joinpath(dir, "repeated.json"),
            PropCheck.itype(Int8); count = 4, seed = 7)
        @test read_property_corpus(second)["cases"] == corpus["cases"]
        @test_throws ArgumentError freeze_propcheck_corpus(path,
            PropCheck.itype(Int8); count = 4)
        @test_throws ArgumentError freeze_propcheck_corpus(path,
            PropCheck.itype(Int8); count = 0)
    end
end
