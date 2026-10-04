function PerfChecker.suite_dashboard(result::PerfChecker.SoftwareSuiteResult;
        view::Symbol = :normalized)
    view in (:normalized, :absolute) ||
        throw(ArgumentError("view must be normalized or absolute"))
    bundle = PerfChecker._suite_run_bundle(result)
    if view === :normalized &&
       any(entry -> entry["kind"] == "normalized_metrics", PerfChecker.plot_catalog(bundle))
        return PerfChecker.performance_figure(bundle)
    end
    labels = String[]
    values = Float64[]
    packages = String[]

    for run in result.runs
        run.status === :pass || continue
        summary = PerfChecker._first_summary_row(run)
        value = get(summary, "min_time", nothing)
        value isa Number || continue
        push!(labels, "$(run.planned.feature.id)\n$(run.planned.target.label)")
        push!(values, Float64(value))
        push!(packages, run.planned.package_suite.package)
    end

    figure = Figure(size = (max(800, 85 * max(length(labels), 1)), 500))
    axis = Axis(figure[1, 1];
        title = "PerfChecker suite: $(result.plan.suite.id)",
        xlabel = "feature and version", ylabel = "minimum time")

    if isempty(values)
        Label(figure[1, 1], "No timing observation available")
        hidespines!(axis)
        hidedecorations!(axis)
        return figure
    end

    package_names = sort!(unique(packages))
    palette = make_colors(length(package_names))
    color_by_package = Dict(name => palette[index]
    for (index, name) in pairs(package_names))
    colors = [color_by_package[name] for name in packages]
    barplot!(axis, eachindex(values), values; color = colors)
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 4
    return figure
end

function PerfChecker.suite_dashboard(job::PerfChecker.SuiteJob; strict::Bool = true,
        view::Symbol = :normalized)
    return PerfChecker.suite_dashboard(PerfChecker.wait_suite(job; strict); view)
end

function PerfChecker.suite_dashboard(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, strict::Bool = true, view::Symbol = :normalized, kwargs...)
    job = PerfChecker.launch_suite(suite; profile, kwargs...)
    return PerfChecker.suite_dashboard(job; strict, view)
end
