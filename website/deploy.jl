using Documenter
using TOML

site = joinpath(@__DIR__, "build", "site")
isfile(joinpath(site, "index.html")) || error("Build the documentation before publishing")

release_tag = get(ENV, "PERFCHECKER_DOCS_RELEASE_TAG", "")
deploy_config = if isempty(release_tag)
    Documenter.auto_detect_deploy_system()
else
    # The release workflow has created and fetched this real tag after full
    # qualification. Give Documenter its documented deployment configuration
    # without changing the workflow's source identity or rebuilding its site.
    get(ENV, "GITHUB_ACTIONS", "") == "true" || error("Stable deployment requires CI")
    get(ENV, "GITHUB_EVENT_NAME", "") == "workflow_dispatch" ||
        error("Stable deployment requires the explicit release workflow")
    get(ENV, "GITHUB_REF", "") == "refs/heads/main" ||
        error("Stable deployment requires the qualified main revision")
    root = dirname(@__DIR__)
    version = VersionNumber(TOML.parsefile(joinpath(root, "Project.toml"))["version"])
    isempty(version.prerelease) && isempty(version.build) ||
        error("Expected a stable version")
    release_tag == "v$version" || error("Tag differs from the package version")
    revision = strip(read(`git -C $root rev-parse HEAD`, String))
    tag_commit = release_tag * "^{commit}"
    tag_revision = strip(read(`git -C $root rev-parse $tag_commit`, String))
    tag_revision == revision || error("Stable tag differs from the checked-out source")
    collection = TOML.parsefile(joinpath(root, ".qualification/collection.toml"))
    collection["full"] && collection["publishable"] ||
        error("Complete clean qualification required")
    collection["revision"] == revision ||
        error("Qualified collection differs from the source")
    Documenter.GitHubActions(ENV["GITHUB_REPOSITORY"], ENV["GITHUB_EVENT_NAME"],
        "refs/tags/$release_tag")
end

deploydocs(; root = @__DIR__, target = "build/site",
    dirname = "PerfChecker",
    repo = "github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    deploy_repo = "github.com/Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io",
    devbranch = "main", versions = ["stable" => "v^", "v#.#", "dev" => "dev"],
    deploy_config, push_preview = false)
