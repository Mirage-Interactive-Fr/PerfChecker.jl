module PerfCheckerQualification

using SHA, TOML, UUIDs

export load_collection, impacted_components, qualification_plan, validate_receipts,
       write_toml, file_digest, tree_digest, json

"Load and validate the component graph, suite matrix and immutable external revisions."
function load_collection(path::AbstractString)
    collection = TOML.parsefile(path)
    get(collection, "schema", "") == "perfchecker-collection/1" ||
        error("Unknown collection schema")
    components, suites = collection["components"], collection["suites"]
    for (name, component) in components
        all(haskey(components, dep) for dep in component["depends"]) ||
            error("Unknown dependency of $name")
        all(haskey(suites, suite) for suite in component["suites"]) ||
            error("Unknown suite of $name")
    end
    visiting, visited = Set{String}(), Set{String}()
    function visit(name)
        name in visited && return
        name in visiting && error("Cyclic component dependencies")
        push!(visiting, name)
        foreach(visit, components[name]["depends"])
        delete!(visiting, name)
        push!(visited, name)
    end
    foreach(visit, keys(components))
    for source in values(get(collection, "sources", Dict()))
        occursin(r"^[0-9a-f]{40}$", source["revision"]) ||
            error("External source requires a full commit SHA")
        occursin(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", source["repository"]) ||
            error("Invalid repository")
    end
    return collection
end

"""
    impacted_components(collection, paths; changed_components=[], full=false)

Select changed components and their transitive consumers. The most specific path
owns a file. Unknown paths conservatively select the entire collection. A change
to the shared contracts or core also requires all components. Explicit component
names support candidates arriving from a separate repository; unknown names fail.
"""
function impacted_components(collection, paths; changed_components = String[], full = false)
    components = collection["components"]
    all(haskey(components, name) for name in changed_components) ||
        error("Unknown changed component")
    full && return sort!(collect(keys(components)))
    selected = Set{String}(changed_components)
    for rawpath in paths
        path = replace(String(rawpath), '\\' => '/')
        matches = [(length(prefix), name) for (name, component) in components
                   for prefix in component["paths"]
                   if
                   (endswith(prefix, "/") ? startswith(path, prefix) : path == prefix)]
        isempty(matches) && return sort!(collect(keys(components)))
        specificity = maximum(first, matches)
        union!(selected, [name for (size, name) in matches if size == specificity])
    end
    !isempty(intersect(selected, Set(["core", "contracts"]))) &&
        return sort!(collect(keys(components)))
    while true
        previous = length(selected)
        for (name, component) in components
            any(in(selected), component["depends"]) && push!(selected, name)
        end
        length(selected) == previous && break
    end
    return sort!(collect(selected))
end

"""
    qualification_plan(collection, paths; revision, full=false, changed_components=[])

Create an explicit OS/Julia matrix. Every nonempty selection runs shared contracts.
The plan is bound to the source revision and collection configuration. A partial
plan may pass but never qualifies a release. The routine profile checks current
dependencies and the core's minimum Julia; the documentation profile builds only
the website. Development documentation can publish after its own checks.
"""
function qualification_plan(collection, paths; revision, full = false,
        changed_components = String[], campaign = string(uuid4()), profile = "extended")
    profile in ("extended", "routine", "documentation") ||
        error("Unknown qualification profile")
    occursin(r"^[0-9a-f]{40}$", revision) || error("A full source commit SHA is required")
    impacted = impacted_components(collection, paths; changed_components, full)
    suites = Set{String}()
    isempty(impacted) || push!(suites, "style")
    for name in impacted
        union!(suites, collection["components"][name]["suites"])
    end
    isempty(suites) || push!(suites, "contracts")
    lanes = [Dict("id" => "$suite-$os-$julia", "suite" => suite,
                 "os" => os, "julia" => julia)
             for suite in sort!(collect(suites))
             for os in collection["suites"][suite]["oses"]
             for julia in collection["suites"][suite]["julias"]]
    if profile == "routine"
        filter!(lanes) do lane
            suite = lane["suite"]
            suite in ("docs", "legacy_interfaces", "legacy_protocol",
                "advisor_http1", "advisor_http2") && return false
            return (lane["os"] == "ubuntu-latest" && lane["julia"] == "1") ||
                   (suite == "core" &&
                    (lane["os"] == "ubuntu-latest" || lane["julia"] == "1"))
        end
    elseif profile == "documentation"
        filter!(lane -> lane["suite"] == "docs", lanes)
    end
    plan = Dict{String, Any}("schema" => "perfchecker-qualification-plan/1",
        "revision" => revision, "campaign" => campaign, "components" => impacted, "lanes" => lanes,
        "full" => profile == "extended" &&
                  Set(impacted) == Set(keys(collection["components"])),
        "profile" => profile,
        "collection_sha256" => bytes2hex(sha256(json(collection))),
        "sources" => get(collection, "sources", Dict()))
    plan["id"] = bytes2hex(sha256(json(plan)))
    return plan
end

"SHA-256 of file bytes; used for manifests, logs and source-independent artifacts."
file_digest(path::AbstractString) = bytes2hex(open(sha256, path))

"Hash a sorted relative file inventory, including names and contents; reject symbolic links."
function tree_digest(root::AbstractString)
    entries = String[]
    for (directory, subdirs, files) in walkdir(root)
        any(islink(joinpath(directory, name)) for name in [subdirs; files]) &&
            error("Symbolic link in evidence")
        for name in files
            path = joinpath(directory, name)
            push!(entries,
                replace(relpath(path, root), '\\' => '/') * "\0" * file_digest(path))
        end
    end
    return bytes2hex(sha256(join(sort!(entries), "\n")))
end

"Write a TOML artifact without changing the caller's working directory."
function write_toml(path::AbstractString, data)
    mkpath(dirname(abspath(path)))
    open(io -> TOML.print(io, data; sorted = true), path, "w")
    return path
end

"""
    validate_receipts(plan, receipts; require_full=false)

Reject missing, duplicate, unexpected, failed or stale lanes. Each receipt must
identify its actual runtime, source state and captured environment. Full publication
also requires clean checkouts. This checks evidence consistency, not authenticity:
CI must retrieve receipts from trusted jobs of the same run, never from a PR payload.
"""
function validate_receipts(plan, receipts; require_full = false)
    require_full && !plan["full"] &&
        error("Partial qualification cannot qualify a release")
    expected = Dict(lane["id"] => lane for lane in plan["lanes"])
    isempty(expected) && error("Empty qualification cannot pass")
    seen = Set{String}()
    for receipt in receipts
        get(receipt, "schema", "") == "perfchecker-qualification-receipt/1" ||
            error("Unknown receipt schema")
        id = receipt["lane"]
        haskey(expected, id) || error("Unexpected lane: $id")
        id in seen && error("Duplicate lane: $id")
        push!(seen, id)
        receipt["plan_id"] == plan["id"] || error("Stale plan in $id")
        receipt["revision"] == plan["revision"] || error("Wrong revision in $id")
        receipt["status"] == "passed" || error("Unsuccessful lane: $id")
        receipt["os"] == expected[id]["os"] || error("Wrong OS in $id")
        runtime = VersionNumber(receipt["runtime"])
        requested = VersionNumber(expected[id]["julia"])
        runtime.major == requested.major || error("Wrong Julia major in $id")
        occursin('.', expected[id]["julia"]) && runtime.minor != requested.minor &&
            error("Wrong Julia minor in $id")
        isempty(receipt["environments"]) && error("Missing environment evidence in $id")
        require_full && receipt["dirty"] &&
            error("Dirty source cannot qualify a release")
        if expected[id]["suite"] == "vscode"
            receipt["external_revision"] == plan["sources"]["vscode"]["revision"] ||
                error("Wrong VS Code revision")
        end
    end
    seen == Set(keys(expected)) ||
        error("Missing lanes: $(join(sort!(collect(setdiff(keys(expected), seen))), ", "))")
    return Dict("schema" => "perfchecker-qualified-collection/1", "plan_id" => plan["id"],
        "revision" => plan["revision"], "full" => plan["full"],
        "publishable" => plan["full"] && all(!r["dirty"] for r in receipts),
        "sources" => plan["sources"], "receipts" => sort(receipts; by = r -> r["lane"]))
end

# Small deterministic JSON writer keeps the qualification controller stdlib-only.
json(x::Bool) = x ? "true" : "false"
json(x::Integer) = string(x)
function json(x::AbstractString)
    "\"" *
    join(c == '"' ? "\\\"" :
         c == '\\' ? "\\\\" :
         Int(c) < 0x20 ? "\\u" * string(Int(c); base = 16, pad = 4) : string(c)
    for c in x) * "\""
end
json(x::AbstractVector) = "[" * join(json.(x), ",") * "]"
function json(x::AbstractDict)
    "{" *
    join(
        (json(string(k)) * ":" * json(x[k]) for k in sort!(collect(keys(x)); by = string)),
        ",") * "}"
end

end
