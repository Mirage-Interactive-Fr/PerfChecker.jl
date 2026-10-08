"""
    checkres_figures(result, Val(backend); kinds=nothing, metrics=nothing, figure_kwargs=(;),
                    axis_kwargs=(;), plot_kwargs=(;))

Collect named Makie figures from saved `CheckerResult` tables. `backend` is
`:alloc`, `:benchmark` or `:chairmark`. `kinds` selects `:trajectory`,
`:distribution` (timing collectors) or `:pie` (allocations). Defaults select
all applicable kinds, in that order. Distributions default to four metrics:
BenchmarkTools `:times`, `:gctimes`, `:memory`, `:allocs`; Chairmarks `:times`,
`:gctimes`, `:bytes`, `:allocs`. The duplicate `:bytes_or_memory` alias is omitted.
Pass `metrics` to select a distinct subset for distributions; selected columns
must exist in every saved table. Metrics cannot be supplied for an allocation
collector or a selection without distributions. Empty, duplicated, missing or
unsupported selections raise `ArgumentError` before rendering.
No checks are rerun and no files are written. Names include each distribution's
metric as well as the collector, package, version and tags;
allocation pies retain one figure per version. Presentation attributes use the
same explicit bundles as `performance_figure`. Use `saveplot` to export this
collection to an explicit directory.
"""
function checkres_figures(result::PerfChecker.CheckerResult, ::Val{backend};
        kinds = nothing, metrics = nothing, figure_kwargs = (;),
        axis_kwargs = (;), plot_kwargs = (;)) where {backend}
    backend in (:alloc, :benchmark, :chairmark) ||
        throw(ArgumentError("supported collectors: alloc, benchmark, chairmark"))
    applicable = backend === :alloc ? (:trajectory, :pie) : (:trajectory, :distribution)
    selected = isnothing(kinds) ? collect(applicable) : collect(kinds)
    !isempty(selected) && all(kind -> kind in applicable, selected) &&
        length(unique(selected)) == length(selected) ||
        throw(ArgumentError("select distinct applicable figure kinds from $applicable"))
    isempty(result.pkgs) && throw(ArgumentError("result has no package versions"))
    supported_metrics = backend === :benchmark ? (:times, :gctimes, :memory, :allocs) :
                        (:times, :gctimes, :bytes, :allocs)
    distributions = :distribution in selected
    !isnothing(metrics) && !distributions &&
        throw(ArgumentError("metrics applies only to timing distributions"))
    selected_metrics = !distributions ? Symbol[] :
                       isnothing(metrics) ? collect(supported_metrics) : collect(metrics)
    if distributions
        !isempty(selected_metrics) &&
            all(metric -> metric in supported_metrics, selected_metrics) &&
            length(unique(selected_metrics)) == length(selected_metrics) ||
            throw(ArgumentError("select distinct distribution metrics from $supported_metrics"))
        all(
            table -> all(
                metric -> metric in TypedTables.columnnames(table), selected_metrics),
            result.tables) ||
            throw(ArgumentError("selected distribution metrics must exist in every saved table"))
    end
    package = something(first(result.pkgs).name, "current")
    tags = join(string.(something(result.tags, Symbol[])), "_")
    prefix = "$(backend)_$(package)_$(join(string.([pkg.version for pkg in result.pkgs]), "-"))"
    isempty(tags) || (prefix *= "_$tags")
    figures = Pair{String, Figure}[]
    for kind in selected
        if kind === :trajectory
            push!(figures,
                "$(prefix)_trajectory" => PerfChecker.checkres_to_scatterlines(
                    result, Val(backend);
                    figure_kwargs, axis_kwargs, plot_kwargs))
        elseif kind === :distribution
            for metric in selected_metrics
                push!(figures,
                    "$(prefix)_distribution_$(metric)" => PerfChecker.checkres_to_boxplots(
                        result, Val(backend); kwarg = metric,
                        figure_kwargs, axis_kwargs, plot_kwargs))
            end
        else
            for (name, figure) in PerfChecker.checkres_to_pie(result, Val(backend);
                figure_kwargs, axis_kwargs, plot_kwargs)
                push!(figures, "$(backend)_$(name)_$(tags)_pie" => figure)
            end
        end
    end
    return figures
end

function _export_name(value)
    name = replace(string(value), r"[^A-Za-z0-9_.-]" => "_")
    name = strip(name, ['.', '_'])
    isempty(name) && throw(ArgumentError("figure name must contain a filename character"))
    stem = uppercase(first(split(name, '.')))
    stem in (
        "CON", "PRN", "AUX", "NUL", ["COM$i" for i in 1:9]..., ["LPT$i" for i in 1:9]...) &&
        (name = "figure_" * name)
    ncodeunits(name) <= 180 || throw(ArgumentError("figure name is too long"))
    return name
end

"""
    saveplot(path, figure::Makie.Figure; overwrite=false, kwargs...) -> String
    saveplot(directory, named_figures; format=:svg, overwrite=false, kwargs...) -> Vector{String}

Export existing figures using the active Makie backend. Load CairoMakie for
SVG/PNG output. Single-file paths must end in `.svg` or `.png`; their parent
directory must exist. The collection overload creates its explicit directory,
sanitizes names into portable filename components and rejects collisions
(including case-insensitive collisions) before writing. It accepts the pairs
returned by `checkres_figures` or an explicit collection of name/figure pairs.
Existing files and symlinks are preserved unless `overwrite=true`; directories
are never replaced. All destinations are checked before a collection is
exported. Rendering uses a temporary file in the destination filesystem and
cleans it up on failure; failures can leave earlier completed collection files.
Additional keywords go to Makie's `save`, for example `px_per_unit=2` for PNG.
Return absolute paths. No workload is rerun; provenance remains in the saved
result rather than being inferred from an image.
"""
function PerfChecker.saveplot(path::AbstractString, figure::Figure;
        overwrite::Bool = false, kwargs...)
    destination = abspath(path)
    extension = lowercase(splitext(destination)[2])
    extension in (".svg", ".png") ||
        throw(ArgumentError("figure export requires .svg or .png"))
    isdir(dirname(destination)) || throw(ArgumentError("destination parent does not exist"))
    _check_destination(destination, overwrite)
    mktempdir(dirname(destination)) do temporary
        rendered = joinpath(temporary, "figure" * extension)
        Makie.save(rendered, figure; kwargs...)
        _check_destination(destination, overwrite)
        mv(rendered, destination; force = overwrite)
    end
    return destination
end

function _check_destination(path, overwrite)
    isdir(path) && throw(ArgumentError("destination is a directory: $path"))
    (ispath(path) || islink(path)) && !overwrite &&
        throw(ArgumentError("destination exists; pass overwrite=true to replace it: $path"))
    return nothing
end

function PerfChecker.saveplot(directory::AbstractString, figures::AbstractVector{<:Pair};
        format::Symbol = :svg, overwrite::Bool = false, kwargs...)
    format in (:svg, :png) || throw(ArgumentError("format must be svg or png"))
    isempty(figures) && throw(ArgumentError("figure collection is empty"))
    all(pair -> last(pair) isa Figure, figures) ||
        throw(ArgumentError("each collection value must be a Makie Figure"))
    names = [_export_name(first(pair)) * ".$format" for pair in figures]
    length(unique(lowercase.(names))) == length(names) ||
        throw(ArgumentError("figure names collide after filename normalization"))
    root = abspath(directory)
    paths = joinpath.(root, names)
    foreach(path -> _check_destination(path, overwrite), paths)
    mkpath(root)
    return [PerfChecker.saveplot(path, last(pair); overwrite, kwargs...)
            for (path, pair) in zip(paths, figures)]
end
