using Documenter

site = joinpath(@__DIR__, "build", "site")
isfile(joinpath(site, "index.html")) || error("Build the documentation before publishing")

deploydocs(; root = @__DIR__, target = "build/site",
    dirname = "PerfChecker",
    repo = "github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    deploy_repo = "github.com/Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io",
    devbranch = "release/v1.0.0-rc1", versions = ["dev" => "dev", "v#.#", "stable" => "v^"],
    push_preview = false)
