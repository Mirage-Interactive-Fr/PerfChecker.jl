using PerfChecker, PerfCheckerMakie, WGLMakie, JSON

length(ARGS) == 2 || error("Pass summary.json and a new export directory")
source, output = abspath.(ARGS)
ispath(output) && error("Choose a new export directory")
evidence = JSON.parsefile(source)
evidence["schema_version"] == "perfchecker-jet-tutorial/1" ||
    error("Unexpected evidence schema")
measurements = evidence["measurements"]
all(record -> record["status"] == "complete" && record["correctness"] == "passed",
    measurements) || error("Render only completed measurements with passing oracles")
categories = [record["implementation"] for record in measurements]
panels = [Dict("id" => metric, "title" => title,
              "xlabel" => "Implementation", "xunit" => "", "ylabel" => ylabel,
              "unit" => unit, "xkind" => "categorical", "categories" => categories,
              "yscale" => metric == "time" ? "log10" : "linear")
          for (metric, title, ylabel, unit) in (
    ("time", "Warm reduction: every timing sample", "Wall time", "s"),
    ("bytes", "Allocated bytes per reduction", "Allocated bytes", "By"),
    ("allocs", "Allocations per reduction", "Allocation count", "1"))]
rows = Dict{String, Any}[]
for record in measurements
    implementation = record["implementation"]
    for (index, sample) in enumerate(record["samples"])
        push!(rows,
            Dict("panel" => "time", "series" => "Timing samples",
                "x" => implementation, "value" => sample["time"], "style" => "scatter",
                "label" => "$implementation · sample $index · $(record["run_id"])"))
    end
    for metric in ("time", "bytes", "allocs")
        push!(rows,
            Dict("panel" => metric, "series" => "Median",
                "x" => implementation, "value" => record["medians"][metric],
                "style" => metric == "time" ? "scatter" : "bar",
                "label" => "$implementation · median of $(length(record["samples"])) samples"))
    end
end
metadata = Dict(key => evidence[key]
for key in ("runtime", "perfchecker_version", "rows", "expected_result",
    "source_sha256", "runner_sha256", "project_sha256", "manifest_sha256"))
metadata["run_ids"] = [record["run_id"] for record in measurements]
metadata["collector_versions"] = [record["collector_version"] for record in measurements]
metadata["evidence_file"] = basename(source)
model = observation_plot("jet-dispatch-measurements", rows;
    title = "Same revenue calculation, different element types", panels,
    collector = "BenchmarkTools (through PerfChecker run_scenarios)",
    scope = evidence["measurement_scope"] * "; " * evidence["comparison_scope"],
    description = "JET findings are shown separately; this plot contains only measured timing and allocation evidence.",
    metadata)
mkpath(output)
open(io -> JSON.print(io, Dict("plot" => performance_plot_dict(model)), 2),
    joinpath(output, "measurements.json"), "w")
write(joinpath(output, "measurements.html"), performance_plot_html(model))
println("Rendered saved measurements; no scenario or analyzer was rerun")
