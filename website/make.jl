using Documenter, DocumenterVitepress

using PerfChecker

include("compat.jl")

makedocs(;
    modules = [PerfChecker],
    authors = "PerfChecker contributors",
    repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    sitename = "PerfChecker.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        build_vitepress = false,
        sidebar_drawer = true,
        repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
        devurl = "dev",
        devbranch = "release/v1.0.0-rc1",
        deploy_url = "https://mirage-interactive-fr.github.io/PerfChecker/",
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
            "Run checks in CI" => "tutorials/ci.md",
        ],
        "Examples" => [
            "Choose an example" => "real-packages/index.md",
            "Bibliography" => "tutorials/bibliography.md",
            "DataStructures" => "real-packages/datastructures.md",
            "Oxygen" => "real-packages/oxygen.md",
            "Interface recipes" => "real-packages/interfaces.md",
            "Tool recipes" => "real-packages/extensions.md",
        ],
        "Interfaces" => [
            "Choose an interface" => "interfaces/packages.md",
            "VS Code" => "interfaces/vscode.md",
            "Web Studio" => "interfaces/web-studio.md",
            "REPL and Pluto" => "interfaces/repl-pluto.md",
            "Plots with Makie" => "interfaces/visualization.md",
            "Documenter" => "interfaces/documentation.md",
        ],
        "Further topics" => [
            "Additional measurements" => [
                "Julia and native profiling" => "native-profiling.md",
                "Process memory" => "process-memory.md",
                "Network traffic" => "network-measurement.md",
            ],
            "Larger experiments" => [
                "Choose an experiment" => "experiments.md",
                "Shared scenarios" => "shared-scenarios.md",
                "Julia runtimes" => "tutorials/julia-runtimes.md",
                "Machine calibration" => "machine-transfer.md",
            ],
            "Remote execution" => [
                "Automation workflows" => "operations/overview.md",
                "Controllers and workers" => "operations/hosted.md",
            ],
            "Optional advisors" => [
                "How advisors work" => "advisors.md",
                "Provider setup" => "advisor-ui.md",
                "MCP tools" => "mcp-advisor.md",
                "Specialized models" => "model-specialization.md",
            ],
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
            "Extensions and providers" => "reference/extensions.md",
        ],
        "Contributing" => [
            "Architecture" => "architecture-roadmap.md",
            "Collection qualification" => "reference/qualification.md",
            "Documentation" => "contributing/documentation.md",
            "Contribute an example" => "real-packages/contributing.md",
        ],
    ],
    warnonly = false
)

# Use the system Node runtime on both platforms. DocumenterVitepress's bundled
# Node 20.12 skips the Windows build and is too old for the current Vite version.
npm = Sys.iswindows() ? `cmd /d /c npm.cmd` : `npm`
run(Cmd(`$npm install --no-audit --no-fund`; dir = @__DIR__))
site = joinpath(@__DIR__, "build", "site")
run(Cmd(`$npm exec -- vitepress build build/.documenter --outDir $site`; dir = @__DIR__))
isfile(joinpath(site, "index.html")) || error("VitePress did not produce the site")

# Publishing is separate from building and does not depend on package qualification.
