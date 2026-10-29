using Documenter, DocumenterVitepress, TOML, SHA

using PerfChecker

include("compat.jl")
local_preview = get(ENV, "PERFCHECKER_DOCS_LOCAL_PREVIEW", "false") == "true"

docs_url = get(ENV, "PERFCHECKER_DOCS_URL", "https://perfchecker.mirageinteractive.fr/")
preview_url = local_preview && occursin(
    r"^http://(?:127\.0\.0\.1|localhost)(?::[0-9]+)?/(?:[A-Za-z0-9._-]+/)*$", docs_url)
(preview_url ||
 occursin(r"^https://[A-Za-z0-9.-]+(?::[0-9]+)?/(?:[A-Za-z0-9._-]+/)*$", docs_url)) ||
    error("PERFCHECKER_DOCS_URL must be an HTTPS deployment URL ending in /")
docs_base = get(ENV, "PERFCHECKER_DOCS_BASE", "/")
occursin(r"^/(?:[A-Za-z0-9._-]+/)*$", docs_base) ||
    error("Invalid PERFCHECKER_DOCS_BASE")
docs_version = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))["version"]
docs_channel = get(ENV, "PERFCHECKER_DOCS_CHANNEL",
    endswith(docs_base, "/dev/") ? "dev" : docs_base == "/" ? "stable" : "version")
docs_channel in ("dev", "stable", "version") || error("Invalid documentation channel")
docs_sftp = get(ENV, "PERFCHECKER_DOCS_HOSTING",
    startswith(docs_url, "https://perfchecker.mirageinteractive.fr/") ? "sftp" : "github") ==
            "sftp"
build_directory = abspath(joinpath(
    @__DIR__, get(ENV, "PERFCHECKER_DOCS_BUILD_DIR", "build")))
ENV["PERFCHECKER_DOCS_URL"] = docs_url
ENV["PERFCHECKER_DOCS_BASE"] = docs_base
ENV["PERFCHECKER_DOCS_VERSION"] = docs_version
ENV["PERFCHECKER_DOCS_CHANNEL"] = docs_channel
ENV["PERFCHECKER_DOCS_HOSTING"] = docs_sftp ? "sftp" : "github"

source_root = normpath(joinpath(@__DIR__, ".."))
source_revision = strip(read(`git -C $source_root rev-parse HEAD`, String))
optional_api = v"1.0.1" <= VersionNumber(docs_version) < v"2.0.0"
if optional_api
    include("optional-api/assemble.jl")
    # Reject missing/mixed exports before starting the main Documenter build.
    OptionalAPIAssembly.validate_optional_exports(source_root, source_revision)
end
source_remote = Documenter.Remotes.GitHub("Mirage-Interactive-Fr", "PerfChecker.jl")
DocMeta.setdocmeta!(PerfChecker, :DocTestSetup, :(using PerfChecker); recursive = true)

makedocs(;
    modules = [PerfChecker],
    build = build_directory,
    authors = "PerfChecker contributors",
    remotes = Dict(source_root => (source_remote, source_revision)),
    sitename = "PerfChecker.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        build_vitepress = false,
        sidebar_drawer = true,
        repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
        devurl = "dev",
        devbranch = "main",
        deploy_url = docs_url,
        description = "Deep, reproducible performance testing for Julia packages and software suites"
    ),
    checkdocs = :all,
    pages = [
        "Manual" => [
            "1. Your first comparison" => "guide/overview.md",
            "2. Investigate a change" => "tutorials/comparisons.md",
            "3. Suites and CI" => "software-suites.md",
            "Worker lifetime" => "worker-lifecycle.md",
            "Architecture" => "architecture-roadmap.md",
            "Contributing" => "contributing/index.md"
        ],
        "Examples" => [
            "Bibliography" => "tutorials/bibliography.md",
            "DataStructures" => "real-packages/datastructures.md",
            "Oxygen" => "real-packages/oxygen.md"
        ],
        "Interfaces" => [
            "VS Code" => "interfaces/vscode.md",
            "Web (Oxygen)" => "interfaces/web-studio.md",
            "Pluto" => "interfaces/pluto.md",
            "REPL" => "interfaces/repl.md",
            "Makie" => "interfaces/visualization.md",
            "Documenter" => "interfaces/documentation.md",
            "Tachikoma" => "interfaces/tachikoma.md"
        ],
        "Tools" => [
            "Timing" => [
                "BenchmarkTools" => "tools/benchmarktools.md",
                "Chairmarks" => "tools/chairmarks.md",
                "TestItemRunner" => "tools/testitemrunner.md"
            ],
            "Profiles" => [
                "CPU profile" => "tools/cpu-profile.md",
                "Wall profile" => "tools/wall-profile.md",
                "Allocation profile" => "tools/allocation-profile.md",
                "Line allocations" => "tools/line-allocations.md",
                "PProf" => "tools/pprof.md",
                "FlameGraphs" => "tools/flamegraphs.md"
            ],
            "Diagnostics" => [
                "JET" => "tools/jet.md",
                "AllocCheck" => "tools/alloccheck.md",
                "SnoopCompile" => "tools/snoopcompile.md",
                "Latency" => "tools/latency.md",
                "GC" => "tools/gc.md",
                "Memory" => "tools/memory.md",
                "Locks" => "tools/locks.md",
                "Aqua" => "tools/aqua.md",
                "Heap snapshot" => "tools/heap-snapshot.md"
            ],
            "Workloads and results" => [
                "DrWatson" => "tools/drwatson.md",
                "PropCheck" => "tools/propcheck.md",
                "Supposition" => "tools/supposition.md",
                "Scenarios" => "tools/scenarios.md",
                "Saved results" => "tools/results.md",
                "Command line" => "tools/cli.md",
                "Network" => "tools/network.md",
                "Machine profiles" => "tools/machine.md",
                "Preferences" => "tools/preferences.md",
                "PkgEval" => "tools/pkgeval.md",
                "Julia runtimes" => "tools/julia-runtimes.md"
            ],
            "Native tools" => [
                "Memcheck" => "tools/memcheck.md",
                "Callgrind" => "tools/callgrind.md",
                "Massif" => "tools/massif.md",
                "Cachegrind" => "tools/cachegrind.md",
                "heaptrack" => "tools/heaptrack.md",
                "Linux perf" => "tools/linux-perf.md",
                "VTune" => "tools/vtune.md",
                "LinuxPerf companion" => "tools/linuxperf.md",
                "LIKWID" => "tools/likwid.md"
            ]
        ],
        "Agentic workflows" => [
            "Connect an MCP tool" => "agentic/mcp.md",
            "Advice → implementation" => "agentic/advice.md",
            "Providers" => "agentic/providers.md"
        ],
        "API" => [
            "Public API" => "reference/public-api.md",
            "Full API" => "reference/api.md",
            "Companion APIs" => "reference/optional-api.md"
        ]
    ],
    warnonly = false
)

markdown = joinpath(build_directory, ".documenter")
if optional_api
    OptionalAPIAssembly.assemble_optional_api(source_root, markdown, source_revision)
end

# Use the system Node runtime on both platforms. DocumenterVitepress's bundled
# Node 20.12 skips the Windows build and is too old for the current Vite version.
npm = Sys.iswindows() ? `cmd /d /c npm.cmd` : `npm`
run(Cmd(`$npm ci --no-audit --no-fund`; dir = @__DIR__))
site = joinpath(build_directory, "site")
run(Cmd(`$npm exec -- vitepress build $markdown --outDir $site`; dir = @__DIR__))
isfile(joinpath(site, "index.html")) || error("VitePress did not produce the site")

# Standalone exports include preview metadata. The SFTP publisher replaces the
# catalogue with the channels actually available on the destination server.
if docs_sftp
    current = docs_channel == "dev" ? "dev" : "v" * docs_version
    catalogue = docs_channel == "dev" ? "[\"dev\"]" : "[$(repr(current)), \"dev\"]"
    write(joinpath(site, "versions.js"),
        "var DOC_VERSIONS = $catalogue;\n" *
        "var DOC_VERSION_URLS = {$(repr(current)): $(repr(docs_base)), \"dev\": \"/dev/\"};\n")
    write(joinpath(site, "siteinfo.js"),
        "var DOCUMENTER_CURRENT_VERSION = $(repr(current));\n" *
        "var DOCUMENTER_IS_DEV_VERSION = $(docs_channel == "dev");\n")
    revision = strip(read(`git -C $(@__DIR__) rev-parse HEAD`, String))
    info = ["schema" => "perfchecker-doc-export/1", "version" => docs_version,
        "channel" => docs_channel, "base" => docs_base, "url" => docs_url,
        "revision" => revision]
    renderer_directory = "packages/PerfCheckerMakie"
    renderer_version = TOML.parsefile(joinpath(source_root,
        renderer_directory, "Project.toml"))["version"]
    renderer_tree = strip(read(
        `git -C $source_root rev-parse $(revision * ":" * renderer_directory)`, String))
    renderer_tag = get(ENV, "PERFCHECKER_DOCS_RENDERER_TAG", "")
    local_preview && !isempty(renderer_tag) &&
        error("A local working-tree preview cannot claim a published renderer tag")
    renderer_revision = get(ENV, "PERFCHECKER_DOCS_RENDERER_REVISION", revision)
    if !isempty(renderer_tag)
        renderer_tag == "PerfCheckerMakie-v" * renderer_version ||
            error("Documentation renderer tag differs from its package version")
        get(ENV, "PERFCHECKER_DOCS_RENDERER_TREE", "") == renderer_tree ||
            error("Documentation renderer tree differs from its validated companion tag")
    end
    append!(info,
        ["renderer_name" => "PerfCheckerMakie", "renderer_version" => renderer_version,
            "renderer_revision" => renderer_revision, "renderer_tree" => renderer_tree])
    isempty(renderer_tag) || push!(info, "renderer_tag" => renderer_tag)
    local_preview && append!(info,
        ["source_state" => "local-working-tree",
            "source_semantics" => "Revision and tree identify the base commit; preview uses current local sources",
            "working_tree_diff_sha256" => bytes2hex(sha256(read(
                `git -C $source_root diff HEAD -- Project.toml src packages`)))])
    write(joinpath(site, "build-info.json"),
        "{\n" * join([repr(key) * ": " * repr(value) for (key, value) in info], ",\n") *
        "\n}\n")
end

# Development publishing is separate; stable publishing requires the full collection.
