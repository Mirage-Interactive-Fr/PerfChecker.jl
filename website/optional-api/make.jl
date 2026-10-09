using Documenter, DocumenterVitepress, Pkg, SHA, TOML
using PerfChecker

configurations = Dict(
    "linuxperf" => (:PerfCheckerLinuxPerf,
        [:CounterRecord, :CounterResult, :measure_counters, :counter_bundle,
            :counter_command, :counter_executor, :run_counter_suite]),
    "likwid" => (:PerfCheckerLIKWID,
        [:CounterRecord, :CounterResult, :measure_counters, :counter_bundle,
            :counter_command, :counter_executor, :run_counter_suite]),
    "makie" => (:PerfCheckerMakie,
        [:performance_figure, :suite_dashboard, :checkres_to_boxplots,
            :checkres_to_scatterlines, :checkres_to_pie, :table_to_pie,
            :checkres_figures, :saveplot]),
    "web" => (:PerfCheckerWeb,
        [:serve_suite, :register_oxygen_routes!, :register_testitem_routes!,
            :studio_token_authenticator, :run_studio_agent]),
    "pluto" => (:PerfCheckerPluto,
        [:prepare_pluto_dashboard, :launch_pluto_dashboard, :write_suite_notebook,
            :write_investigation_notebook]),
    "tachikoma" => (:PerfCheckerTachikoma,
        [:SuiteTUI, :tui_model, :tui, :refresh!, :close!, :plot_pixels]))
length(ARGS) == 1 && haskey(configurations, ARGS[1]) ||
    error("Usage: julia --project=<isolated-project> website/optional-api/make.jl " *
          join(sort!(collect(keys(configurations))), "|"))
slug = only(ARGS)
if slug == "linuxperf"
    using PerfCheckerLinuxPerf
elseif slug == "likwid"
    using PerfCheckerLIKWID
elseif slug == "makie"
    using PerfCheckerMakie, WGLMakie, Bonito
elseif slug == "web"
    using PerfCheckerWeb
elseif slug == "pluto"
    using PerfCheckerPluto
else
    using PerfCheckerTachikoma, PerfCheckerMakie, Makie
end
owner_symbol, expected = configurations[slug]
owner = getfield(Main, owner_symbol)
owner_name = string(nameof(owner))
root = realpath(joinpath(@__DIR__, "..", ".."))
owner_root = joinpath(root, "packages", owner_name)
realpath(pkgdir(PerfChecker)) == root || error("PerfChecker must load from this checkout")
realpath(pkgdir(owner)) == realpath(owner_root) ||
    error("The companion must load from this checkout")
pkgversion(PerfChecker) == v"1.0.1" ||
    error("This builder requires Core 1.0.1 source, not Core 1.0.0")
owner_version = VersionNumber(TOML.parsefile(joinpath(owner_root, "Project.toml"))["version"])
pkgversion(owner) == owner_version ||
    error("The loaded companion version differs from its source")
pkgversion(Documenter) == v"1.19.0" && pkgversion(DocumenterVitepress) == v"0.3.5" ||
    error("The docsystem and renderer versions must match the prototype pins")
docmodules = [owner]
if slug == "makie"
    extension = Base.get_extension(owner, :WGLMakieExt)
    extension === nothing &&
        error("Load the real WGLMakie/Bonito extension for its API docstring")
    push!(docmodules, extension)
elseif slug == "tachikoma"
    Base.get_extension(owner, :MakieExt) === nothing &&
        error("Load the real Makie extension for the plot_pixels method inventory")
    realpath(pkgdir(PerfCheckerMakie)) ==
    realpath(joinpath(root, "packages", "PerfCheckerMakie")) ||
        error("Tachikoma's Makie companion must load from this checkout")
end

source_revision = strip(read(`git -C $root rev-parse HEAD`, String))
occursin(r"^[0-9a-f]{40}$", source_revision) || error("A full source revision is required")
# A documentation prototype may have uncommitted documentation inputs, whose hashes
# are recorded below. Runtime source and package metadata must match this revision.
run(`git -C $root diff --exit-code HEAD -- Project.toml src packages`)
isempty(strip(read(
    `git -C $root ls-files --others --exclude-standard src packages`, String))) ||
    error("Untracked runtime/package files would make source provenance ambiguous")

active_project = Base.active_project()
active_project === nothing && error("An isolated project is required")
manifest = joinpath(dirname(active_project), "Manifest.toml")
isfile(manifest) || error("Resolve the isolated project explicitly before rendering")
configuration = TOML.parsefile(joinpath(@__DIR__, slug, "Project.toml"))
active = TOML.parsefile(active_project)
for key in ("deps", "compat")
    get(active, key, nothing) == configuration[key] ||
        error("The isolated project's $key must match the checked-in configuration")
end
dependencies = Pkg.dependencies()
pretty_tables = [info for info in values(dependencies) if info.name == "PrettyTables"]
if slug in ("linuxperf", "likwid")
    expected_major = slug == "linuxperf" ? 2 : 3
    only(pretty_tables).version !== nothing &&
        only(pretty_tables).version.major == expected_major ||
        error("$owner_name requires the separate PrettyTables $expected_major environment")
end

sort!(expected; by = string)
actual = sort(filter(name -> name != nameof(owner), names(owner)); by = string)
actual == expected || error("The public binding inventory changed; review the prototype")
records = Dict{String, Any}[]
method_records = Dict{String, Any}[]
for docmodule in docmodules
    for (binding, multidoc) in sort!(collect(Documenter.DocSystem.getmeta(docmodule));
        by = entry -> string(first(entry)))
        status = Documenter.DocSystem.APIStatus(owner, binding.var)
        for signature in multidoc.order
            docstring = multidoc.docs[signature]
            source = realpath(String(docstring.data[:path]))
            relative = replace(relpath(source, root), '\\' => '/')
            startswith(relative, "packages/$owner_name/") ||
                error("A companion docstring must be owned by its source package")
            # Record actual Docs metadata, without reconstructing bodies or
            # registering them in a substitute Julia module.
            push!(records,
                Dict{String, Any}(
                    "owner" => owner_name, "binding" => string(binding),
                    "binding_module" => string(binding.mod),
                    "docstring_module" => string(docstring.data[:module]),
                    "signature" => string(signature), "public" => status.ispublic,
                    "exported" => status.isexported, "source" => relative,
                    "line" => Int(docstring.data[:linenumber]),
                    "source_sha256" => bytes2hex(sha256(read(source)))))
        end
    end
end
for name in expected
    binding = Documenter.DocSystem.binding(owner, name)
    isempty(Documenter.DocSystem.getdocs(binding; modules = docmodules, aliases = false)) &&
        error("Missing actual companion docstring for $owner_name.$name")
end
documented_names = slug == "makie" ? vcat(expected, [:performance_plot_html]) : expected
for name in documented_names
    binding = Documenter.DocSystem.binding(owner, name)
    value = getfield(binding.mod, binding.var)
    value isa Union{Function, Type} || continue
    for method in methods(value)
        file = String(method.file)
        isfile(file) || continue
        source = realpath(file)
        relative = replace(relpath(source, root), '\\' => '/')
        startswith(relative, "packages/$owner_name/") || continue
        push!(method_records,
            Dict{String, Any}(
                "owner" => owner_name, "binding" => string(binding),
                "binding_module" => string(binding.mod),
                "defining_module" => string(method.module), "signature" => string(method.sig),
                "source" => relative, "line" => Int(method.line),
                "source_sha256" => bytes2hex(sha256(read(source)))))
    end
end
sort!(method_records;
    by = entry -> (entry["binding"], entry["signature"], entry["source"], entry["line"]))

include(joinpath(@__DIR__, "..", "compat.jl"))
# Core makedocs cleans website/build; these validated exports must outlive it.
build = joinpath(root, "website", "optional-api", "build", source_revision, slug)
makedocs(;
    root = @__DIR__, source = "src", build, modules = docmodules,
    pagesonly = true, checkdocs = :all, doctest = false, warnonly = false,
    sitename = "$owner_name API",
    remotes = Dict(root => (
        Documenter.Remotes.GitHub(
            "Mirage-Interactive-Fr", "PerfChecker.jl"),
        source_revision)),
    format = DocumenterVitepress.MarkdownVitepress(
        build_vitepress = false, install_npm = false, write_inventory = true,
        inventory_version = string(pkgversion(PerfChecker)),
        repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
        devbranch = "main", devurl = "dev",
        deploy_url = "https://perfchecker.mirageinteractive.fr/dev/optional-api/"),
    pages = ["Public API" => "$slug/public-api.md", "Full API" => "$slug/full-api.md"]
)

markdown = joinpath(build, ".documenter")
inventory = joinpath(markdown, "public", "objects.inv")
isfile(inventory) && filesize(inventory) > 0 || error("Missing real Documenter inventory")
rendered_files = [joinpath(markdown, slug, page * ".md")
                  for page in ("public-api", "full-api")]
for file in rendered_files
    rendered = read(file, String)
    occursin("jldocstring", rendered) || error("No rendered Julia docstrings in $file")
    for name in documented_names
        binding = string(Documenter.DocSystem.binding(owner, name))
        occursin("class=\"jlbinding\">$binding</span>", rendered) ||
            error("Missing rendered entry for $binding in $file")
    end
    anchors = [match.captures[1] for match in eachmatch(r"<a id='([^']+)'", rendered)]
    length(anchors) == length(unique(anchors)) || error("Duplicate Julia anchors in $file")
    occursin("/blob/$source_revision/packages/$owner_name/", rendered) ||
        error("No source link to the exact companion revision in $file")
    occursin("(@ref)", rendered) &&
        error("An unresolved Julia reference survived rendering")
end
inputs = [@__FILE__, joinpath(@__DIR__, slug, "Project.toml"),
    joinpath(@__DIR__, "..", "compat.jl"),
    joinpath(root, "website", "package.json"), joinpath(
        root, "website", "package-lock.json"),
    joinpath(@__DIR__, "src", ".vitepress", "config.mts"),
    joinpath(@__DIR__, "src", ".vitepress", "theme", "index.ts"),
    joinpath(@__DIR__, "src", ".vitepress", "theme", "style.css"),
    [joinpath(@__DIR__, "src", slug, page * ".md")
     for page in ("public-api", "full-api")]...]
receipt = Dict{String, Any}(
    "schema" => "perfchecker-optional-doc-export/1", "channel" => "source",
    "source_revision" => source_revision,
    "source_tree" => strip(read(
        Cmd(["git", "-C", root, "rev-parse", "HEAD^{tree}"]), String)),
    "core_version" => string(pkgversion(PerfChecker)), "owner" => owner_name,
    "owner_uuid" => string(Base.PkgId(owner).uuid),
    "owner_version" => string(pkgversion(owner)), "julia" => string(VERSION),
    "documenter" => string(pkgversion(Documenter)),
    "renderer" => string(pkgversion(DocumenterVitepress)),
    "pretty_tables" => isempty(pretty_tables) ? "absent" :
                       string(only(pretty_tables).version),
    "project_sha256" => bytes2hex(sha256(read(active_project))),
    "manifest_sha256" => bytes2hex(sha256(read(manifest))),
    "bindings" => records, "methods" => method_records,
    "documented_modules" => string.(docmodules),
    "inputs" => [Dict("path" => replace(relpath(file, root), '\\' => '/'),
                     "sha256" => bytes2hex(sha256(read(file)))) for file in inputs],
    "outputs" => [Dict("path" => replace(relpath(file, build), '\\' => '/'),
                      "sha256" => bytes2hex(sha256(read(file))))
                  for file in vcat(rendered_files, [inventory])])
open(joinpath(build, "api-provenance.toml"), "w") do io
    TOML.print(io, receipt; sorted = true)
end
println("Rendered actual $owner_name docstrings in $markdown")
