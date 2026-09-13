function _checker_overlay(result, collector)
    props = TypedTables.columnnames(first(result.tables))
    order = sortperm([string(pkg.version) for pkg in result.pkgs];
        by = label -> PerfChecker._version_point_key(Dict("version" => label)))
    versions = string.([result.pkgs[i].version for i in order])
    figure, axis = _performance_figure("$(first(result.pkgs).name) · $collector · minimum = 1")
    colors = make_colors(length(props))
    for (i, prop) in pairs(props)
        values = [minimum(Float64.(getproperty.(result.tables[j], prop))) for j in order]
        ratios = [PerfChecker._relative_measurement(value, minimum(values))
                  for value in values]
        label = string(prop) * (all(iszero, values) ? " (0/0: unchanged)" : "")
        scatterlines!(axis, eachindex(versions), [isnothing(r) ? NaN : r for r in ratios];
            label, color = colors[i], linewidth = 2)
    end
    hlines!(axis, [1.0]; color = (:gray, 0.6), linestyle = :dash)
    axis.xticks = (collect(eachindex(versions)), versions)
    axis.xticklabelrotation = pi / 4
    axis.xlabel = "version"
    axis.ylabel = "minimum per version / minimum across versions"
    axislegend(axis; position = :lt)
    Label(figure[2, 1], "Equal zeros = 1 (unchanged); nonzero / zero = gap.";
        tellwidth = false)
    return _add_inspector(figure)
end

function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:benchmark})
    return _checker_overlay(x, "BenchmarkTools")
end

function PerfChecker.checkres_to_boxplots(
        x::PerfChecker.CheckerResult, ::Val{:benchmark}; kwarg::Symbol = :times)
    datax, datay = [], []

    for i in eachindex(x.tables)
        j = x.tables[i]
        p = x.pkgs[i]
        g = map(TypedTables.GetProperty{kwarg}(), j)
        append!(datax, fill(i, length(g)))
        append!(datay, g)
    end

    versionnums = [x.pkgs[i].version for i in eachindex(x.pkgs)]
    f = Figure()
    ax = f[1, 1] = Axis(f)
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = string(kwarg)
    boxplot!(datax, datay, label = string(kwarg))
    ax.title = x.pkgs[1].name
    ax.xticklabelrotation = 45.0
    f[1, 2] = Legend(f, ax)
    return f
end
