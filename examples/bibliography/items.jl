using PerfChecker, TestItemRunner

length(ARGS) <= 2 || error("Usage: items.jl [list|functional|performance] [item name]")
mode = isempty(ARGS) ? "list" : first(ARGS)
mode in ("list", "functional", "performance") ||
    error("Choose list, functional or performance")
length(ARGS) == 2 && mode != "performance" &&
    error("An item name is supported only in performance mode")
root = @__DIR__
listing = discover_testitems(root)
selected = length(ARGS) == 2 ?
           filter(item -> item["name"] == ARGS[2], listing["items"]) : listing["items"]
isempty(selected) && error("No performance item matches the requested name")
length(ARGS) == 2 && length(selected) != 1 && error("Item name is ambiguous")
for item in listing["items"]
    println(item["name"], " [", join(item["tags"], ", "), "]")
end
if mode == "functional"
    TestItemRunner.run_tests(root; filter = testitem_filter(:test))
elseif mode == "performance"
    parent = joinpath(root, "results")
    mkpath(parent)
    output = mktempdir(parent; prefix = "items-", cleanup = false)
    result = run_testitems(root; ids = [item["id"] for item in selected],
        samples = 1, threads = 1, timeout = 180,
        reports = output)
    println("Reports: ", output)
    result["passed"] || error("One or more native test items did not validate")
end
