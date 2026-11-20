using PerfChecker, PerfCheckerMakie, WGLMakie, JSON
include(normpath(joinpath(
    @__DIR__, "../../../../../examples/kitchen-sink/observation-export.jl")))

length(ARGS) == 2 || error("Pass summary.json and a new export directory")
original_source, output = abspath.(ARGS)
source = joinpath(dirname(original_source), "normalized-source.json")
ispath(output) && error("Choose a new export directory")
evidence = JSON.parsefile(source)
evidence["schema_version"] == "perfchecker-jet-normalized/1" ||
    error("Unexpected evidence schema")
bytes2hex(sha256(read(original_source))) == evidence["original_summary_sha256"] ||
    error("The original JET diagnosis and numeric capture do not share their declared source")
measurements = evidence["measurements"]
all(record -> record["status"] == "complete" && record["correctness"] == "passed",
    measurements) || error("Render only completed measurements with passing oracles")
rows = Dict{String, Any}[]
for record in measurements
    implementation = record["implementation"]
    samples = record["samples"]
    isempty(samples) && error("Missing recorded BenchmarkTools samples")
    for (field, metric, unit) in (("time", "julia.wall.time", "s"),
        ("gctime", "julia.gc.time", "s"), ("bytes", "julia.alloc.bytes", "By"),
        ("allocs", "julia.alloc.count", "1"))
        get(evidence["units"], field, nothing) == unit ||
            error("The captured $field unit differs from the documented projection")
        all(sample -> haskey(sample, field), samples) ||
            error("JET example needs real $field samples; missing GC must be measured, never inferred")
        push!(rows,
            Dict("version" => implementation, "target_kind" => "implementation",
                "metric" => metric, "unit" => unit,
                "value" => minimum(sample[field] for sample in samples),
                "samples" => length(samples), "capture_id" => record["capture_id"],
                "derivation" => "minimum of recorded paired BenchmarkTools samples"))
    end
end
metadata = Dict(key => evidence[key]
for key in ("runtime", "perfchecker_version", "rows", "expected_result",
    "runner_sha256", "project_sha256", "manifest_sha256"))
metadata["case_source_sha256"] = evidence["source_sha256"]
metadata["capture_ids"] = [record["capture_id"] for record in measurements]
metadata["collector_versions"] = [record["collector_version"] for record in measurements]
metadata["evidence_file"] = basename(source)
metadata["original_summary_sha256"] = evidence["original_summary_sha256"]
metadata["target_kind"] = "implementation"
for key in ("perfchecker_tree", "original_source_sha256",
    "measurement_runtime_sha256", "measurement_entrypoint",
    "allocation_scope", "units", "started_at", "finished_at")
    haskey(evidence, key) && (metadata[key] = evidence[key])
end
export_normalized_projection(output, "measurements", rows;
    title = "Same revenue calculation, different element types",
    collector = "BenchmarkTools (through PerfChecker)",
    scope = evidence["measurement_scope"] * "; " * evidence["comparison_scope"],
    sources = [source, original_source], metadata, xlabel = "Implementation", target_label = "implementation",
    json_name = "measurements.json", reference_target = "dynamic")
println("Rendered four normalized saved metrics; no scenario or analyzer was rerun")
