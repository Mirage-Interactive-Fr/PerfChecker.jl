module UnicodePlotsExt

using PerfChecker
using UnicodePlots

_short_label(value; width = 34) = first(String(value), min(length(String(value)), width))

function _bar_plot(plot::PerfChecker.PerformancePlot, label_key::String,
        value_key::String; width::Integer, height::Integer, scale::Float64 = 1.0,
        suffix::String = "")
    records = filter(item -> get(item, value_key, nothing) isa Number, plot.data)
    isempty(records) && throw(ArgumentError("performance plot has no numeric data"))
    labels = [_short_label(get(item, label_key, "item")) for item in records]
    values = [Float64(item[value_key]) * scale for item in records]
    title = isempty(suffix) ? plot.title : "$(plot.title) ($suffix)"
    return UnicodePlots.barplot(labels, values; title, width, height)
end

"Render the common performance-plot grammar directly in a text terminal."
function PerfChecker.terminal_plot(plot::PerfChecker.PerformancePlot;
        width::Integer = 80, height::Integer = 20)
    isempty(plot.data) && throw(ArgumentError("performance plot has no data"))
    if plot.kind === :normalized_metrics
        versions = plot.options["versions"]
        values = [row["ratio"] for row in plot.data if row["ratio"] isa Number]
        chart = UnicodePlots.lineplot([1, max(2, length(versions))], [1.0, 1.0];
            title = plot.title, xlabel = "versions: $(join(versions, ", "))",
            ylabel = "ratio / $(plot.options["reference_version"])",
            width, height, name = "reference = 1", color = :cyan,
            ylim = (0.0, max(1.0, isempty(values) ? 1.0 : maximum(values)) * 1.15))
        for metric in unique(row["metric"] for row in plot.data)
            rows = Dict(row["version"] => row
            for row in plot.data if row["metric"] == metric)
            xs, ys = Int[], Float64[]
            name = replace(metric, "julia." => "")
            for (index, version) in pairs(versions)
                ratio = get(get(rows, version, Dict()), "ratio", nothing)
                if ratio isa Number
                    push!(xs, index)
                    push!(ys, ratio)
                elseif !isempty(xs)
                    UnicodePlots.lineplot!(chart, xs, ys; name)
                    empty!(xs)
                    empty!(ys)
                end
            end
            isempty(xs) || UnicodePlots.lineplot!(chart, xs, ys; name)
        end
        return chart
    elseif plot.kind === :version_series
        labels = String[String(item["version"]) for item in plot.data]
        values = Float64[Float64(item["value"]) for item in plot.data]
        return UnicodePlots.lineplot(collect(eachindex(values)), values;
            title = plot.title,
            xlabel = "versions: $(first(labels)) … $(last(labels))",
            ylabel = String(get(plot.options, "unit", "")), width, height,
            name = "median")
    elseif plot.kind === :version_delta
        records = filter(item -> get(item, "relative_delta", nothing) isa Number,
            plot.data)
        if isempty(records)
            return UnicodePlots.scatterplot(Float64[], Float64[];
                title = "$(plot.title) — relative change unavailable",
                xlabel = "Zero or missing baseline: inspect absolute values",
                xlim = (0.0, 1.0), ylim = (0.0, 1.0), width, height)
        end
        # UnicodePlots.barplot only accepts nonnegative heights. Improvements
        # are negative deltas and must retain their sign in the terminal too.
        labels = String[item["candidate_version"] for item in records]
        values = Float64[100 * item["relative_delta"] for item in records]
        chart = UnicodePlots.lineplot([1, max(2, length(values))], [0.0, 0.0];
            title = plot.title, xlabel = "versions: $(join(labels, ", "))",
            ylabel = "change (%)", width, height,
            ylim = (min(-1.0, minimum(values) * 1.1), max(1.0, maximum(values) * 1.1)),
            name = "baseline = 0", color = :cyan)
        return UnicodePlots.scatterplot!(chart, collect(eachindex(values)), values;
            name = "signed change", color = :yellow)
    elseif plot.kind === :distribution
        values = Float64[Float64(item["value"]) for item in plot.data]
        return UnicodePlots.histogram(values; title = plot.title, width, height)
    elseif plot.kind === :allocation_pie
        return _bar_plot(plot, "label", "percentage"; width, height, suffix = "%")
    elseif plot.kind === :allocation_files
        return _bar_plot(plot, "file", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind === :allocation_lines
        return _bar_plot(plot, "label", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind === :allocation_heatmap
        return _bar_plot(plot, "label", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph)
        records = filter(item -> Int(item["depth"]) == 1, plot.data)
        isempty(records) && (records = plot.data)
        adapted = PerfChecker.PerformancePlot(plot.id, plot.kind, plot.title,
            plot.description, plot.encoding, records, plot.options)
        return _bar_plot(adapted, "label", "percentage";
            width, height, suffix = "% inclusive")
    elseif plot.kind === :time_allocation_tradeoff
        x = Float64[Float64(item["bytes"]) for item in plot.data]
        y = Float64[Float64(item["time"]) for item in plot.data]
        return UnicodePlots.scatterplot(x, y; title = plot.title,
            xlabel = "allocated bytes", ylabel = "time (s)", width, height)
    end
    throw(ArgumentError("unsupported terminal plot kind $(plot.kind)"))
end

function PerfChecker.terminal_plot(comparison::PerfChecker.VersionComparison;
        series_id = nothing, width::Integer = 80, height::Integer = 20)
    isempty(comparison.series) && throw(ArgumentError("comparison has no series"))
    if series_id === nothing
        catalog = PerfChecker._normalized_catalog(comparison.series)
        isempty(catalog) || return PerfChecker.terminal_plot(
            PerfChecker._normalized_plot(comparison.series, first(catalog)); width, height)
    end
    series = series_id === nothing ? first(comparison.series) :
             only(
        filter(item -> item["series_id"] == String(series_id), comparison.series))
    points = series["points"]
    isempty(points) && throw(ArgumentError("selected series has no points"))
    labels = String[String(point["version"]) for point in points]
    values = Float64[Float64(point["median"]) for point in points]
    title = "$(series["package"])/$(series["feature"]) — $(series["metric"])"
    plot = UnicodePlots.lineplot(collect(eachindex(values)), values; title,
        xlabel = "versions: $(first(labels)) … $(last(labels))",
        ylabel = String(series["unit"]), width, height, name = "median")
    return plot
end

function PerfChecker.terminal_plot(bundle::PerfChecker.RunBundle; plot_id = nothing,
        kind = nothing, version = nothing, top::Integer = 20,
        width::Integer = 80, height::Integer = 20)
    catalog = PerfChecker.plot_catalog(bundle)
    isempty(catalog) && throw(ArgumentError("run bundle exposes no performance plots"))
    entries = kind === nothing ? catalog :
              filter(item -> item["kind"] == string(kind), catalog)
    isempty(entries) && throw(ArgumentError("no terminal plot matches kind $kind"))
    entry = plot_id === nothing ? first(entries) :
            only(
        filter(item -> item["id"] == String(plot_id), entries))
    plot = PerfChecker.performance_plot(bundle, entry["id"]; version, top)
    return PerfChecker.terminal_plot(plot; width, height)
end

end
