@testitem "Worker copy exclusions are explicit and preserve environment metadata" tags=[:worker_environment] begin
    using PerfChecker
    mktempdir() do root
        source = joinpath(root, "source")
        mkpath(joinpath(source, ".lab"))
        mkpath(joinpath(source, "fixtures"))
        write(joinpath(source, "Project.toml"), "name = \"Fixture\"\n")
        write(joinpath(source, "Manifest.toml"), "manifest_format = \"2.0\"\n")
        write(joinpath(source, ".lab", "cache"), "not an input")
        write(joinpath(source, "fixtures", "input"), "required")
        plain = PerfChecker._copy_check_environment(source, joinpath(root, "plain"))
        @test isfile(joinpath(plain, ".lab", "cache"))
        selected = PerfChecker._copy_check_environment(
            source, joinpath(root, "selected"); exclude = [".lab"])
        @test !ispath(joinpath(selected, ".lab"))
        @test read(joinpath(selected, "fixtures", "input"), String) == "required"
        @test read(joinpath(selected, "Project.toml")) ==
              read(joinpath(source, "Project.toml"))
        @test read(joinpath(selected, "Manifest.toml")) ==
              read(joinpath(source, "Manifest.toml"))
        @test_throws ArgumentError PerfChecker._copy_check_environment(source, selected)
        for invalid in (["../fixtures"], ["Project.toml"],
            ["PROJECT.TOML"], ["Manifest-v1.12.toml"], ".lab")
            @test_throws ArgumentError PerfChecker._copy_check_environment(
                source, joinpath(root, "invalid"); exclude = invalid)
            @test !ispath(joinpath(root, "invalid"))
        end
    end
end
