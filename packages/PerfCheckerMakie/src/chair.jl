function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:chairmark})
    return _checker_overlay(x, "Chairmarks")
end

function PerfChecker.checkres_to_boxplots(
        x::PerfChecker.CheckerResult, ::Val{:chairmark}; kwarg::Symbol = :times)
    di = Dict()
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
