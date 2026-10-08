function _checker_overlay(
        result, collector; figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    figure, axis = _legacy_figure(result; figure_kwargs)
    isempty(result.tables) && return _decorate!(
        _no_samples!(figure, axis); tool = collector, tags = result.tags, axis_kwargs)
    props = TypedTables.columnnames(first(result.tables))
    order = sortperm([string(pkg.version) for pkg in result.pkgs];
        by = label -> PerfChecker._version_point_key(Dict("version" => label)))
    versions = string.([result.pkgs[i].version for i in order])
    colors = make_colors(length(props))
    captured = false
    for (i, prop) in pairs(props)
        samples = [_finite_samples(getproperty(result.tables[j], prop)) for j in order]
        values = [isempty(sample) ? nothing : minimum(sample) for sample in samples]
        available = filter(!isnothing, values)
        isempty(available) && continue
        captured = true
        baseline = minimum(available)
        ratios = [isnothing(value) ? nothing :
                  PerfChecker._relative_measurement(value, baseline) for value in values]
        label = string(prop) * (all(iszero, available) ? " (0/0: unchanged)" : "")
        _recipe!(scatterlines!, axis, eachindex(versions),
            [isnothing(r) ? NaN : r for r in ratios];
            plot_kwargs, label, color = colors[i], linewidth = 2)
    end
    if captured
        hlines!(axis, [1.0]; color = (:gray, 0.6), linestyle = :dash)
        axislegend(axis; position = :lt)
    else
        _no_samples!(figure, axis)
    end
    axis.xticks = (collect(eachindex(versions)), versions)
    isempty(versions) || xlims!(axis, 0.5, length(versions) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "version"
    axis.ylabel = "minimum per version / minimum across versions"
    Label(figure[2, 1],
        "Equal zeros = 1 (unchanged); nonzero / zero or unavailable samples = gap.";
        tellwidth = false)
    return _decorate!(
        _add_inspector(figure); tool = collector, tags = result.tags, axis_kwargs)
end

"""
    checkres_to_scatterlines(result, Val(:benchmark); figure_kwargs=(;), axis_kwargs=(;), plot_kwargs=(;))

Render each saved metric's finite version minima relative to its finite minimum
across versions. Equal zeros display at one; a nonzero value over zero or an
absent sample is a gap. NaN and Inf are excluded before finding minima. Return
a Makie Figure, including a labeled figure when no finite metric exists.
The title names BenchmarkTools and the subtitle shows result tags. Version
ticks are vertical by default. Explicit Figure, Axis and scatterlines attribute
bundles override presentation defaults without rerunning measurements.
"""
function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:benchmark};
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    return _checker_overlay(x, "BenchmarkTools"; figure_kwargs, axis_kwargs, plot_kwargs)
end

function _checker_boxplots(result, collector; kwarg::Symbol = :times,
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    figure, axis = _legacy_figure(result; figure_kwargs)
    datax, datay = Int[], Float64[]
    for (i, table) in pairs(result.tables)
        samples = _finite_samples(getproperty(table, kwarg))
        append!(datax, fill(i, length(samples)))
        append!(datay, samples)
    end
    if isempty(datay)
        _no_samples!(figure, axis)
    else
        _recipe!(boxplot!, axis, datax, datay; plot_kwargs, label = string(kwarg))
        Legend(figure[1, 2], axis)
    end
    axis.xticks = (
        collect(eachindex(result.pkgs)), string.([pkg.version for pkg in result.pkgs]))
    isempty(result.pkgs) || xlims!(axis, 0.5, length(result.pkgs) + 0.5)
    axis.xlabel = "version"
    units = collector == "BenchmarkTools" ?
            Dict(:times => "Elapsed time (ns)", :gctimes => "GC time (ns)",
        :memory => "Allocated memory (bytes)", :bytes_or_memory => "Allocated memory (bytes)",
        :allocs => "Allocation count") :
            Dict(:times => "Elapsed time (s)", :gctimes => "GC fraction (unitless)",
        :bytes => "Allocated memory (bytes)", :bytes_or_memory => "Allocated memory (bytes)",
        :allocs => "Allocation count")
    axis.ylabel = get(units, kwarg, string(kwarg))
    axis.xticklabelrotation = pi / 2
    return _decorate!(figure; tool = collector, tags = result.tags, axis_kwargs)
end

"""
    checkres_to_boxplots(result, Val(:benchmark); kwarg=:times, figure_kwargs=(;), axis_kwargs=(;), plot_kwargs=(;))

Render finite saved samples from the selected table column as version boxplots.
Values retain their collector units: `:times` and `:gctimes` are nanoseconds,
`:memory` is bytes, and `:allocs` is an allocation count.
Empty or entirely nonfinite columns produce
a labeled Makie Figure; missing columns raise the normal property access error.
The title names BenchmarkTools and the subtitle shows tags. Attribute bundles
target Figure, Axis and boxplot respectively; version labels default to pi/2.
No workload is executed or file written.
"""
function PerfChecker.checkres_to_boxplots(x::PerfChecker.CheckerResult, ::Val{:benchmark};
        kwarg::Symbol = :times, figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    return _checker_boxplots(
        x, "BenchmarkTools"; kwarg, figure_kwargs, axis_kwargs, plot_kwargs)
end
