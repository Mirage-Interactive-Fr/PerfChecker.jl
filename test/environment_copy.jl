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

@testitem "Relative dependency symlinks pointing outside a project stay anchored" tags=[
    :worker_environment, :profile_contract] begin
    using PerfChecker
    using TOML
    if !Sys.iswindows()
        mktempdir() do root
            source, sibling = joinpath(root, "Runner"), joinpath(root, "Sibling")
            mkpath(source)
            mkpath(sibling)
            symlink("../Sibling", joinpath(source, "linked"))
            project = "[sources.Dependency]\npath = \"linked\"\n"
            manifest = "manifest_format = \"2.0\"\n[[deps.Dependency]]\npath = \"linked\"\nuuid = \"fa635044-6c9b-4c82-94a4-9aa6ef3a1a43\"\n"
            write(joinpath(source, "Project.toml"), project)
            write(joinpath(source, "Manifest.toml"), manifest)
            copied = PerfChecker._copy_check_environment(
                source, joinpath(root, "private", "environment"))
            expected = joinpath(source, "linked")
            @test TOML.parsefile(joinpath(copied, "Project.toml"))["sources"]["Dependency"]["path"] ==
                  expected
            @test only(TOML.parsefile(joinpath(copied, "Manifest.toml"))["deps"]["Dependency"])["path"] ==
                  expected
            @test realpath(expected) == realpath(sibling)
            @test read(joinpath(source, "Project.toml"), String) == project
            @test read(joinpath(source, "Manifest.toml"), String) == manifest
        end
    end
end

@testitem "Worker copies preserve external and internal local dependencies" tags=[
    :worker_environment, :profile_contract] begin
    using PerfChecker
    using TOML
    mktempdir() do root
        source = joinpath(root, "Runner")
        sibling = joinpath(root, "ExternalFixture")
        internal = joinpath(source, "vendor", "InternalFixture")
        for (name, path, uuid) in (
            ("ExternalFixture", sibling,
                "fa635044-6c9b-4c82-94a4-9aa6ef3a1a43"),
            ("InternalFixture", internal,
                "9c8a5992-5ac0-4dfc-9b9f-416d7c612c68"))
            mkpath(joinpath(path, "src"))
            write(joinpath(path, "Project.toml"),
                "name = $(repr(name))\nuuid = $(repr(uuid))\nversion = \"1.0.0\"\n")
            write(joinpath(path, "src", "$name.jl"), "module $name\nvalue() = 42\nend\n")
        end
        project = Dict(
            "deps" => Dict("ExternalFixture" => "fa635044-6c9b-4c82-94a4-9aa6ef3a1a43",
                "InternalFixture" => "9c8a5992-5ac0-4dfc-9b9f-416d7c612c68"),
            "sources" => Dict("ExternalFixture" => Dict("path" => "../ExternalFixture"),
                "InternalFixture" => Dict("path" => "vendor/InternalFixture"),
                "LocalRepo" => Dict("url" => "../ExternalFixture"),
                "RemoteRepo" => Dict("url" => "host:repository")))
        manifest = Dict("manifest_format" => "2.0", "julia_version" => string(VERSION),
            "deps" => Dict(
                "ExternalFixture" => [Dict("path" => "../ExternalFixture",
                    "uuid" => project["deps"]["ExternalFixture"], "version" => "1.0.0")],
                "InternalFixture" => [Dict("path" => "vendor/InternalFixture",
                    "uuid" => project["deps"]["InternalFixture"], "version" => "1.0.0")]))
        open(io -> TOML.print(io, project), joinpath(source, "Project.toml"), "w")
        for name in (
            "Manifest.toml", "JuliaManifest-v$(VERSION.major).$(VERSION.minor).toml")
            open(io -> TOML.print(io, manifest), joinpath(source, name), "w")
        end
        originals = Dict(name => read(joinpath(source, name))
        for name in ("Project.toml", "Manifest.toml",
            "JuliaManifest-v$(VERSION.major).$(VERSION.minor).toml"))
        prepared = PerfChecker._copy_check_environment(source, joinpath(root, "prepared"))
        worker = PerfChecker._copy_check_environment(prepared, joinpath(root, "worker"))
        for copied in (prepared, worker)
            metadata = TOML.parsefile(joinpath(copied, "Project.toml"))
            @test metadata["sources"]["ExternalFixture"]["path"] == sibling
            @test metadata["sources"]["InternalFixture"]["path"] ==
                  joinpath("vendor", "InternalFixture")
            @test metadata["sources"]["LocalRepo"]["url"] == sibling
            @test metadata["sources"]["RemoteRepo"]["url"] == "host:repository"
            for name in (
                "Manifest.toml", "JuliaManifest-v$(VERSION.major).$(VERSION.minor).toml")
                entries = TOML.parsefile(joinpath(copied, name))["deps"]
                @test only(entries["ExternalFixture"])["path"] == sibling
                @test only(entries["InternalFixture"])["path"] ==
                      joinpath("vendor", "InternalFixture")
            end
        end
        process = PerfChecker.Worker(;
            exeflags = ["--threads=1", "--gcthreads=1", "--project=$worker"])
        try
            @test PerfChecker.remote_eval_fetch(
                Main, process, quote
                    using ExternalFixture, InternalFixture
                    (ExternalFixture.value(), InternalFixture.value())
                end) == (42, 42)
        finally
            PerfChecker.safe_stop(process)
        end
        @test all(name -> read(joinpath(source, name)) == originals[name], keys(originals))
    end
end

@testitem "Custom manifests and symlinked metadata remain private" tags=[
    :worker_environment, :profile_contract] begin
    using PerfChecker
    using TOML
    mktempdir() do root
        source = joinpath(root, "Runner")
        mkpath(source)
        manifest = joinpath(root, "locked.toml")
        original = "manifest_format = \"2.0\"\n[[deps.Dependency]]\npath = \"Dependency\"\nuuid = \"fa635044-6c9b-4c82-94a4-9aa6ef3a1a43\"\n"
        write(manifest, original)
        write(joinpath(source, "Project.toml"), "manifest = \"../locked.toml\"\n")
        write(joinpath(source, "JuliaProject.toml"), "manifest = \"../locked.toml\"\n")
        copied = PerfChecker._copy_check_environment(source, joinpath(root, "copy"))
        private = normpath(joinpath(
            copied, TOML.parsefile(joinpath(copied, "Project.toml"))["manifest"]))
        @test PerfChecker.PerfCheckerProfileRuntime.within_root(private, copied)
        @test TOML.parsefile(joinpath(copied, "JuliaProject.toml"))["manifest"] ==
              TOML.parsefile(joinpath(copied, "Project.toml"))["manifest"]
        @test only(TOML.parsefile(private)["deps"]["Dependency"])["path"] ==
              joinpath(root, "Dependency")
        @test read(manifest, String) == original
        @test read(joinpath(source, "Project.toml"), String) ==
              "manifest = \"../locked.toml\"\n"
        if !Sys.iswindows() # symlink creation needs extra privileges on Windows
            rm(joinpath(source, "Project.toml"))
            linked_project = joinpath(root, "project.toml")
            write(linked_project, "[sources.Dependency]\npath = \"../Dependency\"\n")
            symlink("../project.toml", joinpath(source, "Project.toml"))
            symlink("../locked.toml", joinpath(source, "Manifest.toml"))
            linked = PerfChecker._copy_check_environment(source, joinpath(root, "linked"))
            @test !islink(joinpath(linked, "Project.toml"))
            @test !islink(joinpath(linked, "Manifest.toml"))
            @test read(linked_project, String) ==
                  "[sources.Dependency]\npath = \"../Dependency\"\n"
            @test read(manifest, String) == original
        end
    end
end

@testitem "Read-only seeds produce writable private worker metadata" tags=[
    :worker_environment, :profile_contract] begin
    using PerfChecker
    using SHA, TOML
    import Pkg
    mktempdir() do root
        source, dependency = joinpath(root, "seed"), joinpath(root, "Dependency")
        metadata = joinpath(source, "metadata")
        mkpath(metadata)
        mkpath(joinpath(dependency, "src"))
        write(joinpath(dependency, "Project.toml"),
            "name = \"ReadonlyDependency\"\nuuid = \"fa635044-6c9b-4c82-94a4-9aa6ef3a1a43\"\nversion = \"1.0.0\"\n")
        write(joinpath(dependency, "src", "ReadonlyDependency.jl"),
            "module ReadonlyDependency\nvalue() = 42\nend\n")
        project, manifest = joinpath(source, "Project.toml"),
        joinpath(metadata, "locked.toml")
        write(project, "manifest = \"metadata/locked.toml\"\n[deps]\n")
        write(manifest,
            "manifest_format = \"2.0\"\njulia_version = $(repr(string(VERSION)))\n[deps]\n")
        chmod(project, 0o444)
        chmod(manifest, 0o444)
        chmod(metadata, 0o555)
        originals = Dict(path => (sha256(read(path)), filemode(path))
        for path in (project, manifest))
        directory_mode = filemode(metadata)
        prepared_root = nothing
        preparation_project = nothing
        external_directory = nothing
        try
            copied = PerfChecker._copy_check_environment(source, joinpath(root, "copy"))
            copied_manifest = joinpath(copied, "metadata", "locked.toml")
            @test filemode(joinpath(copied, "Project.toml")) & 0o200 != 0
            @test filemode(copied_manifest) & 0o200 != 0
            # Windows stat reports read/write flags rather than POSIX traversal bits.
            if !Sys.iswindows()
                @test filemode(dirname(copied_manifest)) & 0o300 == 0o300
            end
            probe, probe_io = mktemp(dirname(copied_manifest))
            try
                write(probe_io, "private worker metadata\n")
                close(probe_io)
                @test read(probe, String) == "private worker metadata\n"
            finally
                isopen(probe_io) && close(probe_io)
                rm(probe)
            end
            @test !ispath(probe)
            @test !islink(copied_manifest)
            open(io -> write(io, "\n"), copied_manifest, "a")
            @test read(manifest) != read(copied_manifest)
            if !Sys.iswindows()
                linked = joinpath(source, "Manifest.toml")
                symlink("metadata/locked.toml", linked)
                external_directory = mkpath(joinpath(root, "external"))
                chmod(external_directory, 0o555)
                symlink("../external", joinpath(source, "linked-directory"))
                private = PerfChecker._copy_check_environment(
                    source, joinpath(root, "linked"))
                @test !islink(joinpath(private, "Manifest.toml"))
                @test filemode(joinpath(private, "Manifest.toml")) & 0o200 != 0
                @test islink(joinpath(private, "linked-directory"))
                @test filemode(external_directory) & 0o777 == 0o555
            end
            # The real preparation path must let Pkg write its project/manifest,
            # using an existing local package rather than downloading a target.
            preparation_seed = mkpath(joinpath(root, "preparation-seed"))
            preparation_project = joinpath(preparation_seed, "Project.toml")
            write(preparation_project, "[deps]\n")
            chmod(preparation_project, 0o444)
            preparation_state = (sha256(read(preparation_project)),
                filemode(preparation_project))
            config = PerfConfig(:network; path = preparation_seed, include_current = false,
                devops = Pkg.PackageSpec(path = dependency, name = "ReadonlyDependency"),
                quiet = true, threads = 1)
            prepared_root, environment = PerfChecker._prepare_check_environment(config)
            @test TOML.parsefile(joinpath(environment, "Project.toml"))["deps"][
                "ReadonlyDependency"] == "fa635044-6c9b-4c82-94a4-9aa6ef3a1a43"
            @test (sha256(read(preparation_project)), filemode(preparation_project)) ==
                  preparation_state
            @test all(path -> (sha256(read(path)), filemode(path)) == originals[path],
                keys(originals))
            @test filemode(metadata) == directory_mode
        finally
            prepared_root === nothing || rm(prepared_root; recursive = true, force = true)
            preparation_project === nothing || chmod(preparation_project, 0o644)
            external_directory === nothing || chmod(external_directory, 0o755)
            chmod(metadata, 0o755)
            chmod(project, 0o644)
            chmod(manifest, 0o644)
        end
    end
end
