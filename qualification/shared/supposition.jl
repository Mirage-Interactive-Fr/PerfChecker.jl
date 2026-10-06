using Test, PerfChecker

Sys.WORD_SIZE == 64 || error("Supposition qualification requires 64-bit Julia")
using Supposition

@testset "Supposition corpus backend on 64-bit Julia" begin
    @test Base.get_extension(PerfChecker, :SuppositionExt) !== nothing
    mktempdir() do dir
        path = joinpath(dir, "generated.json")
        possibility = Supposition.Data.Integers(0, 10)
        generated = freeze_supposition_corpus(path, possibility; count = 4,
            encode = value -> Dict("value" => value), metadata = Dict(:purpose => "qualification"))
        @test generated == path
        corpus = read_property_corpus(generated)
        @test corpus["producer"] == "Supposition.jl"
        @test corpus["count"] == length(corpus["cases"]) == 4
        @test all(x -> 0 <= x["value"] <= 10, corpus["cases"])
        @test corpus["metadata"]["purpose"] == "qualification"
        @test corpus["metadata"]["tries_per_case"] == 100_000
        @test corpus["metadata"]["generator_type"] == string(typeof(possibility))
        @test_throws ArgumentError freeze_supposition_corpus(path, possibility; count = 4)
        @test_throws ArgumentError freeze_supposition_corpus(path, possibility; count = 0)
        freeze_supposition_corpus(path, possibility; count = 2, force = true)
        @test read_property_corpus(path)["count"] == 2
    end
end
