"""
Render finite Chairmarks metric minima as normalized version curves. Accept the
same Figure, Axis and scatterlines attribute bundles and zero/missing-sample
semantics as `checkres_to_scatterlines(result, Val(:benchmark))`. Title and
subtitle retain the Chairmarks collector and result tags. No workload is rerun.
"""
function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:chairmark};
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    return _checker_overlay(x, "Chairmarks"; figure_kwargs, axis_kwargs, plot_kwargs)
end

"""
Render finite Chairmarks version distributions from `kwarg` (default `:times`).
Accept explicit Figure, Axis and boxplot attribute bundles. Empty/nonfinite
samples produce a labeled Figure; collector units, title and tags are retained.
`:times` is seconds, `:gctimes` is GC fraction, `:bytes` is allocated bytes,
and `:allocs` is an allocation count. Values are not converted between collectors.
Version labels default to pi/2. Rendering neither measures nor writes files.
"""
function PerfChecker.checkres_to_boxplots(x::PerfChecker.CheckerResult, ::Val{:chairmark};
        kwarg::Symbol = :times, figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;))
    return _checker_boxplots(
        x, "Chairmarks"; kwarg, figure_kwargs, axis_kwargs, plot_kwargs)
end
