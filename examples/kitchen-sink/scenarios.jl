using PerfChecker, JSON
mode = isempty(ARGS) ? "plan" : ARGS[1]
example = length(ARGS) < 2 ? "datastructures" : ARGS[2]
example in ("datastructures", "oxygen") || error("Choose datastructures or oxygen")
catalog = load_scenario_catalog(joinpath(@__DIR__, example == "oxygen" ? "oxygen/scenarios.toml" : "scenarios.toml"))
if length(ARGS) >= 3
    catalog = select_scenarios(catalog,
        [Dict("id" => ARGS[3], "implementation" => example)])
end
if mode == "plan"
    display(catalog)
elseif mode == "run"
    root = joinpath(@__DIR__, "results")
    mkpath(root)
    output = mktempdir(root; prefix = "scenarios-", cleanup = false)
    result = run_scenarios(catalog; project = dirname(Base.active_project()),
        samples = 5, threads = 1, reports = output)
    # The bundles already contain the observations. Do not duplicate full sampled
    # allocation stacks in a second, potentially very large JSON document.
    summary = [Dict("run_id" => bundle.manifest["run_id"],
        "scenario" => bundle.manifest["scenario"],
        "state" => bundle.manifest["state"],
        "correctness" => bundle.manifest["scenario_evidence"]["correctness"])
        for bundle in result]
    open(io -> JSON.print(io, summary, 2), joinpath(output, "scenario-result.json"), "w")
    println(output)
    all(bundle.manifest["state"] == "complete" &&
        bundle.manifest["scenario_evidence"]["correctness"] == "passed" for bundle in result) ||
        error("A scenario did not complete with a passing oracle; inspect the report")
elseif mode == "diagnose"
    root = joinpath(@__DIR__, "results")
    mkpath(root)
    output = mktempdir(root; prefix = "diagnosis-", cleanup = false)
    result = diagnose(catalog; project = dirname(Base.active_project()), threads = 1,
        tools = [:jet, :alloccheck, :snoopcompile, :latency, :gc, :memory, :locks], reports = output)
    open(io -> JSON.print(io, result, 2), joinpath(output, "diagnosis.json"), "w")
    println(output)
else
    error("Choose plan, run or diagnose")
end
