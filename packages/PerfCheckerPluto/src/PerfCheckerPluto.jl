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

function PerfChecker.launch_pluto_dashboard(path::AbstractString; kwargs...)
    notebook = abspath(String(path))
    isfile(notebook) || throw(ArgumentError("Pluto notebook does not exist: $notebook"))
    return Pluto.run(; notebook, kwargs...)
end

function PerfChecker.prepare_pluto_dashboard(path::AbstractString;
        suite_path = nothing, factory::Symbol = :build_suite, kwargs...)
    destination = abspath(String(path))
    PerfChecker.write_suite_notebook(destination; suite_path, factory, kwargs...)
    return destination
end

end
