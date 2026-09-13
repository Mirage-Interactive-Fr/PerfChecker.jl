using PerfChecker, JSON
example = isempty(ARGS) ? "datastructures" : only(ARGS)
example in ("datastructures", "oxygen") || error("Choose datastructures or oxygen")
package = example == "oxygen" ? "Oxygen" : "DataStructures"
source = Base.find_package(package)
source === nothing && error("Prepare the analyzers environment first")
root = mktempdir(joinpath(@__DIR__, "results"); prefix = "additional-$(example)-", cleanup = false)
quality = diagnose(ScenarioCatalog(dirname(dirname(source)), ScenarioSpec[]);
    project = dirname(Base.active_project()), tools = [:aqua], threads = 1, timeout = 180, reports = root)
open(io -> JSON.print(io, quality, 2), joinpath(root, "quality.json"), "w")
catalog = load_scenario_catalog(joinpath(@__DIR__, example == "oxygen" ? "oxygen/scenarios.toml" : "scenarios.toml"))
catalog = select_scenarios(catalog, [Dict("id" => example == "oxygen" ? "oxygen-heap" : "events-heap", "implementation" => example)])
heap = diagnose(catalog; project = dirname(Base.active_project()), tools = [:heap], threads = 1,
    timeout = 180, reports = root)
open(io -> JSON.print(io, heap, 2), joinpath(root, "heap.json"), "w")
println("Additional diagnostics: ", root)
println("Aqua: ", first(quality["records"])["status"], "; heap: ", first(heap["records"])["status"])
