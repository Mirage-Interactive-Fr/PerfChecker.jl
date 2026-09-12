"""
Makie figures for PerfChecker results and presentation models. Load WGLMakie to
activate HTML rendering, or a Makie display/export backend for static figures.
Saved-result rendering does not install a renderer in measurement workers.
"""
module PerfCheckerMakie

using Makie
using TypedTables
using PerfChecker
export performance_figure, suite_dashboard, checkres_to_boxplots, checkres_to_scatterlines,
       checkres_to_pie, table_to_pie

include("plotutils.jl")
include("allocs.jl")
include("bench.jl")
include("chair.jl")
include("suite.jl")
include("performance.jl")

end
