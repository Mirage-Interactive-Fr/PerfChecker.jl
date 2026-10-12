using PerfChecker, JSON, SHA, Statistics

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
