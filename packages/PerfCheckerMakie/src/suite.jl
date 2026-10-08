"""
    suite_dashboard(result; view=:normalized, figure_kwargs=(;), axis_kwargs=(;), plot_kwargs=(;))

Render saved suite results without running measurements. The normalized view
uses the standard saved-evidence model when available. The absolute view shows
minimum elapsed time in seconds: BenchmarkTools nanoseconds are converted only
for display, while Chairmarks seconds are retained. Unknown collector units are
excluded with a visible explanation, never inferred from magnitude. Source
tables and summaries remain unchanged. Titles name the displayed collectors;
subtitles retain result tags. Explicit attribute bundles customize presentation.
"""
function PerfChecker.suite_dashboard(result::PerfChecker.SoftwareSuiteResult;
        view::Symbol = :normalized, figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    view in (:normalized, :absolute) ||
        throw(ArgumentError("view must be normalized or absolute"))
    tags = Symbol[]
    for run in result.runs
        run.result isa PerfChecker.CheckerResult || continue
        append!(tags, something(run.result.tags, Symbol[]))
    end
    unique!(tags)
    if view === :normalized
        bundle = PerfChecker._suite_run_bundle(result)
        if any(entry -> entry["kind"] == "normalized_metrics",
            PerfChecker.plot_catalog(bundle))
            return PerfChecker.performance_figure(
                bundle; figure_kwargs, axis_kwargs, plot_kwargs, tags)
        end
    end
    labels = String[]
    values = Float64[]
    packages = String[]
    collectors = String[]
    unavailable = String[]

    for run in result.runs
        run.status === :pass || continue
        summary = PerfChecker._first_summary_row(run)
        value = get(summary, "min_time", nothing)
        value isa Real && isfinite(value) || continue
        backend = run.planned.feature.backend
        # Units follow the collector's table contract, never the sample value.
        definition = PerfChecker._measurement_definition(backend, :times)
        unit = isnothing(definition) ? nothing : last(definition)
        scale = unit == "ns" ? 1.0e-9 : unit == "s" ? 1.0 : nothing
        if isnothing(scale)
            push!(
                unavailable, "$(run.planned.feature.id) ($backend): time unit unspecified")
            continue
        end
        push!(labels, "$(run.planned.feature.id)\n$(run.planned.target.label)")
        push!(values, Float64(value) * scale)
        push!(packages, run.planned.package_suite.package)
        push!(collectors,
            backend === :benchmark ? "BenchmarkTools" :
            backend === :chairmark ? "Chairmarks" : string(backend))
    end

    figure = _figure(; figure_kwargs, size = (max(800, 85 * max(length(labels), 1)), 500))
    axis = Axis(figure[1, 1];
        title = "PerfChecker suite: $(result.plan.suite.id)",
        xlabel = "feature and version", ylabel = "minimum elapsed time (s)",
        xticklabelrotation = pi / 2)
    isempty(unavailable) || Label(figure[2, 1], "Unavailable: " * join(unavailable, "; ");
        tellwidth = false, fontsize = 12)

    if isempty(values)
        Label(figure[1, 1], "No timing observation with known units available")
        hidespines!(axis)
        hidedecorations!(axis)
        return _decorate!(figure; tool = "No timing collector with known units available",
            tags, axis_kwargs)
    end

    package_names = sort!(unique(packages))
    palette = make_colors(length(package_names))
    color_by_package = Dict(name => palette[index]
    for (index, name) in pairs(package_names))
    colors = [color_by_package[name] for name in packages]
    _recipe!(barplot!, axis, eachindex(values), values; plot_kwargs, color = colors)
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 2
    return _decorate!(figure; tool = join(unique(collectors), " + "), tags, axis_kwargs)
end

function PerfChecker.suite_dashboard(job::PerfChecker.SuiteJob; strict::Bool = true,
        view::Symbol = :normalized, figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    return PerfChecker.suite_dashboard(
        PerfChecker.wait_suite(job; strict); view, figure_kwargs, axis_kwargs, plot_kwargs)
end

function PerfChecker.suite_dashboard(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, strict::Bool = true, view::Symbol = :normalized,
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;), kwargs...)
    job = PerfChecker.launch_suite(suite; profile, kwargs...)
    return PerfChecker.suite_dashboard(
        job; strict, view, figure_kwargs, axis_kwargs, plot_kwargs)
end
