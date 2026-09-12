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
        "Get started" => [
            "Overview" => "guide/overview.md",
            "Installation" => "guide/installation.md",
            "Your first result" => "guide/first-check.md",
            "Short Bibliography tutorial" => "tutorials/quick-tour.md"
        ],
        "Suites and comparisons" => [
            "What is a suite?" => "suites-and-comparisons.md",
            "Existing test items" => "test-items.md",
            "Software suites" => "software-suites.md",
            "Compare versions and revisions" => "tutorials/comparisons.md",
            "Bibliography walkthrough" => "tutorials/bibliography.md"
        ],
        "Measurements" => [
            "Understand the measurements" => "guide/understanding-measurements.md",
            "Check catalog" => "reference/checks.md",
            "Tool integration catalogue" => "tool-catalog.md",
            "Julia and native profiling review" => "native-profiling.md",
            "Process and external memory" => "process-memory.md",
            "Network measurement" => "network-measurement.md",
            "Native and external dependencies" => "reference/native-external.md"
        ],
        "Interfaces" => [
            "Choose an interface" => "interfaces/packages.md",
            "VS Code" => "interfaces/vscode.md",
            "Oxygen web studio" => "interfaces/web-studio.md",
            "REPL and Pluto" => "interfaces/repl-pluto.md",
            "Makie and interactive plots" => "interfaces/visualization.md",
            "Documenter integration" => "interfaces/documentation.md"
        ],
        "Automation and hosting" => [
            "Choose an automation workflow" => "operations/overview.md",
            "CI/CD" => "tutorials/ci.md",
            "Qualified collections" => "reference/qualification.md",
            "Hosted controller and agents" => "operations/hosted.md"
        ],
        "Advanced experiments" => [
            "Choose an experiment" => "experiments.md",
            "Shared workload contracts" => "shared-scenarios.md",
            "Julia RC and nightly" => "tutorials/julia-runtimes.md",
            "Machine calibration" => "machine-transfer.md"
        ],
        "Optional advice" => [
            "Optional models and investigations" => "advisors.md",
            "MCP advice tools" => "mcp-advisor.md",
            "Advisor setup and models" => "advisor-ui.md",
            "Specializing a local model" => "model-specialization.md"
        ],
        "Contracts and API" => [
            "How to use this reference" => "reference/index.md",
            "Measurement model" => "measurement-model.md",
            "Run bundles" => "reference/run-bundles.md",
            "Queries and documentation blocks" => "report-queries.md",
            "Command line" => "reference/cli.md",
            "Extensions and providers" => "reference/extensions.md",
            "Julia API" => "reference/api.md"
        ],
        "Contribute" => [
            "Architecture" => "architecture-roadmap.md",
            "Documentation guide" => "contributing/documentation.md"
        ]
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
