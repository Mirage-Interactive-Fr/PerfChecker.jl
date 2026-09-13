"Relate declared scenarios, test proposals and literal CI configurations without executing them."
function scenario_sync(root::AbstractString = pwd(); previous = nothing)
    discovery = discover(root; previous)
    coverage = Dict{String, Any}[]
    for job in discovery["ci"], configuration in job["configurations"],
        scenario in discovery["declared"]

        for collector in scenario["collectors"]
            push!(coverage,
                Dict("scenario" => scenario["id"],
                    "implementation" => scenario["implementation"],
                    "collector" => collector, "workflow" => job["file"], "job" => job["job"],
                    "runner" => job["runner"], "configuration" => configuration, "qualification" => "not_tested"))
            length(coverage) <= 10000 ||
                throw(ArgumentError("CI coverage exceeds 10000 combinations; narrow the catalog"))
        end
    end
    Dict("schema_version" => "perfchecker-scenario-sync/1", "coverage" => coverage,
        "declared" => discovery["declared"], "proposals" => discovery["candidates"],
        "changes" => discovery["changes"], "warnings" => discovery["warnings"],
        "fingerprints" => discovery["fingerprints"], "adoption_required" => true,
        "authority" => "proposal_only", "discovery" => discovery)
end

"Write a new CI workflow consuming an explicitly selected catalog; never overwrite a workflow."
function write_scenario_workflow(
        path::AbstractString; catalog = "perf/scenarios.toml", project = "perf",
        implementations = ["cpu"], versions = ["1"], platforms = [
            "ubuntu-latest", "windows-latest", "macos-latest"])
    ispath(path) &&
        throw(ArgumentError("workflow already exists; manual adaptations are preserved"))
    all(
        p -> occursin(r"^[A-Za-z0-9_./-]+$", p) && !isabspath(p) && !(".." in split(p, '/')),
        (catalog, project)) ||
        throw(ArgumentError("use simple relative project/catalog paths"))
    isempty(implementations) &&
        throw(ArgumentError("explicit implementations are required"))
    all(i -> i isa AbstractString && !isempty(i) && !occursin(',', i), implementations) ||
        throw(ArgumentError("implementation names must be nonempty and contain no comma"))
    isempty(versions) && throw(ArgumentError("Julia versions are required"))
    isempty(platforms) && throw(ArgumentError("platforms are required"))
    all(p -> p in ("ubuntu-latest", "windows-latest", "macos-latest"), platforms) ||
        throw(ArgumentError("unsupported runner"))
    setup = "using Pkg; Pkg.instantiate()"
    run = "using PerfChecker; c=load_scenario_catalog(ENV[\"PERFCHECKER_CATALOG\"]); selected=filter(s->s.implementation in split(ENV[\"PERFCHECKER_IMPLEMENTATIONS\"],\",\"),c.scenarios); isempty(selected) && error(\"No adopted scenarios\"); b=run_scenarios(ScenarioCatalog(c.root,selected); project=dirname(Base.active_project()),reports=\"perfchecker-results\",threads=3); all(bundle_passed,b) || exit(1)"
    workflow = Dict("name" => "Shared scenario qualification",
        "on" => ["workflow_dispatch", "pull_request"],
        "jobs" => Dict("scenarios" => Dict("runs-on" => "\${{ matrix.os }}",
            "strategy" => Dict("fail-fast" => false,
                "matrix" => Dict("os" => platforms, "julia" => versions)),
            "env" => Dict("JULIA_NUM_THREADS" => "3", "JULIA_NUM_PRECOMPILE_TASKS" => "3",
                "OPENBLAS_NUM_THREADS" => "1",
                "PERFCHECKER_CATALOG" => catalog, "PERFCHECKER_IMPLEMENTATIONS" => join(
                    implementations, ",")),
            "steps" => [Dict("uses" => "actions/checkout@v7"),
                Dict("uses" => "julia-actions/setup-julia@v3",
                    "with" => Dict("version" => "\${{ matrix.julia }}")),
                Dict("name" => "Prepare declared environment",
                    "run" => "julia --startup-file=no --project=$project -e '$setup'"),
                Dict("name" => "Measure and verify shared scenarios",
                    "run" => "julia --startup-file=no --project=$project -e '$run'"),
                Dict("uses" => "actions/upload-artifact@v4",
                    "if" => "always()",
                    "with" => Dict("name" => "perf-\${{ matrix.os }}-\${{ matrix.julia }}",
                        "path" => "perfchecker-results"))])))
    mkpath(dirname(abspath(path)))
    YAML.write_file(path, workflow)
    abspath(path)
end
