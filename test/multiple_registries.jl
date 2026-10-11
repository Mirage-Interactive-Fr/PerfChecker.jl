@testitem "Version lookup unions private registries" tags=[:unit, :multiple_registries] begin
    using PerfChecker
    import Pkg

    mktempdir() do directory
        depot = joinpath(directory, "depot")
        registry_root = joinpath(depot, "registries")
        mkpath(registry_root)
        package_name = "PerfCheckerRegistryFixture"
        uuid_one = "597145a8-4b57-4a9e-8744-e8fd4ffde642"
        uuid_two = "d7ec36ee-c5da-4f1d-8950-54cdd82320f7"
        function registry(path, name, uuid, packages)
            mkpath(path)
            entries = String[]
            for (package_uuid, package_path, versions) in packages
                push!(entries,
                    "\"$package_uuid\" = { name = \"$package_name\", path = \"$package_path\" }")
                location = joinpath(path, package_path)
                mkpath(location)
                write(joinpath(location, "Package.toml"),
                    "name = \"$package_name\"\nuuid = \"$package_uuid\"\nrepo = \"https://example.invalid/fixture.git\"\n")
                write(joinpath(location, "Versions.toml"),
                    join(
                        ["[\"$version\"]\ngit-tree-sha1 = \"0000000000000000000000000000000000000000\"\n"
                         for version in versions],
                        '\n'))
            end
            write(joinpath(path, "Registry.toml"),
                "name = \"$name\"\nuuid = \"$uuid\"\nrepo = \"https://example.invalid/$name.git\"\n\n[packages]\n" *
                join(entries, '\n') * "\n")
        end
        registry(joinpath(registry_root, "General"), "General",
            "23338594-aafe-5451-b93e-139f81909106",
            [(uuid_one, "P/PerfCheckerRegistryFixture", ["0.2.0", "0.1.0"])])
        registry(joinpath(registry_root, "Custom"), "Custom",
            "a4c8a6fa-fc3c-42c5-8cb4-b6f73835df3f",
            [(uuid_one, "nested/custom-package", ["0.3.0", "0.1.0"]),
                (uuid_two, "other/same-name", ["0.4.0"])])
        compressed_available = Pkg.Registry.registry_read_from_tarball()
        if compressed_available
            compressed_source = joinpath(directory, "compressed-source")
            compressed_uuid = "4b580fb4-2c8b-4b0a-8a81-f2e2d73b9124"
            registry(compressed_source, "Compressed", compressed_uuid,
                [(uuid_one, "unusual/fixture-location", ["0.5.0", "0.3.0"])])
            Pkg.PlatformEngines.package(compressed_source,
                joinpath(registry_root, "Compressed.tar.gz"); io = devnull)
            write(joinpath(registry_root, "Compressed.toml"),
                "uuid = \"$compressed_uuid\"\npath = \"Compressed.tar.gz\"\ngit-tree-sha1 = \"1111111111111111111111111111111111111111\"\n")
        end
        previous_depots = copy(DEPOT_PATH)
        try
            empty!(DEPOT_PATH)
            push!(DEPOT_PATH, depot)
            registries = Pkg.Registry.reachable_registries()
            @test sort([registry.name for registry in registries]) ==
                  (compressed_available ? ["Compressed", "Custom", "General"] :
                   ["Custom", "General"])
            @test all(registry -> startswith(registry.path, registry_root), registries)
            @test length(only(filter(
                registry -> registry.name == "Custom", registries)).pkgs) == 2
            @test PerfChecker.get_pkg_versions(package_name, ["General"]) ==
                  [v"0.1.0", v"0.2.0"]
            @test PerfChecker.get_pkg_versions(package_name, ["Custom"]) ==
                  [v"0.1.0", v"0.3.0", v"0.4.0"]
            @test PerfChecker.get_pkg_versions(package_name, ["General", "Custom"]) ==
                  [v"0.1.0", v"0.2.0", v"0.3.0", v"0.4.0"]
            expected = compressed_available ?
                       [v"0.1.0", v"0.2.0", v"0.3.0", v"0.4.0", v"0.5.0"] :
                       [v"0.1.0", v"0.2.0", v"0.3.0", v"0.4.0"]
            @test PerfChecker.get_pkg_versions(package_name) == expected
            @test isempty(PerfChecker.get_pkg_versions(package_name, ["Missing"]))
            @test isempty(PerfChecker.get_pkg_versions(package_name, String[]))
            @test PerfChecker.get_pkg_versions(
                package_name, ["Custom", "General", "Custom"]) ==
                  [v"0.1.0", v"0.2.0", v"0.3.0", v"0.4.0"]
            @test isempty(PerfChecker.get_pkg_versions("MissingPackage"))
            if compressed_available
                @test PerfChecker.get_pkg_versions(package_name, ["Compressed"]) ==
                      [v"0.3.0", v"0.5.0"]
            end
            # Other Pkg operations may have already parsed package metadata and
            # released the original tarball strings. Lookups must still agree.
            for registry in registries, package in values(registry.pkgs)
                if applicable(Pkg.Registry.registry_info, registry, package)
                    Pkg.Registry.registry_info(registry, package)
                else
                    Pkg.Registry.registry_info(package)
                end
            end
            @test PerfChecker.get_pkg_versions(package_name) == expected
            @test PerfChecker.get_pkg_versions(package_name, ["General", "Custom"]) ==
                  [v"0.1.0", v"0.2.0", v"0.3.0", v"0.4.0"]
        finally
            empty!(DEPOT_PATH)
            append!(DEPOT_PATH, previous_depots)
        end
        @test DEPOT_PATH == previous_depots
    end
end
