# Julia runtimes

A runtime campaign changes Julia while keeping the package source, workloads and measurement definitions fixed.

## Prepare channels

PerfChecker does not install Julia versions. With juliaup:

```sh
juliaup add release
juliaup add rc
juliaup add nightly
```

Each runtime is probed in a fresh process; the resolved version, commit, bindir and LLVM version are recorded.

## Run a campaign

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- julia-campaign \
  --suite=perf/suite.jl --baseline=release --candidate=rc --candidate=nightly \
  --profile=ci --reports=perf/julia-campaign \
  --limit=julia.wall.time=0.05 --min-samples=10 --progress=jsonl
```

- Each runtime gets a child controller and normal isolated workers.
- Startup and history files are disabled.
- `--resume=true` continues an interrupted campaign.

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

`source = :executable` points at an explicit Julia binary when juliaup is not used.

## Attribute a regression

```julia
investigation = investigate_julia_regressions(campaign; max_frames = 50, obvious_share = 0.6)
write_julia_investigation(investigation, "perf/julia-campaign/investigation")
```

PerfChecker ranks source lines whose sampled CPU or allocation weight increased, and labels each as Julia runtime or package/dependency code.

!!! warning "Attribution is not causality"
    A dominant Base, stdlib or compiler frame is a candidate for reduction, not proof of a Julia bug. PerfChecker reports when the evidence is only ranked and not enough for an automatic minimal working example.

## File a useful issue

Reduce in this order:

1. one feature and one check type;
2. the smallest deterministic fixture that still shows the delta;
3. the stable and candidate runtime identities;
4. the effective Project/Manifest and hardware context;
5. a short reproduction command;
6. the ranked profile artifact as supporting evidence.

```@raw html
<a id="Julia-RC-and-nightly-campaigns"></a>
<a id="Prepare-Julia-channels"></a>
<a id="Run-from-the-CLI"></a>
<a id="Use-explicit-runtime-specs"></a>
<a id="Produce-a-useful-Julia-issue"></a>
```
