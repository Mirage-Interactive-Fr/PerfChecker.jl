const RUN_QUALIFICATION_SCHEMA = "perfchecker-run-qualification/1"

"A functional capability probe executed inside the prepared target worker."
struct ProbeSpec
    id::Symbol
    function_name::Symbol
    blocking::Bool
    category::Symbol
end

function ProbeSpec(id::Symbol; function_name::Symbol = Symbol("perf_probe_", id),
        blocking::Bool = true, category::Symbol = :native)
    category in (:native, :runtime, :service, :device, :custom) ||
        throw(ArgumentError("unsupported probe category $category"))
    return ProbeSpec(id, function_name, blocking, category)
end

"A deterministic correctness oracle executed outside the measured region."
struct OracleSpec
    function_name::Symbol
    required::Bool
end

function OracleSpec(; function_name::Symbol = :perf_oracle, required::Bool = true)
    OracleSpec(function_name, required)
end

"Structured qualification evidence carried when a run is blocked or invalid."
struct QualificationFailure <: Exception
    kind::Symbol
    evidence::Dict{String, Any}
end

function Base.showerror(io::IO, error::QualificationFailure)
    verdict = get(error.evidence, "verdict", string(error.kind))
    records = error.kind === :probe ? get(error.evidence, "probes", Any[]) :
              error.kind === :performance ?
              Any[get(error.evidence, "performance", Dict{String, Any}())] :
              Any[get(error.evidence, "correctness", Dict{String, Any}())]
    messages = unique!(String[String(get(record, "message", ""))
                              for record in records
                              if !isempty(String(get(record, "message", "")))])
    print(io, "qualification $verdict")
    isempty(messages) || print(io, ": ", join(messages, "; "))
end

function _empty_qualification(; correctness::AbstractString = "not_checked",
        performance::AbstractString = "not_compared",
        verdict::AbstractString = "executed")
    return Dict{String, Any}(
        "schema_version" => RUN_QUALIFICATION_SCHEMA,
        "probes" => Dict{String, Any}[],
        "correctness" => Dict{String, Any}(
            "status" => String(correctness),
            "message" => correctness == "not_checked" ?
                         "no correctness oracle was declared" : ""),
        "performance" => Dict{String, Any}(
            "status" => String(performance),
            "message" => performance == "not_compared" ?
                         "no baseline and policy were evaluated for this run" : ""),
        "verdict" => String(verdict))
end

function _qualification_failure_kind(evidence::AbstractDict)
    probes = get(evidence, "probes", Any[])
    any(
        probe -> Bool(get(probe, "blocking", true)) &&
            get(probe, "status", "failed") != "passed",
        probes) && return :probe
    get(get(evidence, "correctness", Dict{String, Any}()), "status", "not_checked") ==
    "failed" && return :correctness
    get(get(evidence, "performance", Dict{String, Any}()), "status", "not_compared") ==
    "failed" && return :performance
    return nothing
end

function _qualification_verdict(evidence::AbstractDict)
    failure = _qualification_failure_kind(evidence)
    failure === :probe && return :blocked
    failure === :correctness && return :invalid
    failure === :performance && return :invalid
    correctness = get(get(evidence, "correctness", Dict{String, Any}()),
        "status", "not_checked")
    nonblocking_warning = any(
        probe -> get(probe, "status", "failed") != "passed",
        get(evidence, "probes", Any[]))
    correctness == "passed" && return nonblocking_warning ?
           :validated_with_warnings : :validated
    return nonblocking_warning ? :executed_with_warnings : :executed
end

function _finalize_qualification!(evidence::Dict{String, Any})
    evidence["schema_version"] = RUN_QUALIFICATION_SCHEMA
    get!(evidence, "probes", Dict{String, Any}[])
    get!(evidence, "correctness",
        Dict{String, Any}("status" => "not_checked",
            "message" => "no correctness oracle was declared"))
    get!(evidence, "performance",
        Dict{String, Any}("status" => "not_compared",
            "message" => "no baseline and policy were evaluated for this run"))
    evidence["verdict"] = string(_qualification_verdict(evidence))
    return evidence
end

"""
Return the dictionary representation of a ProbeSpec with its identifier, function name, blocking flag and category.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function probe_spec_dict(probe::ProbeSpec)
    return Dict{String, Any}("id" => string(probe.id),
        "function" => string(probe.function_name), "blocking" => probe.blocking,
        "category" => string(probe.category))
end

"""
Return the dictionary representation of an OracleSpec with its function name and required flag.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function oracle_spec_dict(oracle::OracleSpec)
    return Dict{String, Any}("function" => string(oracle.function_name),
        "required" => oracle.required)
end

function _sha256_file(path::AbstractString)
    isfile(path) || return nothing
    return bytes2hex(SHA.sha256(read(path)))
end

function _local_source_fingerprint(root::AbstractString)
    files = Dict{String, String}()
    complete = true
    consumed = 0
    candidates = filter(
        isfile, [joinpath(root, "Project.toml"), joinpath(root, "LocalPreferences.toml")])
    for directory in ("src", "ext", "deps", "providers")
        base = joinpath(root, directory)
        isdir(base) || continue
        if islink(base)
            complete = false
            continue
        end
        for (parent, directories, names) in walkdir(base; follow_symlinks = false)
            any(islink(joinpath(parent, d)) for d in directories) && (complete = false)
            append!(candidates, joinpath.(parent, names))
            if length(candidates) > 4096
                complete = false
                break
            end
        end
    end
    for file in sort!(unique(candidates))
        if islink(file) || length(files) >= 4096 || consumed + filesize(file) > 268_435_456
            complete = false
            continue
        end
        consumed += filesize(file)
        files[replace(relpath(file, root), '\\' => '/')] = bytes2hex(open(SHA.sha256, file))
    end
    Dict("sha256" => _content_digest(files),
        "files" => length(files), "complete" => complete,
        "scope" => "Project.toml, LocalPreferences.toml, src/, ext/, deps/ and providers/; additional data must be declared as scenario fixtures")
end

function _environment_provenance(path::AbstractString)
    root = abspath(String(path))
    preferred = joinpath(root, "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
    manifest = isfile(preferred) ? preferred : joinpath(root, "Manifest.toml")
    evidence = Dict{String, Any}("path" => root,
        "project_sha256" => _sha256_file(joinpath(root, "Project.toml")),
        "preferences_sha256" => _sha256_file(joinpath(root, "LocalPreferences.toml")),
        "manifest_file" => basename(manifest), "manifest_sha256" => _sha256_file(manifest))
    sources = Dict{String, Any}[]
    resolved_packages = Dict{String, Any}[]
    if isfile(manifest)
        try
            dependencies = get(TOML.parsefile(manifest), "deps", Dict())
            for name in sort!(collect(keys(dependencies))), entry in dependencies[name]
                # Keep the resolved versions after temporary worker environments
                # are removed. Hashes alone cannot explain dependency transitions.
                push!(resolved_packages, merge(Dict{String, Any}("name" => name),
                    Dict{String, Any}(key => entry[key] for key in
                        ("uuid", "version", "git-tree-sha1") if haskey(entry, key))))
                haskey(entry, "path") || continue
                source = abspath(root, entry["path"])
                push!(sources,
                    Dict("package" => name, "path" => source,
                        "source" => isdir(source) ? _local_source_fingerprint(source) :
                                    Dict("complete" => false,
                            "message" => "development dependency directory missing")))
            end
        catch error
            evidence["development_capture_error"] = first(sprint(showerror, error), 1024)
        end
    end
    evidence["development_sources"] = sources
    evidence["resolved_packages"] = resolved_packages
    evidence
end

function _git_output(root::String, arguments::AbstractVector{<:AbstractString})
    command = Cmd(Cmd(vcat(["git"], String.(arguments))); dir = root)
    return strip(read(command, String))
end

"Capture reproducible source identity without recording remotes or file contents."
function _git_provenance(path::AbstractString)
    root = abspath(String(path))
    evidence = Dict{String, Any}(
        "capture_scope" => "working_tree",
        "path" => root,
        "captured" => false,
        "revision" => nothing,
        "branch" => nothing,
        "dirty" => nothing,
        "dirty_state_sha256" => nothing)
    isdir(root) || return evidence
    try
        repository = _git_output(root, ["rev-parse", "--show-toplevel"])
        revision = _git_output(root, ["rev-parse", "HEAD"])
        branch = _git_output(root, ["branch", "--show-current"])
        dirty_state = _git_output(
            root, ["status", "--porcelain=v1", "--untracked-files=normal"])
        evidence["path"] = repository
        evidence["captured"] = true
        evidence["revision"] = revision
        evidence["branch"] = isempty(branch) ? nothing : branch
        evidence["dirty"] = !isempty(dirty_state)
        evidence["dirty_state_sha256"] = bytes2hex(SHA.sha256(codeunits(dirty_state)))
    catch error
        evidence["capture_error"] = first(sprint(showerror, error), 2_048)
    end
    return evidence
end

function _source_provenance(planned)
    source = planned.target.kind === :candidate ?
             something(planned.target.source, planned.package_suite.source) :
             planned.package_suite.source
    local_checkout = planned.target.kind in (:dev, :candidate) &&
                     source !== nothing && isdir(source)
    evidence = local_checkout ? _git_provenance(source) :
               Dict{String, Any}(
        "capture_scope" => "declared_target",
        "path" => source,
        "captured" => false,
        "revision" => planned.target.revision,
        "branch" => nothing,
        "dirty" => nothing,
        "dirty_state_sha256" => nothing)
    evidence["target_kind"] = string(planned.target.kind)
    evidence["target_label"] = planned.target.label
    evidence["requested_revision"] = planned.target.revision
    return evidence
end

@testitem "Qualification contracts" tags=[:unit, :qualification] begin
    using PerfChecker

    probe = ProbeSpec(:jolt; function_name = :probe_jolt, category = :native)
    @test probe_spec_dict(probe)["blocking"]
    oracle = OracleSpec()
    @test oracle.function_name == :perf_oracle

    empty = PerfChecker._empty_qualification()
    @test PerfChecker._qualification_verdict(empty) == :executed
    empty["correctness"] = Dict("status" => "passed")
    @test PerfChecker._qualification_verdict(empty) == :validated
    empty["correctness"] = Dict("status" => "failed", "message" => "wrong hash")
    @test PerfChecker._qualification_failure_kind(empty) == :correctness
    empty["correctness"] = Dict("status" => "passed", "message" => "")
    empty["performance"] = Dict(
        "status" => "failed", "message" => "external live bytes grew")
    @test PerfChecker._qualification_failure_kind(empty) == :performance
    @test PerfChecker._qualification_verdict(empty) == :invalid
    @test occursin("external live bytes grew",
        sprint(showerror,
            PerfChecker.QualificationFailure(:performance, empty)))

    mktempdir() do dir
        run(Cmd(Cmd(["git", "init", "--quiet"]); dir))
        run(Cmd(Cmd(["git", "config", "user.email", "perfchecker@example.invalid"]); dir))
        run(Cmd(Cmd(["git", "config", "user.name", "PerfChecker test"]); dir))
        run(Cmd(Cmd(["git", "config", "commit.gpgsign", "false"]); dir))
        write(joinpath(dir, "sample.txt"), "stable")
        run(Cmd(Cmd(["git", "add", "sample.txt"]); dir))
        run(Cmd(Cmd(["git", "commit", "--quiet", "-m", "fixture"]); dir))
        clean = PerfChecker._git_provenance(dir)
        @test clean["captured"]
        @test !clean["dirty"]
        write(joinpath(dir, "sample.txt"), "changed")
        @test PerfChecker._git_provenance(dir)["dirty"]
    end

    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), "")
        entrypoint = joinpath(dir, "qualification-feature.jl")
        write(entrypoint, """
perf_setup() = 41
perf_workload(state) = state + 1
perf_probe_native(state) = (status = :passed, message = "callable", value = state)
perf_oracle(state) = state + 1 == 42
""")
        feature = FeatureSpec(:qualified; entrypoint,
            backend = :network,
            probes = [ProbeSpec(:native)], oracle = OracleSpec())
        package = PackageSuite("Example"; environment = dir, source = dir,
            versions = VersionNumber[], include_dev = false, features = [feature])
        target = PerfChecker.SuiteTarget(
            "1.0.0", v"1.0.0", v"1.0.0", :release, nothing, nothing, Any[])
        planned = PlannedFeatureRun(:qualification, package, feature, target,
            only(feature.variants), "qualified", :ready, "")
        setup, _, qualification = PerfChecker._feature_blocks(planned)
        worker = PerfChecker.Worker(; exeflags = ["--project=$dir"])
        try
            PerfChecker.remote_eval_wait(Main, worker, setup)
            evidence = PerfChecker.remote_eval_fetch(Main, worker, qualification)
            @test only(evidence["probes"])["status"] == "passed"
            @test evidence["correctness"]["status"] == "passed"
        finally
            PerfChecker.safe_stop(worker)
        end

        config = PerfConfig(:network; path = dir, repeat = false,
            network_repetitions = 1)
        result = PerfChecker.check_function(config, :(nothing),
            :((bytes_sent = 1, bytes_received = 2, operations = 1));
            qualification = :(Dict{String, Any}(
                "probes" => Dict{String, Any}[],
                "correctness" => Dict{String, Any}("status" => "passed"))))
        @test only(result.qualifications)["verdict"] == "validated"

        @test_throws PerfChecker.QualificationFailure PerfChecker.check_function(
            config, :(nothing),
            :((bytes_sent = 1, bytes_received = 2, operations = 1));
            qualification = :(Dict{String, Any}(
                "probes" => Dict{String, Any}[],
                "correctness" => Dict{String, Any}(
                    "status" => "failed", "message" => "wrong result"))))
    end
end
