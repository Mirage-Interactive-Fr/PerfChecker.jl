module PkgEvalSource

using UUIDs

const PACKAGE_NAME = "PerfChecker"
const PACKAGE_UUID = "6309bf6b-a531-4b08-891e-8ee981e5c424"
const PACKAGE_REPOSITORY = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl.git"

"""
Record an explicit package-image policy, Julia arguments and sandbox budget.

`upstream` passes no override to the pinned controller. `yes` permits native
package-image generation during precompilation and testing; it does not enable
PkgEval's shared result or compilation cache. The budget defaults to 45 minutes;
90 minutes is a separate explicit configuration of the complete evaluation.
"""
function evaluation_options(package_images; time_limit_minutes = "45")
    package_images isa AbstractString && package_images in ("upstream", "yes") ||
        throw(ArgumentError("Package images must be upstream or yes"))
    time_limit_minutes isa AbstractString && time_limit_minutes in ("45", "90") ||
        throw(ArgumentError("Evaluation budget must be 45 or 90 minutes"))
    minutes = parse(Int, time_limit_minutes)
    arguments = package_images == "yes" ? ["--pkgimages=yes"] : String[]
    return Dict{String, Any}("package_images" => String(package_images),
        "julia_args" => arguments, "time_limit_minutes" => minutes,
        "time_limit_seconds" => 60 * minutes)
end

"""Validate saved compilation and budget settings before passing them to PkgEval."""
function evaluation_arguments(request)
    minutes, seconds = request["time_limit_minutes"], request["time_limit_seconds"]
    minutes isa Integer && !(minutes isa Bool) &&
        seconds isa Integer && !(seconds isa Bool) ||
        throw(ArgumentError("Recorded evaluation budgets must be integer counts"))
    options = evaluation_options(
        request["package_images"]; time_limit_minutes = string(minutes))
    all(request[key] == options[key]
    for key in ("julia_args", "time_limit_minutes", "time_limit_seconds")) ||
        throw(ArgumentError("Recorded evaluation settings do not match the selected policy"))
    return (;
        julia_args = options["julia_args"], time_limit = options["time_limit_seconds"])
end

function checked_sha(value, label)
    value isa AbstractString && occursin(r"^[0-9a-f]{40}$", value) ||
        throw(ArgumentError("$label must be an exact lowercase 40-character Git SHA"))
    return String(value)
end

"""Select an immutable, non-yanked General entry; never substitute a Git checkout."""
function registered_source(versions; package_version = "", expected_tree = "")
    available = [VersionNumber(key)
                 for (key, info) in versions
                 if !get(info, "yanked", false)]
    isempty(available) &&
        throw(ArgumentError("No non-yanked PerfChecker version is registered"))
    version = isempty(package_version) ? maximum(available) : VersionNumber(package_version)
    info = get(versions, string(version), nothing)
    info === nothing &&
        throw(ArgumentError("PerfChecker $version is not registered at this General commit"))
    get(info, "yanked", false) && throw(ArgumentError("PerfChecker $version is yanked"))
    tree = checked_sha(info["git-tree-sha1"], "Registered tree")
    isempty(expected_tree) ||
        tree == checked_sha(expected_tree, "Expected registered tree") ||
        throw(ArgumentError("Registered tree does not match the requested tree"))
    return Dict("source_kind" => "registered", "package" => PACKAGE_NAME,
        "uuid" => PACKAGE_UUID, "version" => string(version), "registered_tree" => tree)
end

"""
Select a Git candidate from the fixed PerfChecker repository's commit and Project metadata.

The request records that commit's declared version and tree. These fields identify
the candidate; they do not claim that General contains it or that PkgEval passed.
"""
function candidate_source(revision, commit, project;
        package_version = "", expected_tree = "")
    isempty(package_version) && isempty(expected_tree) ||
        throw(ArgumentError("Git candidates do not accept registered version/tree selectors"))
    sha = checked_sha(revision, "Candidate revision")
    checked_sha(commit["sha"], "Resolved candidate commit") == sha ||
        throw(ArgumentError("Resolved candidate commit does not match the requested revision"))
    tree = checked_sha(commit["tree"], "Candidate tree")
    project["name"] == PACKAGE_NAME || throw(ArgumentError("Candidate is not PerfChecker"))
    project["uuid"] == PACKAGE_UUID ||
        throw(ArgumentError("Candidate UUID is not PerfChecker's UUID"))
    version = VersionNumber(project["version"])
    return Dict("source_kind" => "git_candidate", "package" => PACKAGE_NAME,
        "uuid" => PACKAGE_UUID, "version" => string(version),
        "candidate_revision" => sha, "candidate_tree" => tree,
        "source_repository" => PACKAGE_REPOSITORY)
end

"""Return the actual PkgEval.Package keyword arguments for the selected source."""
function package_arguments(request)
    request["package"] == PACKAGE_NAME && request["uuid"] == PACKAGE_UUID ||
        throw(ArgumentError("Invalid selected package identity"))
    identity = (; name = PACKAGE_NAME, uuid = UUID(PACKAGE_UUID))
    if request["source_kind"] == "registered"
        checked_sha(request["registered_tree"], "Registered tree")
        return (; identity..., version = VersionNumber(request["version"]))
    elseif request["source_kind"] == "git_candidate"
        request["source_repository"] == PACKAGE_REPOSITORY ||
            throw(ArgumentError("Git candidates must use the PerfChecker repository"))
        checked_sha(request["candidate_tree"], "Candidate tree")
        VersionNumber(request["version"])
        return (; identity..., url = PACKAGE_REPOSITORY,
            rev = checked_sha(request["candidate_revision"], "Candidate revision"))
    end
    throw(ArgumentError("Unknown PkgEval source kind"))
end

end
