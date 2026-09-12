function _profile_stack_records(bundle::RunBundle; metric::AbstractString,
        case_id::AbstractString = "", version = nothing)
    records = Dict{String, Any}[]
    for observation in bundle.observations
        get(observation, "metric", "") == metric || continue
        isempty(case_id) || get(observation, "case_id", "") == case_id || continue
        version === nothing || get(observation, "version", "") == string(version) ||
            continue
        stack = get(get(observation, "attributes", Dict()), "stack", nothing)
        stack isa AbstractVector || continue
        isempty(stack) && continue
        push!(records,
            Dict("stack" => String.(stack),
                "value" => Float64(observation["value"])))
    end
    if isempty(records) && haskey(bundle.manifest, "scenario_evidence") &&
       (isempty(case_id) || case_id == bundle.manifest["scenario"]["id"]) &&
       (version === nothing ||
        string(version) == bundle.manifest["scenario"]["implementation"])
        raw = bundle.manifest["scenario_evidence"]
        if metric == "julia.cpu.samples"
            append!(records, get(raw, "cpu_stacks", []))
        elseif metric == "julia.alloc.bytes"
            for site in get(raw, "allocation_sites", [])
                stack = ["$(f["function"]) ($(f["file"]):$(f["line"]))"
                         for f in reverse(site["stack"])]
                isempty(stack) ||
                    push!(records, Dict("stack" => stack, "value" => site["bytes"]))
            end
        end
    end
    isempty(records) &&
        throw(ArgumentError("no stack observations match the requested profile"))
    return records
end

"""
    write_folded_profile(bundle, path; metric="julia.cpu.samples",
                         case_id="", version=nothing)

Write matching saved stacks as folded stack/weight lines for flame-graph tools.
Create parent directories, replace the file and return its absolute path.
Reject an empty selection. This exports observations; it does not sample a process.
"""
function write_folded_profile(bundle::RunBundle, path::AbstractString;
        metric::AbstractString = "julia.cpu.samples", case_id::AbstractString = "",
        version = nothing)
    destination = abspath(String(path))
    mkpath(dirname(destination))
    records = _profile_stack_records(bundle; metric, case_id, version)
    open(destination, "w") do io
        for record in records
            labels = replace.(record["stack"], ';' => ':')
            println(io, join(labels, ';'), ' ', record["value"])
        end
    end
    return destination
end

"""
    write_speedscope_profile(bundle, path; metric="julia.cpu.samples",
                            case_id="", version=nothing)

Export matching saved stacks as a Speedscope sampled-profile JSON document.
Weights use bytes for allocation metrics and unitless samples otherwise. Create
parents, replace the file and return its absolute path; reject an empty selection.
"""
function write_speedscope_profile(bundle::RunBundle, path::AbstractString;
        metric::AbstractString = "julia.cpu.samples", case_id::AbstractString = "",
        version = nothing)
    destination = abspath(String(path))
    mkpath(dirname(destination))
    records = _profile_stack_records(bundle; metric, case_id, version)
    labels = sort!(unique!(vcat((record["stack"] for record in records)...)))
    frame_index = Dict(label => index - 1 for (index, label) in enumerate(labels))
    samples = [[frame_index[label] for label in record["stack"]] for record in records]
    weights = [record["value"] for record in records]
    payload = Dict(
        "\$schema" => "https://www.speedscope.app/file-format-schema.json",
        "shared" => Dict("frames" => [Dict("name" => label) for label in labels]),
        "profiles" => [Dict("type" => "sampled", "name" => metric,
            "unit" => occursin("alloc", metric) ? "bytes" : "none",
            "startValue" => 0, "endValue" => sum(weights),
            "samples" => samples, "weights" => weights)],
        "activeProfileIndex" => 0, "exporter" => "PerfChecker.jl")
    open(destination, "w") do io
        JSON.print(io, payload, 2)
    end
    return destination
end

"""
    write_pprof_profile(bundle, path; metric="julia.cpu.samples",
                       case_id="", version=nothing, max_samples=100_000)

Load `PProf` and `FlameGraphs`. Convert saved weighted stacks into a PProf file,
returning its absolute path. The conversion approximates weights with repeated
samples scaled by `max_samples`; it is not a fresh native-process profile.
Reject nonpositive sample limits and profiles without positive weights.
"""
function write_pprof_profile end

@testitem "Portable profile exports" tags=[:unit, :profile, :exports] begin
    using PerfChecker
    using JSON

    bundle = PerfChecker.RunBundle(
        Dict("schema_version" => PerfChecker.RUN_BUNDLE_SCHEMA,
            "run_id" => "profile", "suite" => "demo", "state" => "complete"),
        Dict{String, Any}[], [Dict{String, Any}(
            "metric" => "julia.cpu.samples", "case_id" => "demo/case",
            "version" => "dev", "value" => 3,
            "attributes" => Dict("stack" => ["root (a.jl:1)", "leaf (b.jl:2)"]))],
        Dict{String, Any}[], Dict{String, Any}[])
    mktempdir() do dir
        folded = write_folded_profile(bundle, joinpath(dir, "profile.folded"))
        speedscope = write_speedscope_profile(
            bundle, joinpath(dir, "profile.speedscope.json"))
        @test occursin("root (a.jl:1);leaf (b.jl:2) 3", read(folded, String))
        @test PerfChecker._json_parsefile(speedscope)["profiles"][1]["weights"] == [3]
    end
end
