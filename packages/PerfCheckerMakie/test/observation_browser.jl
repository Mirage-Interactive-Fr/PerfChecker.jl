# Browser evidence is exported through the same public API as user plots.
using PerfChecker, PerfCheckerMakie, WGLMakie
panels = [
    Dict("id" => "time", "title" => "Elapsed time", "xlabel" => "Operation", "xunit" => "",
        "ylabel" => "Duration", "unit" => "s", "xkind" => "numeric"),
    Dict("id" => "signed", "title" => "Signed change",
        "xlabel" => "Implementation", "xunit" => "",
        "ylabel" => "Change", "unit" => "By", "xkind" => "categorical", "categories" => [
            "dynamic", "typed"]),
    Dict("id" => "irregular", "title" => "Irregular recorded positions",
        "xlabel" => "Request body", "xunit" => "By",
        "ylabel" => "Count", "unit" => "1", "xkind" => "numeric")]
rows = Dict{String, Any}[]
for (version, scale) in (("1.0.0", 1), ("1.0.1", 2))
    for (x, value) in ((1, 0.25), (2, nothing), (3, 0.0))
        push!(rows,
            Dict("panel" => "time", "series" => "Recorded samples", "version" => version,
                "x" => x, "value" => value === nothing ? nothing : value * scale,
                "style" => "scatterline", "label" => x == 1 ?
                                                     "</script><script>globalThis.injected=true</script>" :
                                                     "Sample $x"))
    end
    for (x, value) in (("dynamic", -4scale), ("typed", 0))
        push!(rows,
            Dict("panel" => "signed", "series" => "Measured change", "version" => version,
                "x" => x, "value" => value, "style" => "bar", "label" => x))
    end
end
for x in (0, 0.001, 100)
    push!(rows,
        Dict("panel" => "irregular", "series" => "Irregular samples", "x" => x,
            "value" => 1, "style" => "bar"))
end
model = observation_plot("browser-evidence", rows; title = "Browser evidence", panels,
    collector = "Measured regression fixture", scope = "Signed values and unavailable rows")
write(only(ARGS), performance_plot_html(model))
