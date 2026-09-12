@testitem "Development source identity changes without a manifest edit" tags=[:development_provenance] begin
    using PerfChecker, TOML
    mktempdir() do root
        package = joinpath(root, "dependency")
        mkpath(joinpath(package, "src"))
        write(joinpath(package, "Project.toml"), "name = \"Fixture\"\n")
        source = joinpath(package, "src", "Fixture.jl")
        write(source, "answer() = 1\n")
        manifest = Dict("deps" => Dict("Fixture" => [Dict("path" => "dependency")]))
        open(io -> TOML.print(io, manifest), joinpath(root, "Manifest.toml"), "w")
        first = PerfChecker._environment_provenance(root)
        write(source, "answer() = 2\n")
        second = PerfChecker._environment_provenance(root)
        @test first["manifest_sha256"] == second["manifest_sha256"]
        @test first["development_sources"] != second["development_sources"]
        @test only(second["development_sources"])["source"]["complete"]
        preferred = "Manifest-v$(VERSION.major).$(VERSION.minor).toml"
        write(joinpath(root, preferred), "manifest_format = \"2.0\"\n")
        @test PerfChecker._environment_provenance(root)["manifest_file"] == preferred
        mkpath(joinpath(package, "test"))
        write(joinpath(package, "test", "data.txt"), "not a declared input")
        @test PerfChecker._local_source_fingerprint(package) ==
              only(second["development_sources"])["source"]
        # Diagnostic adapters execute in workers but remain part of source identity.
        provider = joinpath(package, "providers", "Example")
        mkpath(provider)
        adapter = joinpath(provider, "adapter.jl")
        write(adapter, "diagnose() = :first\n")
        before_adapter_edit = PerfChecker._local_source_fingerprint(package)
        write(adapter, "diagnose() = :second\n")
        after_adapter_edit = PerfChecker._local_source_fingerprint(package)
        @test before_adapter_edit["sha256"] != after_adapter_edit["sha256"]
        @test before_adapter_edit["files"] == after_adapter_edit["files"]
        @test after_adapter_edit["complete"]
    end
end
