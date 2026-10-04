using PerfChecker, TestItemRunner

listing = discover_testitems(@__DIR__)
item = only(filter(i -> i["name"] == "Parse a small document", listing["items"]))
result = run_testitems(@__DIR__; ids = [item["id"]], samples = 1,
    project = dirname(Base.active_project()))
result["passed"] || error("The example did not pass; inspect the returned samples")
println("Measured one shared test item. Correctness passed; no regression comparison was requested.")
