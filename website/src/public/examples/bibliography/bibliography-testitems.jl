# Save this file below the root passed to discover_testitems/run_testitems.
# The prepared test environment needs Bibliography, TestItems and TestItemRunner.
using TestItems

@testitem "Bibliography BibTeX round trip" tags=[:bibliography, :small] begin
    using Bibliography

    # This item measures the whole test, including the temporary file and import.
    # Keep assertions: a fast operation that produces the wrong result is not valid.
    mktempdir() do directory
        input = joinpath(directory, "article.bib")
        write(input, """
        @article{lovelace2026,
            title = {A reusable performance contract},
            author = {Lovelace, Ada},
            journal = {Julia Studies},
            year = {2026}
        }
        """)
        bibliography = Bibliography.import_bibtex(input)
        exported = Bibliography.export_bibtex(bibliography)
        @test occursin("lovelace2026", exported)
        @test occursin("A reusable performance contract", exported)
    end
end
