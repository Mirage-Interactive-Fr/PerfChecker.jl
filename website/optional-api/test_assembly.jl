using Test, SHA, TOML

include("assemble.jl")
using .OptionalAPIAssembly

root = realpath(joinpath(@__DIR__, "..", ".."))
revision = strip(read(Cmd(["git", "-C", root, "rev-parse", "HEAD"]), String))
exports, receipts = OptionalAPIAssembly.validate_optional_exports(root, revision)

@testset "Real isolated API export assembly" begin
    @test length(receipts) == 6
    mktempdir() do temporary
        copies = joinpath(temporary, "exports")
        for (slug, _) in OptionalAPIAssembly.OWNERS
            for relative in ["api-provenance.toml";
                             [entry["path"] for entry in receipts[slug]["outputs"]]]
                destination = joinpath(copies, slug, relative)
                mkpath(dirname(destination))
                cp(joinpath(exports, slug, relative), destination)
            end
        end
        markdown = joinpath(temporary, "canonical")
        mkpath(joinpath(markdown, "public"))
        core_inventory = joinpath(markdown, "public", "objects.inv")
        write(core_inventory, "Core inventory remains separate")
        before = read(core_inventory)
        OptionalAPIAssembly.assemble_optional_api(
            root, markdown, revision; exports = copies)
        @test read(core_inventory) == before
        @test isfile(joinpath(markdown, "optional-api", "navigation.json"))
        for (slug, _) in OptionalAPIAssembly.OWNERS
            @test read(joinpath(markdown, "public", "optional-api", "$slug.inv")) ==
                  read(joinpath(exports, slug, ".documenter", "public", "objects.inv"))
            @test TOML.parsefile(joinpath(
                markdown, "public", "optional-api", "$slug.toml")) ==
                  receipts[slug]
            for page in ("public-api", "full-api")
                original = read(
                    joinpath(exports, slug, ".documenter", slug, "$page.md"), String)
                assembled = read(
                    joinpath(markdown, "optional-api", slug, "$page.md"), String)
                @test replace(assembled, "---\neditLink: false\n---\n" => "---\n---\n";
                    count = 1) == original
            end
        end
        @test_throws ErrorException OptionalAPIAssembly.assemble_optional_api(
            root, markdown, revision; exports = copies)

        output = joinpath(copies, "web", ".documenter", "web", "full-api.md")
        original = read(output)
        write(output, "corrupted output")
        rejected = joinpath(temporary, "rejected")
        @test_throws ErrorException OptionalAPIAssembly.assemble_optional_api(
            root, rejected, revision; exports = copies)
        @test !ispath(rejected)
        write(output, original)
        inventory = joinpath(copies, "makie", ".documenter", "public", "objects.inv")
        original_inventory = read(inventory)
        write(inventory, "corrupted inventory")
        @test_throws ErrorException OptionalAPIAssembly.validate_optional_exports(
            root, revision; exports = copies)
        write(inventory, original_inventory)
        receipt_path = joinpath(copies, "pluto", "api-provenance.toml")
        receipt = TOML.parsefile(receipt_path)
        original_receipt = deepcopy(receipt)
        push!(receipt["outputs"], deepcopy(first(receipt["outputs"])))
        open(receipt_path, "w") do io
            TOML.print(io, receipt)
        end
        @test_throws ErrorException OptionalAPIAssembly.validate_optional_exports(
            root, revision; exports = copies)
        receipt = original_receipt
        receipt["channel"] = "dev"
        open(receipt_path, "w") do io
            TOML.print(io, receipt)
        end
        @test_throws ErrorException OptionalAPIAssembly.validate_optional_exports(
            root, revision; exports = copies)
        receipt["channel"] = "source"
        receipt["source_revision"] = "0"^40
        open(receipt_path, "w") do io
            TOML.print(io, receipt)
        end
        @test_throws ErrorException OptionalAPIAssembly.validate_optional_exports(
            root, revision; exports = copies)
        rm(joinpath(copies, "pluto"); recursive = true)
        @test_throws Exception OptionalAPIAssembly.validate_optional_exports(
            root, revision; exports = copies)
        @test_throws ErrorException OptionalAPIAssembly.checked_file(
            root, "../Project.toml")
        @test_throws ErrorException OptionalAPIAssembly.checked_file(
            root, joinpath(root, "Project.toml"))
    end
end
