using PerfChecker, Dates, Serialization, SHA

checkpoint_repr(value::AbstractDict) = repr([(string(k), checkpoint_repr(v)) for (k,v) in sort!(collect(value); by = pair -> string(first(pair)))])
checkpoint_repr(value::AbstractVector) = repr(checkpoint_repr.(value))
checkpoint_repr(value) = repr(value)

"""
Run a single-package release history with a complete report after each version.

The final directory contains the combined bundle. `versions/` holds independently
readable checkpoints. A local `result.jls` allows resuming this exact script and
Julia environment; it is an implementation cache, never a public interchange format.
Only resume a directory produced locally by this example, not a downloaded cache.
"""
function checkpointed_history(plan, output; overrides = Dict{Symbol,Any}())
    runs = FeatureRun[]
    started = string(now(UTC))
    # Changes to workload definitions or controller dependencies invalidate a resume.
    files = sort(filter(f -> endswith(f, ".jl") || basename(f) in ("Project.toml", "Manifest.toml"),
        [joinpath(root, file) for (root, _, names) in walkdir(@__DIR__) for file in names
            if !any(part -> part in ("results", "exports", ".controller", "output", "metadata", ".git"), splitpath(relpath(root, @__DIR__)))]))
    core = dirname(dirname(pathof(PerfChecker)))
    corefiles = sort([joinpath(root, file) for (root, _, names) in walkdir(joinpath(core, "src")) for file in names if endswith(file, ".jl")])
    source_identity = join([relpath(f,@__DIR__) * ":" * bytes2hex(sha256(read(f))) for f in vcat(files, corefiles)], "\n")
    # The same sources with a different selection or sampling policy are a different run.
    selection = checkpoint_repr(PerfChecker.suite_plan_dict(plan)) * checkpoint_repr(overrides) *
        checkpoint_repr([run.feature.options for run in plan.runs])
    identity = bytes2hex(sha256(source_identity * string(VERSION) * selection))
    marker = joinpath(output, "checkpoint-identity.txt")
    if isfile(marker)
        strip(read(marker, String)) == identity || error("Example sources changed; start a fresh history instead of resuming this cache")
    else
        mkpath(output)
        write(marker, identity)
    end
    for version in unique(run.target.label for run in plan.runs)
        directory = joinpath(output, "versions", version)
        checkpoint = joinpath(directory, "result.jls")
        result = if isfile(checkpoint)
            println("Reading local checkpoint: ", version)
            deserialize(checkpoint)
        else
            selected = filter_suite_plan(plan; from_version = VersionNumber(version), to_version = VersionNumber(version))
            measured = run_suite_repl(selected; reports = directory, strict = false, overrides)
            temporary = checkpoint * ".tmp"
            serialize(temporary, measured)
            mv(temporary, checkpoint; force = true)
            measured
        end
        append!(runs, result.runs)
        println("Saved complete version report: ", directory)
        flush(stdout)
    end
    result = SoftwareSuiteResult(plan, started, string(now(UTC)), runs)
    write_suite_reports(result, output)
    return result
end
