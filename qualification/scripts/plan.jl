using PerfCheckerQualification, TOML

root = normpath(joinpath(@__DIR__, "../.."))
collection = load_collection(joinpath(root, "qualification/collection.toml"))
revision = strip(read(`git -C $root rev-parse HEAD`, String))
full = "--full" in ARGS
paths = String[]
base = get(ENV, "PERFCHECKER_BASE_SHA", "")
if !full && !isempty(base)
    occursin(r"^[0-9a-f]{40}$", base) || error("Invalid base SHA")
    # Both names of a rename must participate in impact analysis.
    append!(paths,
        split(read(`git -C $root diff --name-only --no-renames $base $revision`, String),
            '\n'; keepempty = false))
elseif !full
    full = true
end
changed = filter(!isempty, split(get(ENV, "PERFCHECKER_CHANGED_COMPONENTS", ""), ','))
profile = get(ENV, "PERFCHECKER_QUALIFICATION_PROFILE", "extended")
plan = qualification_plan(
    collection, paths; revision, full, changed_components = changed, profile)
destination = get(ENV, "PERFCHECKER_PLAN", joinpath(root, ".qualification/plan.toml"))
write_toml(destination, plan)
println(json(Dict("include" => plan["lanes"])))
if haskey(ENV, "GITHUB_OUTPUT")
    open(ENV["GITHUB_OUTPUT"], "a") do io
        println(io, "matrix=", json(Dict("include" => plan["lanes"])))
        println(io, "full=", plan["full"])
        println(io, "vscode_repository=", collection["sources"]["vscode"]["repository"])
        println(io, "vscode_revision=", collection["sources"]["vscode"]["revision"])
    end
end
