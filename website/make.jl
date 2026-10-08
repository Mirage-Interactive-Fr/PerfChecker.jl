using Documenter, DocumenterVitepress, TOML

using PerfChecker

include("compat.jl")

docs_url = get(ENV, "PERFCHECKER_DOCS_URL", "https://perfchecker.mirageinteractive.fr/")
occursin(r"^https://[A-Za-z0-9.-]+(?::[0-9]+)?/(?:[A-Za-z0-9._-]+/)*$", docs_url) ||
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
source_remote = Documenter.Remotes.GitHub("Mirage-Interactive-Fr", "PerfChecker.jl")

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
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Introduction" => "guide/overview.md",
            "Installation" => "guide/installation.md",
            "Quickstart: measure a test" => "guide/first-check.md",
            "Measure an operation" => "tutorials/quick-tour.md",
            "Understand the result" => "guide/understanding-measurements.md",
            "Group workloads in a suite" => "suites-and-comparisons.md",
            "Define a suite" => "software-suites.md",
            "Compare two versions" => "tutorials/comparisons.md",
            "Investigate a change" => "guide/investigate.md",
            "Run checks in CI" => "tutorials/ci.md"
        ],
        "Examples" => [
            "Choose an example" => "real-packages/index.md",
            "Bibliography" => "tutorials/bibliography.md",
            "DataStructures" => "real-packages/datastructures.md",
            "Oxygen" => "real-packages/oxygen.md",
            "Interface recipes" => "real-packages/interfaces.md",
            "Tool recipes" => "real-packages/extensions.md"
        ],
        "Interfaces" => [
            "Choose an interface" => "interfaces/packages.md",
            "VS Code" => "interfaces/vscode.md",
            "VS Code configuration" => "interfaces/vscode-configuration.md",
            "Plots, notebooks and Julia tools" => "interfaces/vscode-workflows.md",
            "Web interface (Oxygen)" => "interfaces/web-studio.md",
            "REPL and Pluto" => "interfaces/repl-pluto.md",
            "Plots with Makie" => "interfaces/visualization.md",
            "Documenter" => "interfaces/documentation.md"
        ],
        "Further topics" => [
            "Additional measurements" => [
                "Julia and native profiling" => "native-profiling.md",
                "Process memory" => "process-memory.md",
                "Network traffic" => "network-measurement.md"
            ],
            "Larger experiments" => [
                "Choose an experiment" => "experiments.md",
                "Shared scenarios" => "shared-scenarios.md",
                "Julia runtimes" => "tutorials/julia-runtimes.md",
                "Machine calibration" => "machine-transfer.md"
            ],
            "Remote execution" => [
                "Automation workflows" => "operations/overview.md",
                "Controllers and workers" => "operations/hosted.md"
            ],
            "Optional advisors" => [
                "How advisors work" => "advisors.md",
                "Provider setup" => "advisor-ui.md",
                "MCP advice and implementation" => "mcp-advisor.md",
                "Specialized models" => "model-specialization.md"
            ]
        ],
        "Reference" => [
            "Reference index" => "reference/index.md",
            "Julia API" => "reference/api.md",
            "TestItems and tags" => "test-items.md",
            "Collectors" => "reference/checks.md",
            "Tool catalogue" => "tool-catalog.md",
            "Comparison configuration" => "reference/comparisons.md",
            "Measurement definitions" => "measurement-model.md",
            "Native dependencies" => "reference/native-external.md",
            "Run bundles" => "reference/run-bundles.md",
            "Report queries" => "report-queries.md",
            "Command line" => "reference/cli.md",
            "Extensions and providers" => "reference/extensions.md"
        ],
        "Contributing" => [
            "Architecture" => "architecture-roadmap.md",
            "Collection qualification" => "reference/qualification.md",
            "Documentation" => "contributing/documentation.md",
            "Contribute an example" => "real-packages/contributing.md"
        ]
    ],
    warnonly = false
)

# Use the system Node runtime on both platforms. DocumenterVitepress's bundled
# Node 20.12 skips the Windows build and is too old for the current Vite version.
npm = Sys.iswindows() ? `cmd /d /c npm.cmd` : `npm`
run(Cmd(`$npm ci --no-audit --no-fund`; dir = @__DIR__))
site = joinpath(build_directory, "site")
markdown = joinpath(build_directory, ".documenter")
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
    write(joinpath(site, "build-info.json"),
        "{\n" * join([repr(key) * ": " * repr(value) for (key, value) in info], ",\n") *
        "\n}\n")
end

# Development publishing is separate; stable publishing requires the full collection.
