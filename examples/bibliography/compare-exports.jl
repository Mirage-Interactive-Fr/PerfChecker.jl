using PerfChecker, BenchmarkTools, TOML

suite = load_software_suite(joinpath(@__DIR__, "suite.jl"))
sources = TOML.parsefile(joinpath(@__DIR__, "sources.toml"))
source = joinpath(@__DIR__, ".sources/Bibliography")
after = sources["Bibliography"]["revision"]
before = strip(read(`git -C $source rev-parse $after^`, String))
dependencies = [(name = name, url = sources[name]["url"], rev = sources[name]["revision"])
                for name in ("BibInternal", "BibParser")]
candidates = Dict("Bibliography" => [
    SuiteCandidate("before-streaming", before; dependencies),
    SuiteCandidate("after-streaming", after; dependencies)])
policy = ComparisonPolicy("streaming-export"; package = "Bibliography",
    feature = "export_bibtex", baselines = ["before-streaming"],
    candidates = ["after-streaming"])
full = plan_suite(suite; profile = :quick, candidates, comparisons = [policy])
selected = filter_suite_plan(full; packages = "Bibliography",
    features = :export_bibtex, backends = :benchmark)
selected = SuitePlan(selected.suite, selected.profile,
    filter(run -> run.target.kind == :candidate, selected.runs), selected.comparisons)
print_suite_plan(selected)
isempty(ARGS) && error("Pass plan to inspect or run to measure the two revisions")
only(ARGS) in ("plan", "run") || error("Choose plan or run")
if only(ARGS) == "run"
    parent = joinpath(@__DIR__, "results")
    mkpath(parent)
    output = mktempdir(parent; prefix = "export-comparison-", cleanup = false)
    result = run_suite_repl(selected; reports = output, strict = false,
        overrides = Dict{Symbol, Any}(:threads => 1, :samples => 100,
            :evals => 1, :seconds => 1.0))
    println("Reports: ", output)
    suite_passed(result) || throw(PerfChecker.SuiteRunError(result))
end
