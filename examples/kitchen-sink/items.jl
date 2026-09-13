using PerfChecker, TestItemRunner, JSON
mode = isempty(ARGS) ? "list" : ARGS[1]
tag = length(ARGS) >= 2 ? Symbol(ARGS[2]) : :queue
if mode == "list"
    display(discover_testitems(@__DIR__))
elseif mode == "run"
    result = run_testitems(@__DIR__; tags = [tag], samples = 30, project = dirname(Base.active_project()))
    output = mktempdir(joinpath(@__DIR__, "results"); prefix = "testitems-", cleanup = false)
    open(io -> JSON.print(io, result, 2), joinpath(output, "result.json"), "w")
    println("TestItem evidence: ", output)
    result["passed"] || error("Native test item failed")
else
    error("Choose list or run")
end
