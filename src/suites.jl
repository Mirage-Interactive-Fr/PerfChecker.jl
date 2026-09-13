const SuiteVersion = Union{VersionNumber, Symbol, String}

"A named Git branch, tag, or commit evaluated beside releases and the working tree."
struct SuiteCandidate
    label::String
    revision::String
    source::Union{Nothing, String}
    compatibility_version::Union{Nothing, VersionNumber}
    dependencies::Vector{Any}
end

function SuiteCandidate(label::AbstractString, revision::AbstractString;
        source = nothing, compatibility_version = nothing,
        dependencies::AbstractVector = Any[])
    isempty(strip(String(label))) && throw(ArgumentError("candidate label cannot be empty"))
    isempty(strip(String(revision))) &&
        throw(ArgumentError("candidate revision cannot be empty"))
    normalized_source = source === nothing ? nothing : String(source)
    compatibility = compatibility_version === nothing ? nothing :
                    VersionNumber(compatibility_version)
    return SuiteCandidate(String(label), String(revision), normalized_source,
        compatibility, Any[item for item in dependencies])
end

"An exact or grouped reference used to compare several candidate targets."
struct ComparisonPolicy
    id::String
    package::String
    feature::String
    comparison_key::String
    baselines::Vector{String}
    candidates::Vector{String}
    aggregation::Symbol
end

function ComparisonPolicy(id::AbstractString; package::AbstractString = "",
        feature::AbstractString = "", comparison_key::AbstractString = "",
        baselines::AbstractVector{<:AbstractString},
        candidates::AbstractVector{<:AbstractString}, aggregation::Symbol = :median)
    isempty(strip(String(id))) &&
        throw(ArgumentError("comparison policy id cannot be empty"))
    isempty(feature) && isempty(comparison_key) &&
        throw(ArgumentError(
            "comparison policy requires a feature or comparison_key"))
    isempty(baselines) && throw(ArgumentError("comparison policy requires a baseline"))
    isempty(candidates) && throw(ArgumentError("comparison policy requires a candidate"))
    aggregation in (:median, :mean, :minimum, :maximum) || throw(ArgumentError(
        "comparison aggregation must be :median, :mean, :minimum, or :maximum"))
    return ComparisonPolicy(String(id), String(package), String(feature),
        String(comparison_key), unique!(String.(baselines)),
        unique!(String.(candidates)), aggregation)
end

"""
Return the dictionary representation of a ComparisonPolicy, including its baseline/candidate selection and metric limits.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function comparison_policy_dict(policy::ComparisonPolicy)
    return Dict{String, Any}("id" => policy.id, "package" => policy.package,
        "feature" => policy.feature, "comparison_key" => policy.comparison_key,
        "baselines" => policy.baselines, "candidates" => policy.candidates,
        "aggregation" => string(policy.aggregation))
end

"A closed package-version interval with explicit exclusions."
struct VersionWindow
    since::Union{Nothing, VersionNumber}
    until::Union{Nothing, VersionNumber}
    excluded::Set{VersionNumber}
end

function VersionWindow(; since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[])
    lo = since === nothing ? nothing : VersionNumber(since)
    hi = until === nothing ? nothing : VersionNumber(until)
    lo !== nothing && hi !== nothing && lo > hi &&
        throw(ArgumentError("version window starts after it ends"))
    return VersionWindow(lo, hi, Set(excluded))
end

function supports(window::VersionWindow, version::VersionNumber)
    window.since !== nothing && version < window.since && return false
    window.until !== nothing && version > window.until && return false
    return version ∉ window.excluded
end

"One workload implementation over a package-version interval."
struct FeatureVariant
    window::VersionWindow
    entrypoint::String
    comparison_key::String
    options::Dict{Symbol, Any}
end

function FeatureVariant(entrypoint::AbstractString; since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[],
        comparison_key::AbstractString = "", options = Dict{Symbol, Any}())
    path = abspath(String(entrypoint))
    isfile(path) || throw(ArgumentError("feature entrypoint does not exist: $path"))
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol || throw(ArgumentError("variant option keys must be symbols"))
        normalized[key] = value
    end
    return FeatureVariant(VersionWindow(; since, until, excluded), path,
        String(comparison_key), normalized)
end

"A feature-level performance contract."
struct FeatureSpec
    id::Symbol
    workload::Symbol
    description::String
    backend::Symbol
    variants::Vector{FeatureVariant}
    julia_window::VersionWindow
    options::Dict{Symbol, Any}
    probes::Vector{ProbeSpec}
    oracle::Union{Nothing, OracleSpec}
end

function FeatureSpec(id::Symbol; description::AbstractString = "",
        backend::Symbol = :benchmark, variants = nothing, entrypoint = nothing,
        workload = nothing,
        since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[],
        julia_since = nothing, julia_until = nothing,
        julia_excluded::AbstractVector{VersionNumber} = VersionNumber[],
        comparison_key::AbstractString = string(id), options = Dict{Symbol, Any}(),
        probes::AbstractVector{ProbeSpec} = ProbeSpec[], oracle = nothing,
        state_policy::Symbol = :fresh)
    implementations = if variants === nothing
        entrypoint isa AbstractString ||
            throw(ArgumentError("feature $id requires an entrypoint"))
        [FeatureVariant(entrypoint; since, until, excluded, comparison_key)]
    else
        FeatureVariant[variant for variant in variants]
    end
    isempty(implementations) && throw(ArgumentError("feature $id has no variants"))
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol || throw(ArgumentError("feature option keys must be symbols"))
        normalized[key] = value
    end
    state_policy in (:fresh, :reuse) ||
        throw(ArgumentError("state_policy must be :fresh or :reuse"))
    normalized[:state_policy] = get(normalized, :state_policy, state_policy)
    normalized[:state_policy] in (:fresh, :reuse) ||
        throw(ArgumentError("invalid state_policy option"))
    business_feature = workload === nothing ? id : Symbol(workload)
    correctness = oracle === nothing ? nothing :
                  oracle isa OracleSpec ? oracle :
                  throw(ArgumentError("feature oracle must be an OracleSpec or nothing"))
    return FeatureSpec(id, business_feature, String(description), backend, implementations,
        VersionWindow(; since = julia_since, until = julia_until,
            excluded = julia_excluded), normalized, collect(probes), correctness)
end

"Stable business-feature identifier shared by plans, reports, and user interfaces."
workload_id(feature::FeatureSpec) = feature.workload

"All feature measurements owned by one package."
struct PackageSuite
    id::Symbol
    package::String
    worker_environment::String
    source::Union{Nothing, String}
    dev_sources::Vector{String}
    release_pins::Dict{VersionNumber, Vector{Any}}
    versions::Union{Symbol, Vector{VersionNumber}}
    features::Vector{FeatureSpec}
    include_dev::Bool
    candidates::Vector{SuiteCandidate}
end

function PackageSuite(package::AbstractString; id::Symbol = Symbol(package),
        environment = nothing, worker_environment = nothing, source = nothing,
        versions = :all,
        dev_sources::AbstractVector{<:AbstractString} = String[],
        release_pins::AbstractDict = Dict{VersionNumber, Vector{Any}}(),
        features::AbstractVector{FeatureSpec}, include_dev::Bool = true,
        candidates::AbstractVector{SuiteCandidate} = SuiteCandidate[])
    selection = if versions isa Symbol
        versions in (:all, :latest) ||
            throw(ArgumentError("package versions must be :all, :latest, or a vector"))
        versions
    elseif versions isa AbstractVector{VersionNumber}
        sort!(unique!(collect(versions)))
    else
        throw(ArgumentError("package versions must be :all, :latest, or a vector"))
    end
    if environment !== nothing && worker_environment !== nothing &&
       abspath(String(environment)) != abspath(String(worker_environment))
        throw(ArgumentError(
            "environment and worker_environment refer to different directories; " *
            "use worker_environment for the isolated measurement seed"))
    end
    selected_environment = something(worker_environment, environment, pwd())
    env = abspath(String(selected_environment))
    isdir(env) || throw(ArgumentError(
        "suite worker environment does not exist: $env"))
    src = source === nothing ? nothing : abspath(String(source))
    src === nothing || isdir(src) ||
        throw(ArgumentError("package source does not exist: $src"))
    local_sources = abspath.(String.(dev_sources))
    all(isdir, local_sources) ||
        throw(ArgumentError("every development dependency must be a directory"))
    pins = Dict{VersionNumber, Vector{Any}}(
        VersionNumber(version) => Any[spec for spec in specs]
    for (version, specs) in pairs(release_pins))
    allunique(candidate.label for candidate in candidates) ||
        throw(ArgumentError("candidate labels must be unique within a package suite"))
    return PackageSuite(id, String(package), env, src, local_sources, pins,
        selection, collect(features), include_dev, collect(candidates))
end

"Seed environment copied into every isolated measurement worker."
worker_environment(package::PackageSuite) = getfield(package, :worker_environment)

# Preserve source compatibility for callers that inspected the pre-1.0 field.
function Base.getproperty(package::PackageSuite, name::Symbol)
    name === :environment && return getfield(package, :worker_environment)
    return getfield(package, name)
end

function Base.propertynames(::PackageSuite, private::Bool = false)
    names = fieldnames(PackageSuite)
    return private ? (names..., :environment) : (names..., :environment)
end

function _worker_environment_issue(package::PackageSuite)
    package.package == "PerfChecker" && return nothing
    project = joinpath(worker_environment(package), "Project.toml")
    isfile(project) || return nothing
    document = try
        TOML.parsefile(project)
    catch error
        return "cannot inspect worker Project.toml at $project: $(sprint(showerror, error))"
    end
    dependencies = get(document, "deps", Dict{String, Any}())
    haskey(dependencies, "PerfChecker") || return nothing
    return "worker environment for $(package.package) directly depends on PerfChecker: " *
           "$project. Keep PerfChecker in the controller environment and place only " *
           "measurement backends plus workload dependencies in the worker environment."
end

function _validate_worker_environments(packages; strict::Bool)
    seen = Set{Tuple{String, String}}()
    for package in packages
        identity = (package.package, worker_environment(package))
        identity in seen && continue
        push!(seen, identity)
        issue = _worker_environment_issue(package)
        issue === nothing && continue
        strict ? throw(ArgumentError(issue)) : @warn issue
    end
    return nothing
end

"The measurable surface of one software, composed from package suites."
struct SoftwareSuite
    id::Symbol
    description::String
    packages::Vector{PackageSuite}
    comparisons::Vector{ComparisonPolicy}
end

function SoftwareSuite(id::Symbol, packages::AbstractVector{PackageSuite};
        description::AbstractString = "",
        comparisons::AbstractVector{ComparisonPolicy} = ComparisonPolicy[])
    isempty(packages) && throw(ArgumentError("software suite $id has no packages"))
    allunique(getfield.(packages, :id)) ||
        throw(ArgumentError("package-suite IDs must be unique"))
    allunique(policy.id for policy in comparisons) || throw(ArgumentError(
        "comparison policy ids must be unique within a software suite"))
    return SoftwareSuite(id, String(description), collect(packages), collect(comparisons))
end

struct SuiteTarget
    label::String
    version::SuiteVersion
    compatibility_version::VersionNumber
    kind::Symbol
    source::Union{Nothing, String}
    revision::Union{Nothing, String}
    dependencies::Vector{Any}
end

"""
One resolved package, feature variant and target in a suite plan. Created by
`plan_suite`; inspect `planned_status` and `reason` before execution. Planning
an unavailable target preserves it for reports rather than executing it.
"""
struct PlannedFeatureRun
    suite::Symbol
    package_suite::PackageSuite
    feature::FeatureSpec
    target::SuiteTarget
    variant::Union{Nothing, FeatureVariant}
    comparison_key::String
    planned_status::Symbol
    reason::String
end

workload_id(run::PlannedFeatureRun) = workload_id(run.feature)

"""
Resolved suite, profile, feature runs and comparison policies. Obtain a plan
with `plan_suite`, inspect or filter it, then pass it to `run_suite` or
`launch_suite`. Holding a plan does not start workers.
"""
struct SuitePlan
    suite::SoftwareSuite
    profile::Symbol
    runs::Vector{PlannedFeatureRun}
    comparisons::Vector{ComparisonPolicy}
end

"""
Return the deterministic identifier of a planned feature/target selection used by plan filters, progress events and interfaces. This identifies the selection, not a completed measurement.
"""
function planned_run_id(run::PlannedFeatureRun)
    identity = (run.suite, run.package_suite.id, run.feature.id,
        run.target.label, run.comparison_key)
    return _content_digest(identity)[1:20]
end

function _project_version(package::PackageSuite)
    candidates = String[]
    package.source === nothing ||
        push!(candidates, joinpath(package.source, "Project.toml"))
    push!(candidates, joinpath(worker_environment(package), "Project.toml"))
    for project in candidates
        isfile(project) || continue
        data = parse(read(project, String))
        haskey(data, "version") && return VersionNumber(data["version"])
    end
    throw(ArgumentError("cannot determine current version for $(package.package)"))
end

function _declared_versions(package::PackageSuite, version_provider)
    versions = if package.versions === :all || package.versions === :latest
        sort!(unique!(VersionNumber.(version_provider(package.package))))
    else
        copy(package.versions)
    end
    package.versions === :latest && !isempty(versions) && return [last(versions)]
    return versions
end

function _representative_versions(versions::Vector{VersionNumber})
    groups = Dict{Tuple{Int, Int}, Vector{VersionNumber}}()
    for version in versions
        key = version.major == 0 ? (version.major, version.minor) : (version.major, -1)
        push!(get!(groups, key, VersionNumber[]), version)
    end
    selected = VersionNumber[]
    for group in values(groups)
        sort!(group)
        push!(selected, first(group))
        last(group) == first(group) || push!(selected, last(group))
    end
    return sort!(unique!(selected))
end

function suite_targets(package::PackageSuite, profile::Symbol;
        version_provider = get_pkg_versions,
        candidates::AbstractVector{SuiteCandidate} = SuiteCandidate[])
    profile in (:quick, :ci, :historical, :release) ||
        throw(ArgumentError("unknown suite profile $profile"))
    declared = profile === :quick && package.include_dev ? VersionNumber[] :
               _declared_versions(package, version_provider)
    releases = if profile === :quick
        package.include_dev ? VersionNumber[] :
        (isempty(declared) ? declared : [last(declared)])
    elseif profile === :ci
        _representative_versions(declared)
    else
        declared
    end
    targets = SuiteTarget[SuiteTarget(string(version), version, version, :release,
                              nothing, nothing, Any[])
                          for version in releases]
    if package.include_dev && profile !== :release
        current = _project_version(package)
        push!(targets,
            SuiteTarget("dev@$(current)", :dev, current, :dev,
                package.source, nothing, Any[]))
    end
    all_candidates = vcat(package.candidates, collect(candidates))
    if profile !== :release
        current = isempty(all_candidates) ? nothing : _project_version(package)
        for candidate in all_candidates
            source = something(candidate.source, package.source)
            source === nothing && throw(ArgumentError(
                "candidate $(candidate.label) for $(package.package) requires a source or URL"))
            compatibility = something(candidate.compatibility_version, current)
            push!(targets,
                SuiteTarget(candidate.label, candidate.revision,
                    compatibility, :candidate, source, candidate.revision,
                    copy(candidate.dependencies)))
        end
    end
    allunique(target.label for target in targets) || throw(ArgumentError(
        "release, development, and candidate target labels must be unique"))
    return targets
end

function _variant_for(feature::FeatureSpec, version::VersionNumber)
    supports(feature.julia_window, VERSION) || return nothing
    matches = [variant for variant in feature.variants if supports(variant.window, version)]
    length(matches) <= 1 || throw(ArgumentError(
        "feature $(feature.id) has overlapping variants for version $version"))
    return isempty(matches) ? nothing : only(matches)
end

function _feature_unavailable_reason(feature::FeatureSpec, target::SuiteTarget)
    window = feature.julia_window
    if !supports(window, VERSION)
        bounds = String[]
        window.since === nothing || push!(bounds, ">=$(window.since)")
        window.until === nothing || push!(bounds, "<=$(window.until)")
        VERSION in window.excluded && push!(bounds, "excluding $(VERSION)")
        requirement = isempty(bounds) ? "declared Julia compatibility" : join(bounds, ", ")
        return "feature requires Julia $requirement; controller uses $(VERSION)"
    end
    return "feature is not defined for package version $(target.label)"
end

"""
    plan_suite(suite; profile=:quick, candidates=Dict(), comparisons=[])

Resolve package releases, development sources, Git candidates, feature variants,
and comparison policies into an immutable `SuitePlan` without running workloads.
"""
function plan_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions,
        candidates::AbstractDict = Dict{String, Vector{SuiteCandidate}}(),
        comparisons::AbstractVector{ComparisonPolicy} = ComparisonPolicy[])
    _validate_worker_environments(suite.packages; strict = false)
    planned = PlannedFeatureRun[]
    for package in suite.packages
        requested = get(candidates, package.package,
            get(candidates, string(package.id), SuiteCandidate[]))
        for target in suite_targets(package, profile; version_provider,
            candidates = SuiteCandidate[item for item in requested])
            for feature in package.features
                variant = _variant_for(feature, target.compatibility_version)
                if variant === nothing
                    push!(planned,
                        PlannedFeatureRun(suite.id, package, feature, target,
                            nothing, "", :unavailable,
                            _feature_unavailable_reason(feature, target)))
                else
                    key = isempty(variant.comparison_key) ? string(feature.id) :
                          variant.comparison_key
                    push!(planned,
                        PlannedFeatureRun(suite.id, package, feature, target,
                            variant, key, :ready, ""))
                end
            end
        end
    end
    policies = isempty(comparisons) ? suite.comparisons :
               vcat(suite.comparisons, collect(comparisons))
    allunique(policy.id for policy in policies) || throw(ArgumentError(
        "comparison policy ids must be unique after applying overrides"))
    return SuitePlan(suite, profile, planned, policies)
end

"""
Return the dictionary representation of a SuitePlan with its revision and resolved selections for UI and execution contracts.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function suite_plan_dict(plan::SuitePlan)
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-suite-plan/1",
        "suite" => string(plan.suite.id),
        "description" => plan.suite.description,
        "profile" => string(plan.profile),
        "comparisons" => comparison_policy_dict.(plan.comparisons),
        "runs" => [Dict{String, Any}(
                       "id" => planned_run_id(run),
                       "package" => run.package_suite.package,
                       "package_id" => string(run.package_suite.id),
                       "feature" => string(run.feature.id),
                       "workload" => string(workload_id(run)),
                       "description" => run.feature.description,
                       "backend" => string(run.feature.backend),
                       "qualification" => Dict{String, Any}(
                           "probes" => probe_spec_dict.(run.feature.probes),
                           "oracle" => run.feature.oracle === nothing ? nothing :
                                       oracle_spec_dict(run.feature.oracle)),
                       "julia_compatibility" => Dict{String, Any}(
                           "since" => run.feature.julia_window.since === nothing ? nothing :
                                      string(run.feature.julia_window.since),
                           "until" => run.feature.julia_window.until === nothing ? nothing :
                                      string(run.feature.julia_window.until),
                           "excluded" => sort!(string.(collect(run.feature.julia_window.excluded)))),
                       "entrypoint" => run.variant === nothing ?
                                       first(run.feature.variants).entrypoint :
                                       (run.variant::FeatureVariant).entrypoint,
                       "version" => run.target.label,
                       "target_kind" => string(run.target.kind),
                       "target_source" => run.target.source,
                       "target_revision" => run.target.revision,
                       "comparison_key" => run.comparison_key,
                       "status" => string(run.planned_status),
                       "reason" => run.reason) for run in plan.runs])
    payload["plan_revision"] = _content_digest(payload)
    return payload
end

"Return a validated, explicitly ordered subset of a server-produced plan."
function select_suite_plan(plan::SuitePlan, run_ids::AbstractVector{<:AbstractString})
    requested = String.(run_ids)
    length(unique(requested)) == length(requested) ||
        throw(ArgumentError("selected run identifiers must be unique"))
    available = Dict(planned_run_id(run) => run for run in plan.runs)
    unknown = setdiff(requested, collect(keys(available)))
    isempty(unknown) || throw(ArgumentError(
        "unknown selected run identifiers: $(join(unknown, ", "))"))
    selected = PlannedFeatureRun[available[id] for id in requested]
    return SuitePlan(plan.suite, plan.profile, selected, plan.comparisons)
end

"Apply the ordered selection from a shared UI configuration."
function select_suite_plan(plan::SuitePlan, configuration::AbstractDict)
    get(configuration, "schema_version", nothing) == "perfchecker-ui-config/1" ||
        throw(ArgumentError("unsupported UI configuration schema"))
    selection = get(configuration, "selection", nothing)
    selection isa AbstractDict || throw(ArgumentError(
        "UI configuration requires a selection object"))
    run_ids = get(selection, "run_ids", nothing)
    run_ids isa AbstractVector && all(id -> id isa AbstractString, run_ids) ||
        throw(ArgumentError("UI configuration selection requires string run_ids"))
    return select_suite_plan(plan, String.(run_ids))
end

"""
Result of one planned feature execution. `planned` identifies the target;
`status` distinguishes `:pass`, `:unavailable`, `:blocked`, `:invalid` and `:error`.
`elapsed_seconds` is orchestration time, not a replacement for measured samples.
`result` holds backend data when available; `qualification` retains probe,
correctness and provenance evidence even when execution fails.
"""
struct FeatureRun
    planned::PlannedFeatureRun
    status::Symbol
    elapsed_seconds::Float64
    result::Any
    message::String
    qualification::Dict{String, Any}
end

function FeatureRun(planned::PlannedFeatureRun, status::Symbol, elapsed_seconds::Float64,
        result, message::String)
    FeatureRun(planned, status, elapsed_seconds, result,
        message, _empty_qualification())
end

"""
Completed suite evidence: the original `plan`, UTC start/finish timestamps
and a vector of `FeatureRun` records. Use `suite_verdict` for qualification and
`write_suite_reports` to export it without repeating measurements.
"""
struct SoftwareSuiteResult
    plan::SuitePlan
    started_at::String
    finished_at::String
    runs::Vector{FeatureRun}
end

struct SuiteRunError <: Exception
    result::SoftwareSuiteResult
end

function Base.showerror(io::IO, error::SuiteRunError)
    failures = count(run -> run.status in (:error, :blocked, :invalid), error.result.runs)
    print(io, "software suite $(error.result.plan.suite.id) had $failures failed run(s)")
end

"""
Handle returned by `launch_suite` for asynchronous controller execution.
Use `suite_job_status`, `suite_job_progress`, `cancel_suite!` and `wait_suite`
instead of mutating its task and reference fields.
"""
mutable struct SuiteJob
    id::UUID
    plan::SuitePlan
    task::Task
    status::Base.RefValue{Symbol}
    result::Base.RefValue{Any}
    error::Base.RefValue{Any}
    progress::Base.RefValue{Dict{String, Any}}
    cancelled::Base.RefValue{Bool}
end

function _suite_progress(plan::SuitePlan, runs::Vector{FeatureRun};
        state::Symbol = :running, current = nothing)
    total = length(plan.runs)
    completed = length(runs)
    counts = Dict(status => count(run -> run.status === status, runs)
    for status in (:pass, :unavailable, :blocked, :invalid, :error))
    current_payload = current === nothing ? nothing :
                      Dict{String, Any}(
        "id" => planned_run_id(current),
        "package" => current.package_suite.package,
        "feature" => string(current.feature.id),
        "workload" => string(workload_id(current)),
        "backend" => string(current.feature.backend),
        "version" => current.target.label)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-progress/1", "stage" => "measurement",
        "state" => string(state), "total" => total, "completed" => completed,
        "remaining" => max(total - completed, 0),
        "fraction" => total == 0 ? 1.0 : completed / total,
        "percent" => total == 0 ? 100.0 : 100 * completed / total,
        "passed" => counts[:pass], "unavailable" => counts[:unavailable],
        "blocked" => counts[:blocked], "invalid" => counts[:invalid],
        "failed" => counts[:error], "current_run" => current_payload)
end

function _notify_suite_progress(callback, payload)
    try
        callback(payload)
    catch error
        @warn "PerfChecker progress callback failed" exception=(error,
            catch_backtrace())
    end
    return payload
end

function _feature_blocks(planned::PlannedFeatureRun)
    entrypoint = (planned.variant::FeatureVariant).entrypoint
    state_name = Symbol("_perfchecker_feature_state_", planned_run_id(planned))
    qualification = _feature_qualification_block(planned, state_name)
    needs_qualification_state = qualification !== nothing
    setup = quote
        include($entrypoint)
        isdefined(Main, :perf_workload) ||
            error("feature entrypoint must define perf_workload(state)")
        const $state_name = isdefined(Main, :d) && get(Main.d, :fresh_feature, false) &&
                            !$needs_qualification_state ?
                            nothing : isdefined(Main, :perf_setup) ? perf_setup() : nothing
    end
    workload = Expr(:call, :perf_workload, state_name)
    if needs_qualification_state
        qualification = quote
            try
                $qualification
            finally
                if isdefined(Main, :d) && get(Main.d, :fresh_feature, false) &&
                   isdefined(Main, :perf_cleanup)
                    Base.invokelatest(Main.perf_cleanup, $state_name)
                end
            end
        end
    end
    return setup, workload, qualification
end

function _feature_qualification_block(planned::PlannedFeatureRun, state_name::Symbol;
        include_oracle::Bool = true)
    feature = planned.feature
    isempty(feature.probes) && (!include_oracle || feature.oracle === nothing) &&
        return nothing
    probes = probe_spec_dict.(feature.probes)
    oracle = include_oracle && feature.oracle !== nothing ?
             oracle_spec_dict(feature.oracle) : nothing
    oracle_function = oracle === nothing ? "" : oracle["function"]
    oracle_required = oracle === nothing ? false : Bool(oracle["required"])
    has_oracle = oracle !== nothing
    return quote
        let
            normalize_result = function (raw; unavailable::Bool = false)
                if unavailable
                    return Dict{String, Any}(
                        "status" => "unavailable", "message" => String(raw))
                elseif raw === nothing
                    return Dict{String, Any}("status" => "passed", "message" => "")
                elseif raw isa Bool
                    return Dict{String, Any}(
                        "status" => raw ? "passed" : "failed",
                        "message" => raw ? "" : "check returned false")
                elseif raw isa AbstractString
                    return Dict{String, Any}("status" => "passed", "message" => String(raw))
                elseif raw isa AbstractDict || raw isa NamedTuple
                    evidence = Dict{String, Any}(
                        string(key) => value for (key, value) in pairs(raw))
                    token = lowercase(String(get(evidence, "status", "passed")))
                    status = token in ("pass", "passed", "valid", "available",
                        "supported", "ok") ? "passed" :
                             token in ("unavailable", "unsupported", "missing") ?
                             "unavailable" : "failed"
                    message = String(get(evidence, "message",
                        status == "passed" ? "" : "check reported $token"))
                    return Dict{String, Any}(
                        "status" => status, "message" => message,
                        "evidence" => evidence)
                end
                return Dict{String, Any}(
                    "status" => "failed",
                    "message" => "unsupported check result $(typeof(raw))")
            end

            probe_records = Dict{String, Any}[]
            for specification in $probes
                function_name = Symbol(specification["function"])
                record = if !isdefined(Main, function_name)
                    normalize_result("probe function $function_name is not defined";
                        unavailable = true)
                else
                    function_value = getfield(Main, function_name)
                    try
                        raw = applicable(function_value, $state_name) ?
                              Base.invokelatest(function_value, $state_name) :
                              Base.invokelatest(function_value)
                        normalize_result(raw)
                    catch error
                        Dict{String, Any}(
                            "status" => "failed",
                            "message" => sprint(showerror, error, catch_backtrace()))
                    end
                end
                record["id"] = specification["id"]
                record["function"] = specification["function"]
                record["blocking"] = specification["blocking"]
                record["category"] = specification["category"]
                push!(probe_records, record)
            end

            correctness = if !$has_oracle
                Dict{String, Any}("status" => "not_checked",
                    "message" => "no correctness oracle was evaluated")
            else
                function_name = Symbol($oracle_function)
                if !isdefined(Main, function_name)
                    Dict{String, Any}(
                        "status" => $oracle_required ? "failed" : "not_checked",
                        "message" => "oracle function $function_name is not defined",
                        "function" => String(function_name),
                        "required" => $oracle_required)
                else
                    function_value = getfield(Main, function_name)
                    record = try
                        raw = if applicable(function_value, $state_name)
                            Base.invokelatest(function_value, $state_name)
                        elseif applicable(function_value)
                            Base.invokelatest(function_value)
                        else
                            result = Base.invokelatest(Main.perf_workload, $state_name)
                            isdefined(Main, :perf_synchronize) &&
                                Base.invokelatest(
                                    Main.perf_synchronize, $state_name, result)
                            Base.invokelatest(function_value, $state_name, result)
                        end
                        normalize_result(raw)
                    catch error
                        Dict{String, Any}(
                            "status" => "failed",
                            "message" => sprint(showerror, error, catch_backtrace()))
                    end
                    record["function"] = String(function_name)
                    record["required"] = $oracle_required
                    record
                end
            end

            Dict{String, Any}(
                "schema_version" => "perfchecker-run-qualification/1",
                "probes" => probe_records,
                "correctness" => correctness,
                "performance" => Dict{String, Any}(
                    "status" => "not_compared",
                    "message" => "no baseline and policy were evaluated for this run"))
        end
    end
end

function _run_config(planned::PlannedFeatureRun, overrides::AbstractDict)
    options = copy(planned.feature.options)
    merge!(options, (planned.variant::FeatureVariant).options)
    get!(options, :quiet, true)
    for (key, value) in pairs(overrides)
        key isa Symbol || throw(ArgumentError("suite override keys must be symbols"))
        options[key] = value
    end
    if planned.feature.backend in (
        :benchmark, :chairmark, :profile, :wall_profile, :profile_alloc) &&
       get(options, :state_policy, :fresh) == :fresh
        get(options, :evals, 1) in (1, nothing) || throw(ArgumentError(
            "fresh feature scenarios require evals=1; use state_policy=:reuse only for intentionally repeated state"))
        options[:evals] = 1
        options[:fresh_feature] = true
        options[:feature_oracle] = planned.feature.oracle === nothing ? "" :
                                   string(planned.feature.oracle.function_name)
        options[:feature_oracle_required] = planned.feature.oracle === nothing ? false :
                                            planned.feature.oracle.required
    end
    options[:path] = worker_environment(planned.package_suite)
    options[:tags] = unique!(vcat(
        normalize_symbols(get(options, :tags, Symbol[]), :tags),
        [planned.suite, planned.package_suite.id, planned.feature.id]))
    if planned.target.kind === :release
        version = planned.target.version::VersionNumber
        options[:pkgs] = (planned.package_suite.package, :custom, [version], true)
        pins = get(planned.package_suite.release_pins, version, Any[])
        if !isempty(pins)
            existing = get(options, :extra_pkgs, Any[])
            existing = existing isa AbstractVector ? collect(existing) : Any[existing]
            options[:extra_pkgs] = vcat(existing, pins)
        end
    elseif planned.target.kind === :dev
        source = planned.package_suite.source
        source === nothing && throw(ArgumentError(
            "dev target for $(planned.package_suite.package) requires a source path"))
        options[:devops] = PackageSpec(
            name = planned.package_suite.package, path = source)
        isempty(planned.package_suite.dev_sources) ||
            (options[:extra_devops] = [PackageSpec(path = path)
                                       for path in planned.package_suite.dev_sources])
        options[:include_current] = false
    elseif planned.target.kind === :candidate
        source = something(planned.target.source, planned.package_suite.source)
        source === nothing && throw(ArgumentError(
            "candidate target $(planned.target.label) requires a Git source"))
        options[:devops] = PackageSpec(name = planned.package_suite.package,
            url = source, rev = something(planned.target.revision, planned.target.label))
        options[:target_install] = :add
        isempty(planned.target.dependencies) || begin
            existing = get(options, :extra_pkgs, Any[])
            existing = existing isa AbstractVector ? collect(existing) : Any[existing]
            options[:extra_pkgs] = vcat(existing, planned.target.dependencies)
        end
        options[:include_current] = false
    else
        throw(ArgumentError("unsupported suite target kind $(planned.target.kind)"))
    end
    return PerfConfig(planned.feature.backend, options)
end

"Identity of the package graph prepared for one feature worker."
function _suite_environment_key(planned::PlannedFeatureRun, config::PerfConfig)
    options = config.options
    requirements = Dict{String, Any}(
        "package_suite" => string(planned.package_suite.id),
        "target" => planned.target.label,
        "path" => abspath(String(options[:path])),
        "packages" => repr(get(options, :pkgs, nothing)),
        "devops" => repr(get(options, :devops, nothing)),
        "extra_packages" => repr(get(options, :extra_pkgs, nothing)),
        "extra_devops" => repr(get(options, :extra_devops, nothing)),
        "target_install" => repr(get(options, :target_install, :develop)),
        "include_current" => Bool(get(options, :include_current, true)))
    return _content_digest(requirements)
end

function _unavailable_exception(error)
    error isa Pkg.Resolve.ResolverError && return true
    error isa Pkg.Types.PkgError || return false
    message = lowercase(sprint(showerror, error))
    return occursin("unsatisfiable requirements", message) ||
           occursin("not found", message) || occursin("expected package", message)
end

function _default_suite_executor(planned::PlannedFeatureRun, config, setup, workload,
        qualification = nothing)
    return check_function(config, setup, workload; qualification)
end

function _ensure_suite_backends(plan::SuitePlan)
    backends = Set(run.feature.backend
    for run in plan.runs
    if run.planned_status === :ready)
    for backend in backends
        try
            backend === :benchmark && Core.eval(Main, :(import BenchmarkTools))
            backend === :chairmark && Core.eval(Main, :(import Chairmarks))
        catch error
            throw(ArgumentError(
                "suite backend $backend must be installed in the controller environment: " *
                sprint(showerror, error)))
        end
    end
    return nothing
end

function _execute_suite_plan(plan::SuitePlan; executor = _default_suite_executor,
        overrides::AbstractDict = Dict{Symbol, Any}(),
        progress_callback = _ -> nothing)
    executor === _default_suite_executor && begin
        _validate_worker_environments(plan.suite.packages; strict = true)
        _ensure_suite_backends(plan)
    end
    started = string(Dates.now(Dates.UTC))
    runs = FeatureRun[]
    prepared = Dict{String, String}()
    environment_provenance = Dict{String, Dict{String, Any}}()
    preparation_errors = Dict{String, Any}()
    preparation_roots = String[]
    _notify_suite_progress(progress_callback,
        _suite_progress(plan, runs; state = :running))
    try
        for planned in plan.runs
            _notify_suite_progress(progress_callback,
                _suite_progress(plan, runs; state = :running, current = planned))
            if planned.planned_status === :unavailable
                qualification = _empty_qualification()
                qualification["source_provenance"] = _source_provenance(planned)
                push!(runs,
                    FeatureRun(planned, :unavailable, 0.0, nothing, planned.reason,
                        qualification))
                _notify_suite_progress(progress_callback,
                    _suite_progress(plan, runs; state = :running))
                continue
            end
            before = time()
            config = nothing
            environment_key = nothing
            try
                config = _run_config(planned, overrides)
                if executor === _default_suite_executor
                    key = _suite_environment_key(planned, config)
                    environment_key = key
                    haskey(preparation_errors, key) && throw(preparation_errors[key])
                    environment = get(prepared, key, nothing)
                    if environment === nothing
                        root, environment = try
                            _prepare_check_environment(config)
                        catch error
                            preparation_errors[key] = error
                            rethrow()
                        end
                        push!(preparation_roots, root)
                        prepared[key] = environment
                    end
                    config.options[:prepared_environment] = environment
                end
                setup, workload, qualification_block = _feature_blocks(planned)
                result = if executor === _default_suite_executor
                    Base.invokelatest(executor, planned, config, setup, workload,
                        qualification_block)
                else
                    Base.invokelatest(executor, planned, config, setup, workload)
                end
                qualification = result isa CheckerResult &&
                                !isempty(result.qualifications) ?
                                deepcopy(only(result.qualifications)) :
                                _empty_qualification()
                if executor === _default_suite_executor
                    key = _suite_environment_key(planned, config)
                    qualification["environment_provenance"] = get!(
                        environment_provenance, key) do
                        _environment_provenance(config.options[:prepared_environment])
                    end
                    qualification["source_provenance"] = _source_provenance(planned)
                end
                _finalize_qualification!(qualification)
                qualification_failure = _qualification_failure_kind(qualification)
                if qualification_failure === nothing
                    push!(runs,
                        FeatureRun(planned, :pass, time() - before, result, "",
                            qualification))
                elseif qualification_failure === :performance
                    failure = QualificationFailure(qualification_failure, qualification)
                    push!(runs,
                        FeatureRun(planned, :invalid, time() - before, result,
                            sprint(showerror, failure), qualification))
                else
                    throw(QualificationFailure(qualification_failure, qualification))
                end
            catch error
                status = error isa QualificationFailure ?
                         (error.kind === :probe ? :blocked : :invalid) :
                         _unavailable_exception(error) ? :unavailable : :error
                message = sprint(showerror, error, catch_backtrace())
                qualification = error isa QualificationFailure ?
                                deepcopy(error.evidence) : _empty_qualification()
                if executor === _default_suite_executor
                    qualification["source_provenance"] = _source_provenance(planned)
                    if config isa PerfConfig && environment_key !== nothing &&
                       haskey(config.options, :prepared_environment)
                        qualification["environment_provenance"] = get!(
                            environment_provenance, environment_key) do
                            _environment_provenance(
                                config.options[:prepared_environment])
                        end
                    end
                end
                _finalize_qualification!(qualification)
                push!(runs,
                    FeatureRun(planned, status, time() - before, nothing,
                        message, qualification))
            end
            _notify_suite_progress(progress_callback,
                _suite_progress(plan, runs; state = :running))
        end
    finally
        foreach(root -> rm(root; recursive = true, force = true), preparation_roots)
    end
    result = SoftwareSuiteResult(plan, started, string(Dates.now(Dates.UTC)), runs)
    final_state = suite_passed(result) ? :complete : :failed
    _notify_suite_progress(progress_callback,
        _suite_progress(plan, runs; state = final_state))
    return result
end

"""
    launch_suite(plan::SuitePlan; executor, overrides=Dict()) -> SuiteJob
    launch_suite(suite::SoftwareSuite; profile=:quick, kwargs...) -> SuiteJob

Start an asynchronous controller task which executes the selected plan. The
normal executor prepares isolated environments and starts measurement workers.
Return immediately with a job handle. Poll `suite_job_progress` for progress,
use `cancel_suite!` to request interruption and `wait_suite` to obtain the result
or surface a failure. Supplying an executor changes how measurements are run.
"""
function launch_suite(plan::SuitePlan;
        overrides::AbstractDict = Dict{Symbol, Any}(), executor = _default_suite_executor,
        progress_callback = _ -> nothing)
    status = Ref(:queued)
    result = Ref{Any}(nothing)
    captured_error = Ref{Any}(nothing)
    progress = Ref(_suite_progress(plan, FeatureRun[]; state = :queued))
    cancelled = Ref(false)
    update_progress = payload -> begin
        progress[] = payload
        _notify_suite_progress(progress_callback, payload)
    end
    task = @async begin
        status[] = :running
        try
            result[] = _execute_suite_plan(plan; overrides, executor,
                progress_callback = update_progress)
            status[] = :complete
        catch error
            if cancelled[] || error isa InterruptException
                status[] = :cancelled
                progress[]["state"] = "cancelled"
            else
                captured_error[] = (error, catch_backtrace())
                status[] = :failed
                progress[]["state"] = "failed"
            end
        end
    end
    return SuiteJob(uuid4(), plan, task, status, result, captured_error, progress,
        cancelled)
end

function launch_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions, kwargs...)
    return launch_suite(plan_suite(suite; profile, version_provider); kwargs...)
end

"""
Return the current job state, such as `:running`, `:cancelling`, `:complete`, `:cancelled` or `:failed`, without waiting.
"""
suite_job_status(job::SuiteJob) = job.status[]
"""
Return a shallow copy of the current progress dictionary without waiting. It includes completed/total counts, per-status counts and the current run when available.
"""
suite_job_progress(job::SuiteJob) = copy(job.progress[])

"""
    cancel_suite!(job::SuiteJob) -> Bool

Request interruption of an active suite task and mark it as cancelling. Return
`false` if the task already finished. A `true` return acknowledges the request;
use `wait_suite` or the job status to observe completed cancellation and cleanup.
"""
function cancel_suite!(job::SuiteJob)
    istaskdone(job.task) && return false
    job.cancelled[] = true
    job.status[] = :cancelling
    job.progress[]["state"] = "cancelling"
    schedule(job.task, InterruptException(); error = true)
    return true
end

"""
Return the dictionary representation of a SuiteJob snapshot, including a completed result or failure message when available.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function suite_job_dict(job::SuiteJob)
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-suite-job/1",
        "job_id" => string(job.id),
        "suite" => string(job.plan.suite.id),
        "profile" => string(job.plan.profile),
        "status" => string(suite_job_status(job)),
        "progress" => suite_job_progress(job))
    job.status[] === :complete && (payload["result"] = suite_dict(job.result[]))
    if job.status[] === :failed && job.error[] !== nothing
        error, _ = job.error[]
        payload["message"] = sprint(showerror, error)
    end
    return payload
end

"""
    wait_suite(job::SuiteJob; strict=true) -> SoftwareSuiteResult

Wait for the controller task to finish. Rethrow orchestration failures and throw
`InterruptException` for cancellation. With `strict=true`, a failed suite raises
an error carrying its result; `strict=false` returns completed failure records
for inspection. It does not suppress orchestration exceptions.
"""
function wait_suite(job::SuiteJob; strict::Bool = true)
    wait(job.task)
    if job.error[] !== nothing
        error, trace = job.error[]
        @debug "suite orchestration failure" exception=(error, trace)
        throw(error)
    end
    job.status[] === :cancelled && throw(InterruptException())
    result = job.result[]::SoftwareSuiteResult
    strict && !suite_passed(result) && throw(SuiteRunError(result))
    return result
end

"""
    run_suite(plan; executor=_default_suite_executor, strict=true,
              progress_callback=identity)

Execute the runnable leaves of a resolved suite plan and return their isolated
worker results. When `strict` is false, individual failures are retained in the
result instead of aborting the complete suite.
"""
function run_suite(plan::SuitePlan; executor = _default_suite_executor,
        overrides::AbstractDict = Dict{Symbol, Any}(), strict::Bool = true,
        progress_callback = _ -> nothing)
    result = _execute_suite_plan(plan; executor, overrides, progress_callback)
    strict && !suite_passed(result) && throw(SuiteRunError(result))
    return result
end

function run_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions, kwargs...)
    return run_suite(plan_suite(suite; profile, version_provider); kwargs...)
end

"""
    load_software_suite(path; factory=:build_suite) -> SoftwareSuite

Load an ordinary Julia suite definition in an isolated controller module. The
file must define the selected zero-argument factory or bind `suite` to a
`SoftwareSuite`.
Only the controller evaluates this file; measured Malt workers still load just
their backend, package, and feature entrypoint.
"""
function load_software_suite(path::AbstractString; factory::Symbol = :build_suite)
    definition = abspath(String(path))
    isfile(definition) ||
        throw(ArgumentError("suite definition does not exist: $definition"))
    owner = Module(gensym(:PerfCheckerSuiteDefinition), true, true)
    Core.eval(owner, :(eval(expression) = Core.eval($owner, expression)))
    Core.eval(owner, :(include(source) = Base.include($owner, source)))
    Base.include(owner, definition)
    value = Base.invokelatest() do
        # On Julia 1.13 the binding-existence check is world-age sensitive too.
        # Inspect and invoke the freshly included definition in the same world.
        if isdefined(owner, factory)
            getfield(owner, factory)()
        elseif isdefined(owner, :suite)
            getfield(owner, :suite)
        else
            throw(ArgumentError(
                "suite definition must define $(factory)() or a suite binding: $definition"))
        end
    end
    value isa SoftwareSuite || throw(ArgumentError(
        "suite definition returned $(typeof(value)); expected SoftwareSuite"))
    return value
end

"""
    run_suite_file(path; profile=:quick, reports=nothing,
                   factory=:build_suite, kwargs...)

Load and execute a suite definition. When `reports` is a path, write the JSON,
Markdown, and JUnit representations consumed by CI and user interfaces.
"""
function run_suite_file(path::AbstractString; profile::Symbol = :quick,
        reports = nothing, factory::Symbol = :build_suite, kwargs...)
    result = run_suite(load_software_suite(path; factory); profile, kwargs...)
    reports === nothing || write_suite_reports(result, String(reports))
    return result
end

"""
Return whether no run has status `:error`, `:blocked` or `:invalid`.
Unavailable runs do not fail this execution predicate. Use `suite_verdict`
to distinguish partial execution from validated results.
"""
function suite_passed(result::SoftwareSuiteResult)
    !any(run -> run.status in (:error, :blocked, :invalid), result.runs)
end

"""
    suite_verdict(result::SoftwareSuiteResult) -> Symbol

Summarize execution and qualification in priority order: execution failure,
blocked capability, invalid result, partial execution, no execution, validated,
execution with warnings, or executed. Ordinary successful execution without a
correctness oracle remains `:executed`.
"""
function suite_verdict(result::SoftwareSuiteResult)
    any(run -> run.status === :error, result.runs) && return :execution_failed
    any(run -> run.status === :blocked, result.runs) && return :blocked
    any(run -> run.status === :invalid, result.runs) && return :invalid
    any(run -> run.status === :unavailable, result.runs) && return :partially_executed
    isempty(result.runs) && return :not_executed
    verdicts = Symbol[Symbol(get(run.qualification, "verdict", "executed"))
                      for run in result.runs]
    all(verdict -> verdict === :validated, verdicts) && return :validated
    any(verdict -> verdict in (:validated_with_warnings, :executed_with_warnings),
        verdicts) && return :executed_with_warnings
    return :executed
end

"""
Return a TypedTables table with one row per feature run: suite, package, feature, target version, comparison key, status, elapsed orchestration seconds and message.
"""
function suite_summary(result::SoftwareSuiteResult)
    return Table(
        suite = fill(string(result.plan.suite.id), length(result.runs)),
        package = [run.planned.package_suite.package for run in result.runs],
        feature = [string(run.planned.feature.id) for run in result.runs],
        version = [run.planned.target.label for run in result.runs],
        comparison_key = [run.planned.comparison_key for run in result.runs],
        status = [string(run.status) for run in result.runs],
        elapsed_seconds = [run.elapsed_seconds for run in result.runs],
        message = [run.message for run in result.runs])
end

function _first_summary_row(run::FeatureRun)
    run.result isa CheckerResult || return Dict{String, Any}()
    table = summary_table(run.result)
    isempty(table) && return Dict{String, Any}()
    return Dict{String, Any}(string(name) => (ismissing(getproperty(table, name)[1]) ?
                                              nothing :
                                              getproperty(table, name)[1])
    for name in propertynames(table))
end

function _resource_envelope_payloads(run::FeatureRun)
    run.result isa CheckerResult || return Dict{String, Any}[]
    return Dict{String, Any}[resource_envelope_dict(envelope)
                             for envelope in run.result.resource_envelopes
                             if envelope !== nothing]
end

"""
Return the dictionary representation of a SoftwareSuiteResult with schema, execution verdict and per-run summaries and qualification.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function suite_dict(result::SoftwareSuiteResult)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-suite-result/1",
        "suite" => string(result.plan.suite.id),
        "description" => result.plan.suite.description,
        "profile" => string(result.plan.profile),
        "started_at" => result.started_at,
        "finished_at" => result.finished_at,
        "passed" => suite_passed(result),
        "verdict" => string(suite_verdict(result)),
        "runs" => [Dict{String, Any}(
                       "package" => run.planned.package_suite.package,
                       "feature" => string(run.planned.feature.id),
                       "workload" => string(workload_id(run.planned)),
                       "version" => run.planned.target.label,
                       "target_kind" => string(run.planned.target.kind),
                       "comparison_key" => run.planned.comparison_key,
                       "status" => string(run.status),
                       "elapsed_seconds" => run.elapsed_seconds,
                       "message" => run.message,
                       "summary" => _first_summary_row(run),
                       "resource_envelopes" => _resource_envelope_payloads(run),
                       "qualification" => run.qualification) for run in result.runs])
end

"""
    write_suite_json(result::SoftwareSuiteResult, path)

Write JSON suite evidence including per-run qualification. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_suite_json(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON.print(io, suite_dict(result), 2)
    end
    return String(path)
end

"""
    write_suite_markdown(result::SoftwareSuiteResult, path)

Write a Markdown suite summary with verdict and run statuses. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_suite_markdown(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker suite: `$(result.plan.suite.id)`\n")
        println(io, "Profile: `$(result.plan.profile)`  ")
        println(io, "Verdict: **$(uppercase(string(suite_verdict(result))))**\n")
        println(io, "| Package | Feature | Version | Comparable as | Status | Seconds |")
        println(io, "| --- | --- | --- | --- | --- | ---: |")
        for run in result.runs
            message = isempty(run.message) ? "" :
                      " — " * replace(first(split(run.message, '\n')), '|' => '/')
            println(io,
                "| $(run.planned.package_suite.package) | $(run.planned.feature.id) | " *
                "$(run.planned.target.label) | $(run.planned.comparison_key) | " *
                "$(run.status)$(message) | $(round(run.elapsed_seconds; digits = 3)) |")
        end
    end
    return String(path)
end

function _xml_escape(value)
    replace(string(value), '&' => "&amp;", '<' => "&lt;",
        '>' => "&gt;", '"' => "&quot;", '\'' => "&apos;")
end

"""
    write_suite_junit(result::SoftwareSuiteResult, path)

Write JUnit XML, mapping error/blocked/invalid runs to failures and unavailable runs to skipped cases. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_suite_junit(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    failures = count(run -> run.status in (:error, :blocked, :invalid), result.runs)
    skipped = count(run -> run.status === :unavailable, result.runs)
    total_time = sum(run.elapsed_seconds for run in result.runs)
    open(path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        println(io,
            "<testsuite name=\"$(_xml_escape(result.plan.suite.id))\" " *
            "tests=\"$(length(result.runs))\" failures=\"$failures\" " *
            "skipped=\"$skipped\" time=\"$total_time\">")
        for run in result.runs
            name = "$(run.planned.feature.id)[$(run.planned.target.label)]"
            println(io,
                "  <testcase classname=\"$(_xml_escape(run.planned.package_suite.package))\" " *
                "name=\"$(_xml_escape(name))\" time=\"$(run.elapsed_seconds)\">")
            run.status in (:error, :blocked, :invalid) && println(io,
                "    <failure message=\"$(_xml_escape(run.status))\">" *
                "$(_xml_escape(run.message))</failure>")
            run.status === :unavailable && println(io,
                "    <skipped message=\"$(_xml_escape(run.message))\" />")
            println(io, "  </testcase>")
        end
        println(io, "</testsuite>")
    end
    return String(path)
end

"""
    write_suite_reports(result, directory; formats, relative_limits=Dict(),
                        min_samples=1, sample_statistics=Dict(),
                        default_sample_statistic=:median)

Export a completed suite and return written paths. Defaults include JSON,
Markdown, JUnit, a run bundle, version series and version-comparison reports.
The comparison options control evidence reduction and budgets. Ordinary report
files are replaced; bundles use new run directories. No workload is rerun.
"""
function write_suite_reports(result::SoftwareSuiteResult, directory::AbstractString;
        formats = (:json, :markdown, :junit, :bundle, :version_series,
            :version_comparison_json, :version_comparison_markdown),
        relative_limits::AbstractDict = Dict{String, Float64}(),
        min_samples::Integer = 1,
        sample_statistics::AbstractDict = Dict{String, Symbol}(),
        default_sample_statistic = :median)
    mkpath(directory)
    paths = String[]
    :json in formats && push!(paths,
        write_suite_json(result, joinpath(directory, "suite-result.json")))
    :markdown in formats && push!(paths,
        write_suite_markdown(result, joinpath(directory, "suite-report.md")))
    :junit in formats && push!(paths,
        write_suite_junit(result, joinpath(directory, "suite-junit.xml")))
    protocol_formats = (:bundle, :version_series, :version_comparison_json,
        :version_comparison_markdown)
    bundle = any(format -> format in formats, protocol_formats) ?
             _suite_run_bundle(result) : nothing
    if :bundle in formats
        bundle_path = joinpath(abspath(String(directory)), "bundles",
            "run-$(bundle.manifest["run_id"])")
        push!(paths, write_run_bundle(bundle, bundle_path))
    end
    if any(format -> format in formats,
        (:version_series, :version_comparison_json,
            :version_comparison_markdown))
        comparison = compare_suite_versions(bundle; relative_limits, min_samples,
            sample_statistics, default_sample_statistic)
        :version_series in formats && push!(paths,
            write_version_series_json(comparison,
                joinpath(directory, "version-series.json")))
        :version_comparison_json in formats && push!(paths,
            write_version_comparison_json(comparison,
                joinpath(directory, "version-comparison.json")))
        :version_comparison_markdown in formats && push!(paths,
            write_version_comparison_markdown(comparison,
                joinpath(directory, "version-comparison.md")))
    end
    return paths
end

"""
Load `DrWatson`, then convert a suite plan (or a suite with `profile=:quick`) into parameter dictionaries for each planned run. No measurement is started.
"""
function drwatson_parameters end
"""
Load `DrWatson`, then derive a filename from a planned run's suite, package, feature and target version; `suffix="jld2"` selects the default extension. This does not write a file.
"""
function drwatson_savename end
"""
    drwatson_produce_or_load(producer, parameters; directory="",
                            force=false, tag=true, kwargs...)

Load `DrWatson` to enable its disk-cache workflow. Delegate cache lookup and
writing to `DrWatson.produce_or_load`; wrap a non-dictionary producer result
under `"result"`. Return DrWatson's result. The producer executes only when its
cache policy requires it; cached data is not fresh measurement evidence.
"""
function drwatson_produce_or_load end
"""
    register_oxygen_routes!(source; prefix="/perfchecker/v1", kwargs...)

Load `PerfCheckerWeb`. Register routes on Oxygen's current router for a result,
bundle, result provider or interactive suite. Read-only evidence routes do not
run measurements; suite/studio control routes may launch work. This registers
routes without starting the HTTP server. See `serve_suite` for hosting.
"""
function register_oxygen_routes! end
"""
    serve_suite(source; host="127.0.0.1", port=8080, kwargs...)

Load `PerfCheckerWeb` to serve a suite, saved reports, bundle or scenario catalog
in Oxygen. Available routes depend on the source type. The default host is
loopback; remote control requires an authenticator and explicit
`allow_remote_control=true`. Server startup and lifetime options are forwarded
to Oxygen. Loading a report view does not itself rerun its measurements.
"""
function serve_suite end
"""
    studio_token_authenticator(users_or_path) -> Function

Load `PerfCheckerWeb`. Build a bearer-token verifier from a digest-to-identity
dictionary or a TOML file with `[[users]]`, `id`, `token_sha256` and `roles`.
The returned function hashes a supplied token and returns its identity or
`nothing`. It does not create credentials, start a server or grant new roles.
"""
function studio_token_authenticator end
"""
    run_studio_agent(suite; server, token, agent_id, poll_seconds=2,
                     heartbeat_seconds=30, max_jobs=typemax(Int), once=false)

Load `PerfCheckerWeb`. Register an agent with the specified controller, poll for
jobs, execute accepted suite plans locally and upload progress/results. This
performs network requests and runs workload processes; keep the server and suite
under the caller's control. Use `once=true` for a bounded polling iteration or
`max_jobs` to bound completed jobs.
"""
function run_studio_agent end
"""
    launch_pluto_dashboard(path; kwargs...)

Load `PerfCheckerPluto` and open an existing generated notebook with `Pluto.run`.
Reject a missing file and forward server options to Pluto. This starts a notebook
server; generating a notebook alone uses `prepare_pluto_dashboard` instead.
"""
function launch_pluto_dashboard end
"""
    suite_dashboard(result::SoftwareSuiteResult; view=:normalized)
    suite_dashboard(job::SuiteJob; strict=true, view=:normalized)
    suite_dashboard(suite::SoftwareSuite; profile=:quick, strict=true, view=:normalized, kwargs...)

Load `PerfCheckerMakie` to overlay the first available benchmark workload's
measurements, each divided by its minimum across versions. Use `plot_catalog`
and `performance_figure` to select another workload. With `view=:absolute`,
show minimum benchmark times for every run; this is also the fallback when no
overlay is available. The result overload only renders saved measurements. The job overload
waits for completion; the suite overload launches and waits for new measurements.
Return a Makie figure.
"""
function suite_dashboard end
