const _PLOT_PALETTE = ["#2563eb", "#c2410c", "#0f766e", "#7e22ce",
    "#0369a1", "#be185d", "#4d7c0f", "#475569"]

function _metric_color(metric)
    index = metric == "julia.wall.time" ? 1 :
            metric in ("julia.gc.time", "julia.gc.fraction") ? 2 :
            metric == "julia.alloc.bytes" ? 3 : metric == "julia.alloc.count" ? 4 : 8
    return _PLOT_PALETTE[index]
end

function _version_tick_label(version)
    length(string(version)) > 16 ? first(string(version), 12) * "…" : string(version)
end

function make_colors(l)
    palette = Makie.to_color.(_PLOT_PALETTE)
    l <= length(palette) && return palette[1:l]
    return [palette;
            Makie.distinguishable_colors(l - length(palette),
                [palette; Makie.RGB(1, 1, 1); Makie.RGB(0, 0, 0)], dropseed = true)]
end

function _attributes(value)
    value isa NamedTuple && return value
    value isa AbstractDict && all(key -> key isa Symbol, keys(value)) &&
        return (; value...)
    throw(ArgumentError("Makie attributes must be a NamedTuple or a Symbol-keyed dictionary"))
end

function _figure(; figure_kwargs = (;), kwargs...)
    defaults = (fontsize = 14, figure_padding = 24,
        backgroundcolor = Makie.RGBf(0.97, 0.98, 0.99))
    Figure(; merge(defaults, (; kwargs...), _attributes(figure_kwargs))...)
end

function _recipe!(recipe, args...; plot_kwargs = (;), kwargs...)
    return recipe(args...; merge((; kwargs...), _attributes(plot_kwargs))...)
end

function _legend_colors(default, plot_kwargs)
    color = get(_attributes(plot_kwargs), :color, default)
    return color isa AbstractVector ? color : fill(color, length(default))
end

function _decorate!(figure; tool, tags = nothing, axis_kwargs = (;))
    attributes = _attributes(axis_kwargs)
    tags === nothing ||
        (tags isa Union{AbstractVector, Tuple} &&
         all(tag -> tag isa Union{Symbol, AbstractString}, tags)) ||
        throw(ArgumentError("tags must be a collection of Symbols or Strings"))
    for axis in filter(item -> item isa Axis, figure.content)
        for (key, value) in pairs(attributes)
            setproperty!(axis, key, value)
        end
        axis.title = "$(axis.title[]) · $tool"
        tag_label = tags === nothing || isempty(tags) ? "Tags: none" :
                    "Tags: $(join(string.(tags), ", "))"
        axis.subtitle = isempty(axis.subtitle[]) ? tag_label :
                        "$(axis.subtitle[]) · $tag_label"
    end
    return figure
end

function _legacy_figure(result; figure_kwargs = (;))
    figure = _figure(; figure_kwargs, size = (1100, 620))
    name = isempty(result.pkgs) ? "PerfChecker" :
           something(first(result.pkgs).name, "current")
    axis = Axis(figure[1, 1]; title = name)
    return figure, axis
end

function _no_samples!(figure, axis)
    Label(figure[1, 1], "No finite samples available"; tellwidth = false)
    hidedecorations!(axis)
    hidespines!(axis)
    return figure
end

function _finite_samples(values)
    Float64[value for value in values if value isa Real && isfinite(value)]
end

function _collector_label(definition)
    text = lowercase(string(definition))
    occursin("benchmarktools", text) && return "BenchmarkTools"
    occursin("chairmarks", text) && return "Chairmarks"
    occursin("profile-allocs", text) && return "Julia Profile.Allocs"
    occursin("line-tracking", text) && return "Julia allocation tracking"
    occursin("profile-walltime", text) && return "Julia wall-time profiler"
    occursin("profile-v1", text) && return "Julia CPU profiler"
    return "Collector: unspecified"
end

function _model_collector(plot)
    haskey(plot.options, "collector") && return _collector_label(plot.options["collector"])
    definitions = get(plot.options, "measurement_definitions", String[])
    isempty(definitions) && return "Collector: unspecified"
    return join(unique(_collector_label.(definitions)), " + ")
end

function smart_paths(paths)
    split_paths = map(splitpath ∘ normpath, paths)

    common = paths |> first |> dirname |> splitpath
    for path in split_paths
        to_pop = length(common)
        for name in Iterators.zip(common, path)
            name[1] == name[2] || break
            to_pop -= 1
        end
        foreach(_ -> pop!(common), 1:to_pop)
    end

    split_paths = map(path -> deleteat!(copy(path), 1:length(common)), split_paths)
    #=
    @info split_paths common
    for path in split_paths
        @info "debug 1" path length(common)
        foreach(_ -> popfirst!(path), 1:length(common))
        @info "debug 2" path length(common)
    end
    =#

    return joinpath(common...), map(joinpath, split_paths)
end

# Fix the maximum limit in plot by some epsilon for log scale plots
ϵ(x; adjust = 0.1 * log(10)) = x * exp(adjust)
