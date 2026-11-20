using PerfChecker, JSON, SHA, Statistics

# This mode captures all four native BenchmarkTools columns together. The
# earlier JET diagnosis remains a separate, unchanged report.
if length(ARGS) == 2 && first(ARGS) == "--normalized-only"
    using BenchmarkTools, Dates, Pkg, UUIDs

    output = abspath(last(ARGS))
    ispath(output) &&
        error("Choose a new output directory; existing results are not overwritten")
    Threads.nthreads() == 1 || error("Use one Julia thread for this recorded comparison")
    source = joinpath(@__DIR__, "cases.jl")
    original_path = joinpath(@__DIR__, "summary.json")
    original_bytes = read(original_path)
    original = JSON.parse(String(copy(original_bytes)))
    source_hash = bytes2hex(sha256(read(source)))
    runner = joinpath(pkgdir(PerfChecker), "src/scenario_runtime.jl")
    include(runner)
    include(source)
    started = string(now(UTC))
    measurements = Dict{String, Any}[]
    for implementation in ("dynamic", "typed")
        case = Base.invokelatest(
            getfield(SalesCases, Symbol(implementation)), Dict("rows" => 4096))
        state = Base.invokelatest(case.prepare)
        answer = Base.invokelatest(case.operation, state)
        answer == 129536.0 && Base.invokelatest(case.verify, state, answer) ||
            error("The correctness oracle failed")
        trial = Base.invokelatest(
            SharedScenarioRuntime.measure_benchmark, case, 20; raw = true)
        length(trial.times) == length(trial.gctimes) == 20 ||
            error("Expected 20 paired native samples")
        samples = [Dict("time" => Float64(trial.times[index]) / 1e9,
                       "gctime" => Float64(trial.gctimes[index]) / 1e9,
                       "bytes" => trial.memory, "allocs" => trial.allocs)
                   for index in eachindex(trial.times)]
        push!(measurements,
            Dict("implementation" => implementation, "status" => "complete",
                "capture_id" => string(uuid4()), "source_kind" => "native BenchmarkTools Trial",
                "correctness" => "passed", "collector" => "benchmark",
                "collector_version" => string(Base.pkgversion(BenchmarkTools)),
                "samples" => samples,
                "medians" => Dict(metric => median([sample[metric] for sample in samples])
                for metric in ("time", "gctime", "bytes", "allocs")),
                "minimums" => Dict(metric => minimum(sample[metric] for sample in samples)
                for metric in ("time", "gctime", "bytes", "allocs")),
                "raw_trial" => Dict("times_ns" => trial.times,
                    "gctimes_ns" => trial.gctimes, "memory_bytes" => trial.memory,
                    "allocations" => trial.allocs, "evals" => trial.params.evals,
                    "samples_limit" => trial.params.samples,
                    "seconds_limit" => trial.params.seconds)))
    end
    core = Pkg.dependencies()[Base.PkgId(PerfChecker).uuid]
    project = dirname(Base.active_project())
    summary = Dict("schema_version" => "perfchecker-jet-normalized/1",
        "runtime" => Dict("language" => "julia", "version" => string(VERSION),
            "threads" => Threads.nthreads(), "os" => string(Sys.KERNEL), "arch" => string(Sys.ARCH)),
        "perfchecker_version" => string(Base.pkgversion(PerfChecker)),
        "perfchecker_tree" => string(core.tree_hash),
        "rows" => 4096, "expected_result" => 129536.0,
        "started_at" => started, "finished_at" => string(now(UTC)),
        "measurement_scope" => "one warm operation on fresh prepared state; preparation and correctness verification excluded; 20 samples, evals=1, sequential implementations",
        "allocation_scope" => "BenchmarkTools Trial.memory and Trial.allocs per-evaluation estimates; paired times and GC times are the actual native samples",
        "comparison_scope" => "two implementations on one local machine; not released package versions or a portable speed guarantee",
        "units" => Dict("time" => "s", "gctime" => "s", "bytes" => "By", "allocs" => "1"),
        "original_summary_sha256" => bytes2hex(sha256(original_bytes)),
        "original_source_sha256" => original["source_sha256"],
        "source_sha256" => source_hash,
        "runner_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "measurement_runtime_sha256" => bytes2hex(sha256(read(runner))),
        "measurement_entrypoint" => "PerfChecker SharedScenarioRuntime.measure_benchmark(case, 20; raw=true)",
        "reproduction" => "julia --startup-file=no --threads=1 --project=. run.jl --normalized-only NEW_DIRECTORY",
        "project_sha256" => bytes2hex(sha256(read(Base.active_project()))),
        "manifest_sha256" => bytes2hex(sha256(read(joinpath(project, "Manifest.toml")))),
        "measurements" => measurements)
    read(original_path) == original_bytes || error("The original diagnostic report changed")
    mkpath(output)
    open(io -> JSON.print(io, summary, 2), joinpath(output, "normalized-source.json"), "w")
    for name in ("Project.toml", "Manifest.toml")
        cp(joinpath(project, name), joinpath(output, name))
    end
    println("Saved four-metric native BenchmarkTools evidence to ", output)
    exit()
end

length(ARGS) == 1 || error("Pass a new output directory: julia --project=. run.jl results")
output = abspath(only(ARGS))
ispath(output) &&
    error("Choose a new output directory; existing results are not overwritten")
mkpath(output)
project = dirname(Base.active_project())
source = joinpath(@__DIR__, "cases.jl")
catalog = ScenarioCatalog(@__DIR__,
    [ScenarioSpec("net-revenue"; source, factory = "SalesCases.$implementation",
         implementation, parameters = Dict("rows" => 4096),
         collectors = [:benchmark], repeatable = true)
     for implementation in ("dynamic", "typed")])

# JET checks the operation specialized for its prepared state type, in its own
# worker. It is deliberately separate from the BenchmarkTools measurement.
diagnosis = diagnose(catalog; project, tools = [:jet], threads = 1, timeout = 180)
all(record -> record["status"] == "complete" && record["correctness"] == "passed",
    diagnosis["records"]) || error("JET did not complete with a passing correctness oracle")
dynamic = only(filter(
    record -> record["implementation"] == "dynamic", diagnosis["records"]))
typed = only(filter(record -> record["implementation"] == "typed", diagnosis["records"]))
any(finding -> finding["rule_id"] == "inference.runtime_dispatch", dynamic["findings"]) ||
    error("The untyped control did not demonstrate runtime dispatch")
isempty(typed["findings"]) ||
    error("The typed control still has JET findings; inspect this tool version")

bundles = run_scenarios(catalog; project, samples = 20, threads = 1, timeout = 180,
    reports = joinpath(output, "bundles"))
all(
    bundle -> bundle_passed(bundle) &&
        bundle.manifest["scenario_evidence"]["correctness"] == "passed",
    bundles) ||
    error("A measurement did not complete with a passing correctness oracle")

function portable_finding(finding)
    message = finding["message"]
    # Keep the real diagnostic text, while replacing machine-specific roots.
    message = replace(message, dirname(source) => "<example>")
    message = replace(message, homedir() => "<home>")
    location = finding["location"]
    return Dict("rule_id" => finding["rule_id"], "severity" => finding["severity"],
        "message" => message, "evidence" => finding["evidence"],
        "location" => Dict("file" => basename(location["file"]), "line" => location["line"]))
end

records = [Dict("implementation" => record["implementation"],
               "tool" => record["tool"], "tool_version" => record["tool_version"],
               "status" => record["status"], "correctness" => record["correctness"],
               "analysis_scope" => record["analysis_scope"],
               "runtime" => record["runtime"],
               "findings" => portable_finding.(record["findings"]))
           for record in diagnosis["records"]]
measurements = [Dict("implementation" => bundle.manifest["scenario"]["implementation"],
                    "run_id" => bundle.manifest["run_id"],
                    "status" => bundle.manifest["state"],
                    "correctness" => bundle.manifest["scenario_evidence"]["correctness"],
                    "collector" => bundle.manifest["scenario_evidence"]["collector"],
                    "collector_version" => bundle.manifest["scenario_evidence"]["collector_version"],
                    "samples" => bundle.manifest["scenario_evidence"]["samples"],
                    "medians" => Dict(metric => median([sample[metric]
                                                        for sample in bundle.manifest["scenario_evidence"]["samples"]])
                    for metric in ("time", "bytes", "allocs")))
                for bundle in bundles]
summary = Dict("schema_version" => "perfchecker-jet-tutorial/1",
    "runtime" => Dict("language" => "julia", "version" => string(VERSION),
        "threads" => Threads.nthreads(), "os" => string(Sys.KERNEL), "arch" => string(Sys.ARCH)),
    "perfchecker_version" => string(Base.pkgversion(PerfChecker)),
    "rows" => 4096, "expected_result" => 129536.0,
    "measurement_scope" => "one warm operation on fresh prepared state; preparation and correctness verification excluded",
    "comparison_scope" => "two implementations on one local machine; not released package versions or a portable speed guarantee",
    "source_sha256" => bytes2hex(sha256(read(source))),
    "runner_sha256" => bytes2hex(sha256(read(@__FILE__))),
    "project_sha256" => bytes2hex(sha256(read(Base.active_project()))),
    "manifest_sha256" => bytes2hex(sha256(read(joinpath(project, "Manifest.toml")))),
    "diagnosis" => records, "measurements" => measurements)
open(io -> JSON.print(io, summary, 2), joinpath(output, "summary.json"), "w")
for measurement in measurements
    println(measurement["implementation"], ": ", measurement["medians"])
end
println("JET findings: ", length(dynamic["findings"]), " → ", length(typed["findings"]))
println("Saved verified evidence to ", output)
