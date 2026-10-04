# Run in an isolated environment containing PerfChecker, HTTP, JET and AllocCheck.
# The writer connects only when an explicit configuration file is supplied.
using PerfChecker
root = @__DIR__
output = abspath(get(ENV, "PERFCHECKER_EVALUATION_REPORTS", joinpath(root, "results")))
labels = PerfChecker._json_parsefile(joinpath(root, "expected.json"))["cases"]
cases = Dict{String, Any}[]
for label in labels
    id = label["id"]
    spec = ScenarioSpec(
        id; source = joinpath(root, "cases.jl"), factory = "AdvisorCases.$id")
    diagnosis = diagnose(
        ScenarioCatalog(root, [spec]); project = dirname(Base.active_project()),
        tools = [Symbol(label["tool"])], timeout = 180)
    advice = advise(diagnosis)
    write_investigation_report(diagnosis, joinpath(output, id, "diagnosis"))
    write_investigation_report(advice, joinpath(output, id, "advice"))
    push!(cases,
        Dict("id" => id, "expected_rules" => label["expected_rules"], "advice" => advice))
end
config = isempty(ARGS) ? nothing : load_advisor_config(first(ARGS))
result = evaluate_advisors(cases; config)
write_investigation_report(result, output)
println(sprint(show, MIME"text/plain"(), investigation_view(result)))
