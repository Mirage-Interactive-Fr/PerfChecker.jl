using PerfChecker, TestItemRunner
mode = isempty(ARGS) ? "list" : only(ARGS)
if mode == "list"
    display(discover_testitems(@__DIR__))
elseif mode == "run"
    result = run_testitems(@__DIR__; tags = [:queue], samples = 3, project = dirname(Base.active_project()))
    result["passed"] || error("Native test item failed")
else
    error("Choose list or run")
end
