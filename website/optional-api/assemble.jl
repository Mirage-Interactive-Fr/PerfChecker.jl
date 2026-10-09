module OptionalAPIAssembly

using SHA, TOML

const OWNERS = [
    "linuxperf" => "PerfCheckerLinuxPerf", "likwid" => "PerfCheckerLIKWID",
    "makie" => "PerfCheckerMakie", "web" => "PerfCheckerWeb",
    "pluto" => "PerfCheckerPluto", "tachikoma" => "PerfCheckerTachikoma"]

filehash(path) = bytes2hex(sha256(read(path)))

function checked_file(root, relative)
    isabspath(relative) && error("Absolute provenance paths are not permitted")
    any(==(".."), split(replace(relative, '\\' => '/'), '/')) &&
        error("Provenance paths must stay inside their source tree")
    path = joinpath(root, relative)
    isfile(path) && !islink(path) || error("Missing regular provenance file: $relative")
    all(!=(".."), splitpath(relpath(realpath(path), realpath(root)))) ||
        error("Provenance file escapes its source tree")
    return path
end

function validate_optional_exports(root, revision;
        exports = joinpath(root, "website", "optional-api", "build", revision))
    occursin(r"^[0-9a-f]{40}$", revision) || error("Expected a full source revision")
    strip(read(Cmd(["git", "-C", root, "rev-parse", "HEAD"]), String)) == revision ||
        error("Optional API exports must match the canonical checkout revision")
    run(Cmd(["git", "-C", root, "diff", "--exit-code", "HEAD",
        "--", "Project.toml", "src", "packages"]))
    version = TOML.parsefile(joinpath(root, "Project.toml"))["version"]
    version == "1.0.1" || error("Optional API exports require Core 1.0.1 source")
    tree = strip(read(Cmd(["git", "-C", root, "rev-parse", "$revision^{tree}"]), String))
    receipts = Dict{String, Any}()
    for (slug, owner) in OWNERS
        directory = joinpath(exports, slug)
        receipt = TOML.parsefile(checked_file(directory, "api-provenance.toml"))
        receipt["schema"] == "perfchecker-optional-doc-export/1" ||
            error("Unknown API receipt")
        receipt["channel"] == "source" && receipt["source_revision"] == revision &&
            receipt["source_tree"] == tree && receipt["core_version"] == version &&
            receipt["owner"] == owner || error("Mixed optional API provenance: $slug")
        receipt["documenter"] == "1.19.0" && receipt["renderer"] == "0.3.5" ||
            error("Unexpected isolated API renderer versions")
        !isempty(receipt["bindings"]) && !isempty(receipt["methods"]) ||
            error("Missing actual Julia binding or method provenance")
        package = TOML.parsefile(joinpath(root, "packages", owner, "Project.toml"))
        receipt["owner_version"] == package["version"] &&
            receipt["owner_uuid"] == package["uuid"] || error("Companion metadata mismatch")
        for entry in receipt["inputs"]
            filehash(checked_file(root, entry["path"])) == entry["sha256"] ||
                error("Changed API rendering input: $(entry["path"])")
        end
        for entry in vcat(receipt["bindings"], receipt["methods"])
            startswith(entry["source"], "packages/$owner/") ||
                error("Wrong docstring owner")
            filehash(checked_file(root, entry["source"])) == entry["source_sha256"] ||
                error("Changed companion source: $(entry["source"])")
        end
        expected = Set([".documenter/$slug/public-api.md", ".documenter/$slug/full-api.md",
            ".documenter/public/objects.inv"])
        Set(entry["path"] for entry in receipt["outputs"]) == expected ||
            error("Incomplete or unexpected API outputs: $slug")
        length(receipt["outputs"]) == length(expected) || error("Duplicate API output")
        for entry in receipt["outputs"]
            filehash(checked_file(directory, entry["path"])) == entry["sha256"] ||
                error("Changed API output: $(entry["path"])")
        end
        for page in ("public-api", "full-api")
            body = read(joinpath(directory, ".documenter", slug, "$page.md"), String)
            startswith(body, "---\n---\n") || error("Unexpected rendered frontmatter")
            occursin("jldocstring", body) || error("Missing rendered Julia docstrings")
            occursin("/blob/$revision/packages/$owner/", body) ||
                error("Wrong source links")
            occursin(r"```@(docs|autodocs|ref|index)|\]\(@ref", body) &&
                error("Unrendered Julia directive in optional API output")
        end
        receipts[slug] = receipt
    end
    return exports, receipts
end

function canonical_optional_page(body, slug)
    # Documenter resolves owner-local @ref links against the isolated site's root.
    # Keep them relative when the page moves under optional-api/<owner>/ so every
    # canonical hosting base works. External/source URLs and anchors stay intact.
    links = Regex("\\]\\(/$slug/((?:public|full)-api)(?=[#)])")
    body = replace(body, links => link -> replace(link, "](/$slug/" => "](./"; count = 1))
    return replace(body, "---\n---\n" => "---\neditLink: false\n---\n"; count = 1)
end

function assemble_optional_api(root, markdown, revision;
        exports = joinpath(root, "website", "optional-api", "build", revision))
    exports, receipts = validate_optional_exports(root, revision; exports)
    destination = joinpath(markdown, "optional-api")
    ispath(destination) && error("Optional API destination already exists")
    # Validate the entire set before writing anything to the canonical build.
    mkpath(destination)
    for (slug, _) in OWNERS
        directory = joinpath(exports, slug)
        mkpath(joinpath(destination, slug))
        # Its existing <slug>/full-api URI resolves relative to /optional-api/.
        # Separate inventories preserve different methods of shared Core bindings.
        public_directory = joinpath(markdown, "public", "optional-api")
        mkpath(public_directory)
        cp(joinpath(directory, ".documenter", "public", "objects.inv"),
            joinpath(public_directory, "$slug.inv"))
        cp(joinpath(directory, "api-provenance.toml"),
            joinpath(public_directory, "$slug.toml"))
        for page in ("public-api", "full-api")
            path = joinpath(destination, slug, "$page.md")
            body = read(joinpath(directory, ".documenter", slug, "$page.md"), String)
            write(path, canonical_optional_page(body, slug))
        end
    end
    # A tracked canonical theme consumes this small, generated navigation marker.
    write(joinpath(destination, "navigation.json"),
        "{\"source_revision\":$(repr(revision)),\"owners\":[" *
        join(
            ["{\"slug\":$(repr(slug)),\"name\":$(repr(owner))}" for (slug, owner) in OWNERS],
            ",") *
        "]}\n")
    return receipts
end

end
