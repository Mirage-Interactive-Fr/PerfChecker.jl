"""
    table_to_pie(table, Val(:alloc); pkg_name="", tags=nothing, min_percentage=5, top=40,
                 figure_kwargs=(;), axis_kwargs=(;), plot_kwargs=(;))

Render positive finite allocation bytes by source location, grouping sites below
the share threshold and capping legend entries with `top`. Tables use filename/
line (or filenames/linenumbers) and bytes columns. Empty or zero-only evidence
returns a labeled Figure. Explicit attribute bundles target Figure, Axis and
pie; the title names Julia allocation tracking and the subtitle lists tags.
This reads saved bytes without rerunning a check or writing an image.
"""
function PerfChecker.table_to_pie(x::Table, ::Val{:alloc}; pkg_name = "", tags = nothing,
        min_percentage::Real = 5, top::Integer = 40,
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    PerfChecker._group_allocation_pie(Dict{String, Any}[]; min_percentage, top)
    filenames = hasproperty(x, :filename) ? x.filename : x.filenames
    lines = hasproperty(x, :line) ? x.line : x.linenumbers
    figure = _figure(; figure_kwargs, size = (1100, 620))
    axis = Axis(figure[1, 1];
        title = isempty(pkg_name) ? "Allocated bytes" : "Allocated bytes for $pkg_name",
        aspect = DataAspect())
    indices = [i
               for i in eachindex(x.bytes)
               if x.bytes[i] isa Real && isfinite(x.bytes[i]) && x.bytes[i] > 0]
    if isempty(indices)
        _no_samples!(figure, axis)
    else
        paths = smart_paths(filenames[indices])[2] .* " — line " .* string.(lines[indices])
        records = PerfChecker._group_allocation_pie(
            [Dict{String, Any}("label" => paths[j], "bytes" => x.bytes[i])
             for (j, i) in pairs(indices)];
            min_percentage, top)
        data = Float64[item["bytes"] for item in records]
        paths = ["$(item["label"]) · $(round(item["percentage"]; digits = 1))%"
                 for item in records]
        colors = make_colors(length(records))
        _recipe!(pie!, axis, data; plot_kwargs, color = colors, inner_radius = 2,
            radius = 4, strokecolor = :white, strokewidth = 5)
        Legend(figure[1, 2],
            [PolyElement(color = c) for c in _legend_colors(colors, plot_kwargs)], paths)
        hidedecorations!(axis)
        hidespines!(axis)
    end
    return _decorate!(figure; tool = "Julia allocation tracking", tags, axis_kwargs)
end

"""
Return version-name/Figure pairs for saved allocation tables, retaining result
tags and package/version names. Keywords go to `table_to_pie`; no measurement
or export occurs. Empty tables retain a labeled Figure in the collection.
"""
function PerfChecker.checkres_to_pie(x::PerfChecker.CheckerResult, ::Val{:alloc}; kwargs...)
    name(i) = something(x.pkgs[i].name, "current") * "_v" * string(x.pkgs[i].version)
    return [name(i) => table_to_pie(
                x.tables[i], Val(:alloc); pkg_name = name(i), tags = x.tags, kwargs...)
            for i in eachindex(x.tables)]
end

"""
Render saved allocated bytes aggregated by file across versions. Missing files
remain gaps, not zero observations; nonfinite entries are excluded. Accept
explicit Figure, Axis and scatterlines attributes and an optional title.
Version ticks default to pi/2, with collector and result tags visible. Return a
labeled Figure for empty evidence. No measurement or file export occurs.
"""
function PerfChecker.checkres_to_scatterlines(x::PerfChecker.CheckerResult, ::Val{:alloc};
        title = "", figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    figure, axis = _legacy_figure(x; figure_kwargs)
    isempty(title) || (axis.title = title)
    files = Dict{String, Vector{Tuple{Int, Float64}}}()
    for (i, table) in pairs(x.tables)
        filenames = hasproperty(table, :filename) ? table.filename : table.filenames
        for filename in unique(filenames)
            samples = _finite_samples(table.bytes[filenames .== filename])
            isempty(samples) && continue
            push!(get!(files, String(filename), Tuple{Int, Float64}[]), (i, sum(samples)))
        end
    end
    if isempty(files)
        _no_samples!(figure, axis)
    else
        names = sort!(collect(keys(files)))
        labels = smart_paths(names)[2]
        colors = make_colors(length(names))
        for (i, name) in pairs(names)
            values = Dict(files[name])
            # An absent file is unavailable evidence, never an invented zero.
            ys = [get(values, j, NaN) for j in eachindex(x.tables)]
            _recipe!(scatterlines!, axis, eachindex(ys), ys;
                plot_kwargs, label = labels[i], color = colors[i])
        end
        axislegend(axis; position = :lt)
    end
    axis.xticks = (collect(eachindex(x.pkgs)), string.([pkg.version for pkg in x.pkgs]))
    isempty(x.pkgs) || xlims!(axis, 0.5, length(x.pkgs) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "version"
    axis.ylabel = "allocated bytes"
    axis.yscale = Makie.pseudolog10
    return _decorate!(
        figure; tool = "Julia allocation tracking", tags = x.tags, axis_kwargs)
end
