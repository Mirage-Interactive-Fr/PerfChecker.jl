"""
    observation_plot(id, rows; title, panels, collector, scope, description="", metadata=Dict())

Build a saved-evidence plot with explicit axes rather than package-version axes.
Use this for request sizes, operation indices, implementation names, startup
phases or native-profiler timelines. No measurement is run and no file is written.
Render the returned `PerfChecker.PerformancePlot` with `performance_figure`, or
load WGLMakie and call `PerfChecker.performance_plot_html` for an interactive export.

`panels` is a nonempty vector of dictionaries. Each panel requires a unique `id`,
`title`, `xlabel`, `xunit`, `ylabel`, `unit` and `xkind` (`"numeric"` or
`"categorical"`). A categorical panel also requires an ordered, distinct
`categories` vector. Optional `yscale` is `"linear"` (default) or `"log10"`.
Units are supplied explicitly, including `""` for a categorical axis; neither
units nor package versions are inferred from values or labels.

Each row requires `panel`, `series`, `x` and `value`. `x` must match its panel's
axis. `value` is finite numeric evidence, or `nothing`/`missing` for an unavailable
observation. Unavailable rows remain in the model and inspector but have no mark;
zero is never substituted. Logarithmic panels require strictly positive values.
Optional `label` adds context, `version` records a real package version, and
`style` selects `"scatter"` (default), `"line"`, `"scatterline"` or `"bar"`.
Bars require a linear y-axis so that their zero baseline remains meaningful.
Rows in a series/version group must use the same style. Lines follow recorded
row order; callers must supply meaningful order rather than imply a time axis.

`collector` names the actual tool. `scope` states what was measured, for example
"one loopback process; application bytes are not wire bytes". `metadata` retains
explicit provenance such as source SHA-256 and run IDs. Inputs are deep-copied.
The interactive view filters panels, series and recorded versions without
changing observations, inspects exact rows and downloads the complete model.

# Example
The values in this minimal example are illustrative. Replace them with your
recorded observations and attach their provenance in `metadata` for publication.
```julia
using PerfChecker, PerfCheckerMakie, WGLMakie
panels = [Dict("id" => "time", "title" => "Warm requests",
    "xlabel" => "Request body", "xunit" => "By", "ylabel" => "Round trip",
    "unit" => "s", "xkind" => "numeric")]
rows = [Dict("panel" => "time", "series" => "Oxygen 1.11.0",
    "x" => 4096, "value" => 0.002, "label" => "Illustrative sample")]
model = observation_plot("request-time", rows; title = "Recorded request",
    panels, collector = "PerfChecker network runner", scope = "Loopback only")
html = performance_plot_html(model)
```
"""
function observation_plot(id::AbstractString, rows::AbstractVector;
        title::AbstractString, panels::AbstractVector, collector::AbstractString,
        scope::AbstractString, description::AbstractString = "", metadata::AbstractDict = Dict())
    all(value -> !isempty(strip(value)), (id, title, collector, scope)) ||
        throw(ArgumentError("id, title, collector and scope must be nonempty"))
    isempty(panels) && throw(ArgumentError("at least one panel is required"))
    copied_panels = Dict{String, Any}[]
    for original in panels
        original isa AbstractDict || throw(ArgumentError("panels must be dictionaries"))
        panel = Dict{String, Any}(string(k) => deepcopy(v) for (k, v) in original)
        for key in ("id", "title", "xlabel", "xunit", "ylabel", "unit", "xkind")
            get(panel, key, nothing) isa AbstractString ||
                throw(ArgumentError("panel requires string $key"))
        end
        isempty(strip(panel["id"])) && throw(ArgumentError("panel id cannot be empty"))
        panel["xkind"] in ("numeric", "categorical") ||
            throw(ArgumentError("xkind must be numeric or categorical"))
        get(panel, "yscale", "linear") in ("linear", "log10") ||
            throw(ArgumentError("yscale must be linear or log10"))
        if panel["xkind"] == "categorical"
            categories = get(panel, "categories", nothing)
            categories isa AbstractVector && !isempty(categories) &&
                all(value -> value isa AbstractString, categories) &&
                length(unique(categories)) == length(categories) ||
                throw(ArgumentError("categorical panels require distinct string categories"))
        end
        push!(copied_panels, panel)
    end
    ids = [panel["id"] for panel in copied_panels]
    length(unique(ids)) == length(ids) || throw(ArgumentError("panel ids must be distinct"))
    by_id = Dict(panel["id"] => panel for panel in copied_panels)
    copied_rows = Dict{String, Any}[]
    styles = Dict{Tuple{String, String, String}, String}()
    for original in rows
        original isa AbstractDict || throw(ArgumentError("rows must be dictionaries"))
        row = Dict{String, Any}(string(k) => deepcopy(v) for (k, v) in original)
        get(row, "panel", nothing) isa AbstractString && haskey(by_id, row["panel"]) ||
            throw(ArgumentError("row refers to an unknown panel"))
        get(row, "series", nothing) isa AbstractString && !isempty(strip(row["series"])) ||
            throw(ArgumentError("row requires a nonempty series"))
        panel = by_id[row["panel"]]
        x = get(row, "x", nothing)
        valid_x = panel["xkind"] == "numeric" ?
                  x isa Real && !(x isa Bool) && isfinite(x) :
                  x isa AbstractString && x in panel["categories"]
        valid_x || throw(ArgumentError("row x does not match its explicit panel axis"))
        haskey(row, "value") || throw(ArgumentError("row requires value"))
        value = row["value"]
        if value === nothing || ismissing(value)
            row["value"] = nothing
        else
            value isa Real && !(value isa Bool) && isfinite(value) ||
                throw(ArgumentError("value must be finite or explicitly unavailable"))
            get(panel, "yscale", "linear") == "log10" && value <= 0 &&
                throw(ArgumentError("log10 values must be positive"))
        end
        for key in ("label", "version")
            !haskey(row, key) || row[key] isa AbstractString ||
                throw(ArgumentError("$key must be a string"))
        end
        style = get(row, "style", "scatter")
        style in ("scatter", "line", "scatterline", "bar") ||
            throw(ArgumentError("unsupported observation style"))
        style == "bar" && get(panel, "yscale", "linear") == "log10" &&
            throw(ArgumentError("bars require a linear axis with a zero baseline"))
        row["style"] = style
        key = (String(row["panel"]), String(row["series"]), String(get(row, "version", "")))
        get(styles, key, style) == style ||
            throw(ArgumentError("one series/version group cannot mix styles"))
        styles[key] = style
        push!(copied_rows, row)
    end
    return PerfChecker.PerformancePlot(String(id), :observation_series, String(title),
        String(description), Dict{String, Any}("x" => "x", "y" => "value",
            "color" => "series", "panel" => "panel"),
        copied_rows,
        Dict{String, Any}(
            "panels" => copied_panels, "collector_label" => String(collector),
            "scope" => String(scope), "metadata" => deepcopy(metadata)))
end

function _observation_series_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    panels = plot.options["panels"]
    columns = min(2, length(panels))
    figure = _figure(; figure_kwargs, size = (1100, 390cld(length(panels), columns) + 100))
    Label(figure[0, 1:columns], plot.title; fontsize = 22, tellwidth = false)
    groups = unique((row["series"], get(row, "version", "")) for row in plot.data)
    colors = Dict(group => _PLOT_PALETTE[mod1(i, length(_PLOT_PALETTE))]
    for (i, group) in enumerate(groups))
    for (i, panel) in enumerate(panels)
        axis = Axis(figure[cld(i, columns), mod1(i, columns)]; title = panel["title"],
            xlabel = panel["xlabel"] *
                     (isempty(panel["xunit"]) ? "" : " ($(panel["xunit"]))"),
            ylabel = panel["ylabel"] *
                     (isempty(panel["unit"]) ? "" : " ($(panel["unit"]))"),
            yscale = get(panel, "yscale", "linear") == "log10" ? log10 : identity)
        rows = filter(row -> row["panel"] == panel["id"], plot.data)
        local_groups = unique((row["series"], get(row, "version", "")) for row in rows)
        bar_groups = filter(local_groups) do group
            any(
                row -> (row["series"], get(row, "version", "")) == group &&
                    row["style"] == "bar",
                rows)
        end
        coordinates = sort!(unique([panel["xkind"] == "numeric" ? Float64(row["x"]) :
                                    Float64(findfirst(==(row["x"]), panel["categories"]))
                                    for row in rows]))
        spacing = length(coordinates) > 1 ? minimum(diff(coordinates)) : 1.0
        bar_width = 0.75spacing / max(1, length(bar_groups))
        for group in local_groups
            selected = filter(
                row -> (row["series"], get(row, "version", "")) == group, rows)
            isempty(selected) && continue
            # NaNs leave gaps at unavailable rows; no line bridges missing evidence.
            xs = [panel["xkind"] == "numeric" ? Float64(row["x"]) :
                  Float64(findfirst(==(row["x"]), panel["categories"])) for row in selected]
            ys = [row["value"] === nothing ? NaN : Float64(row["value"])
                  for row in selected]
            label = isempty(last(group)) ? first(group) : "$(first(group)) · $(last(group))"
            style = first(selected)["style"]
            if style == "bar"
                shift = (findfirst(==(group), bar_groups) - (length(bar_groups) + 1) / 2) *
                        bar_width
                xs .+= shift
            end
            recipe = style == "bar" ? barplot! :
                     style == "line" ? lines! :
                     style == "scatterline" ? scatterlines! : scatter!
            if style == "bar"
                _recipe!(recipe, axis, xs, ys; plot_kwargs, color = colors[group], label,
                    width = bar_width)
            else
                _recipe!(recipe, axis, xs, ys; plot_kwargs, color = colors[group], label)
            end
        end
        if panel["xkind"] == "categorical"
            axis.xticks = (collect(eachindex(panel["categories"])), panel["categories"])
            axis.xticklabelrotation = pi / 4
        end
        length(local_groups) > 1 && axislegend(axis; position = :lt, labelsize = 10)
    end
    Label(figure[cld(length(panels), columns) + 1, 1:columns], plot.options["scope"];
        tellwidth = false, fontsize = 12)
    return _add_inspector(figure)
end
