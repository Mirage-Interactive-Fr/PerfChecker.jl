"""
Pluto notebook generation and launch for PerfChecker suites and investigations.
The exported functions extend PerfChecker's shared entry points. Notebook
generation writes source only; launch and measurement controls are explicit.
"""
module PerfCheckerPluto

using PerfChecker
using Pluto
using PlutoUI
using JuliaSyntax
using UUIDs: uuid4
export prepare_pluto_dashboard, launch_pluto_dashboard, write_suite_notebook,
       write_investigation_notebook
include("investigation_notebook.jl")
include("suite_notebook.jl")

"""
    launch_pluto_dashboard(path::AbstractString; kwargs...)

Open an existing notebook with `Pluto.run` and return its result. Resolve `path`
from the working directory and reject a missing file before starting Pluto.
Additional keywords go to `Pluto.run`, including its server configuration.
This function starts a notebook server and normal Pluto cell evaluation; it
does not generate the notebook or install its dependencies. Use
`prepare_pluto_dashboard` or a notebook writer first, with a prepared controller
project. Load `PerfCheckerPluto` to enable this method.
"""
function PerfChecker.launch_pluto_dashboard(path::AbstractString; kwargs...)
    notebook = abspath(String(path))
    isfile(notebook) || throw(ArgumentError("Pluto notebook does not exist: $notebook"))
    return Pluto.run(; notebook, kwargs...)
end

"""
    prepare_pluto_dashboard(path::AbstractString; suite_path=nothing,
                            factory=:build_suite, kwargs...) -> String

Write a suite controller notebook and return its absolute path. `suite_path`
and `factory` select the suite definition; other keywords go to
`write_suite_notebook`, including the prepared `project`, report paths and
`force=false` overwrite policy. This function creates parent directories but
does not start Pluto, install packages or run measurements. Generated cells
activate the selected project when opened. Without a suite path, the notebook
reads saved reports only.

```julia
using PerfChecker, PerfCheckerPluto
notebook = prepare_pluto_dashboard("perf/notebooks/results.jl";
    project=abspath("perf/pluto"), result_path="../results/suite-result.json")
# launch_pluto_dashboard(notebook) starts Pluto explicitly.
```
"""
function PerfChecker.prepare_pluto_dashboard(path::AbstractString;
        suite_path = nothing, factory::Symbol = :build_suite, kwargs...)
    destination = abspath(String(path))
    PerfChecker.write_suite_notebook(destination; suite_path, factory, kwargs...)
    return destination
end

end
