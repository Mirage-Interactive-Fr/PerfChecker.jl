using Test, Documenter, DocumenterVitepress

include("compat.jl")
include("optional-api/assemble.jl")

@testset "DocumenterVitepress $(pkgversion(DocumenterVitepress)) inventory HTML routes" begin
    # Exercise the writer used by makedocs, with its real page-build interface.
    # These paths are relative to each inventory's build directory, not a
    # deployment base; assembly preserves companion inventories byte-for-byte.
    build = abspath(joinpath(@__DIR__, "build"))
    document = (; user = (; build))
    inventory_uri(path, anchor = nothing) = DocumenterVitepress._get_inventory_uri(
        document, (; build = joinpath(build, path)), anchor)
    @test inventory_uri("index.md") == "index.html"
    @test inventory_uri(joinpath("reference", "api.md"), "Public-API") ==
          "reference/api.html#Public-API"
    @test inventory_uri(joinpath("reference", "api.md"),
        "PerfChecker.performance_plot-Tuple{RunBundle,String}") ==
          "reference/api.html#PerfChecker.performance_plot-Tuple%7BRunBundle%2CString%7D"
    for (slug, owner) in OptionalAPIAssembly.OWNERS
        for page in ("public-api", "full-api")
            path = joinpath(slug, "$page.md")
            @test inventory_uri(path) == "$slug/$page.html"
            @test inventory_uri(path, "$owner-$page") == "$slug/$page.html#$owner-$page"
            @test inventory_uri(path, "$owner.example-Tuple{Int64}") ==
                  "$slug/$page.html#$owner.example-Tuple%7BInt64%7D"
        end
    end
    @test inventory_uri(joinpath("API pages", "μ.md"), "value < limit") ==
          "API%20pages/%CE%BC.html#value%20%3C%20limit"
end
