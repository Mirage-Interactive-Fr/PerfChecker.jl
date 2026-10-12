```@raw html
<a id="Julia-RC-and-nightly-campaigns"></a>
```

# Julia runtimes

A runtime campaign changes Julia while keeping the package source, workloads and measurement definitions fixed.

```@raw html
<a id="Prepare-Julia-channels"></a>
```

## Prepare channels

PerfChecker does not install Julia versions. With juliaup:

```sh
juliaup add release
juliaup add rc
juliaup add nightly
```

Each runtime is probed in a fresh process; the resolved version, commit, bindir and LLVM version are recorded.

```@raw html
<a id="Run-from-the-CLI"></a>
```

## Run a campaign

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- julia-campaign \
  --suite=perf/suite.jl --baseline=release --candidate=rc --candidate=nightly \
  --profile=ci --reports=perf/julia-campaign \
  --limit=julia.wall.time=0.05 --min-samples=10 --progress=jsonl
```

Once the campaign starts, the initial progress record has these fields
(`PERFCHECKER_PROGRESS ` precedes the JSON):

```json
{"schema_version":"perfchecker-progress/1","stage":"runtime_campaign","state":"running","completed":0,"total":3}
```

The final line is `PASS` or `FAIL`, based on both runtime runs and baseline
comparisons. Inspect the generated reports rather than interpreting a missing
runtime as a fast result:

```text
perf/julia-campaign/
├── julia-runtime-campaign.json
├── julia-runtime-campaign.md
├── julia-investigation.json
└── julia-investigation.md
```

These are expected outputs of the recipe, not a recorded release/RC/nightly
performance comparison. The campaign Markdown table shows each runtime's
resolved Julia version, status, failure phase, duration and diagnostic.

- Each runtime gets a child controller and normal isolated workers.
- Startup and history files are disabled.
- `--resume=true` continues an interrupted campaign.

```@raw html
<a id="Use-explicit-runtime-specs"></a>
```

## Explicit specs

```julia
using PerfChecker
specs = [
    JuliaRuntimeSpec(:stable, "release"; role = :baseline),
    JuliaRuntimeSpec(:next, "rc"; role = :candidate),
    JuliaRuntimeSpec(:nightly, "nightly"; role = :candidate),
]

campaign = run_julia_runtime_campaign(specs;
    suite = "perf/suite.jl", reports = "perf/julia-campaign", profile = :ci,
    relative_limits = Dict("julia.wall.time" => 0.05), min_samples = 10)
```

Inspect the saved result without starting another measurement:

```julia
report = julia_runtime_campaign_dict(campaign)
report["schema_version"]
[(run["runtime_id"], run["role"]) for run in report["runs"]]
```

Expected identities for the explicit specs above:

```text
"perfchecker-julia-runtime-campaign/1"
[("stable", "baseline"), ("next", "candidate"), ("nightly", "candidate")]
```

Read each run's `status`, `probe`, `elapsed_seconds` and any `failure_stage`, then
the separate `comparisons` rows. `report["passed"]` requires both successful
execution and passing comparisons; elapsed time alone is not that verdict.

`source = :executable` points at an explicit Julia binary when juliaup is not used.

## Attribute a regression

```julia
investigation = investigate_julia_regressions(campaign; max_frames = 50, obvious_share = 0.6)
write_julia_investigation(investigation, "perf/julia-campaign/investigation")
```

This writes `investigation/julia-investigation.json` and
`investigation/julia-investigation.md`. Inspect the attribution statuses:

```julia
[(row["candidate_runtime_id"], row["status"])
 for row in julia_investigation_dict(investigation)["comparisons"]]
```

| Status | How to read it |
| --- | --- |
| `ranked` | Positive sampled source deltas are available; inspect their frames and owners. |
| `no_source_evidence` | No positive source-level delta was available; there is nothing to rank. |
| `unavailable` | A required runtime bundle is absent; read its failure diagnostic. |

PerfChecker ranks source lines whose sampled CPU or allocation weight increased, and labels each as Julia runtime or package/dependency code.

!!! warning "Attribution is not causality"
    A dominant Base, stdlib or compiler frame is a candidate for reduction, not proof of a Julia bug. PerfChecker reports when the evidence is only ranked and not enough for an automatic minimal working example.

```@raw html
<a id="Produce-a-useful-Julia-issue"></a>
```

## File a useful issue

Reduce in this order:

1. one feature and one check type;
2. the smallest deterministic fixture that still shows the delta;
3. the stable and candidate runtime identities;
4. the effective Project/Manifest and hardware context;
5. a short reproduction command;
6. the ranked profile artifact as supporting evidence.
