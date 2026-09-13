# Command line

The public entry point is `perfchecker_main`. It works with an installed package; no checkout is needed.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- <command> [options]
```

- `init` — write starter suite/workload files (not installation).
- `testitems` — list or measure existing TestItems; `--list` runs none.
- `plan` — resolve targets and print or write the plan.
- `preflight` — resolve dependency compatibility without measuring.
- `run` — preflight, run the plan, write reports.
- `compare` — compare two bundles; never fails on a regression.
- `check` — compare two bundles; fails when a limit fails.
- `report` — export portable JSON and Markdown from one bundle.
- `verify` — verify bundle integrity.
- `migrate` — rewrite a legacy bundle into a new destination.
- `diagnose`, `advise` — collect analyzer evidence, or explain saved evidence.
- `discover`, `sync` — propose scenarios and CI selections without running target code.
- `machine`, `estimate` — capture machine specs, or estimate from calibration records.
- `julia-campaign` — compare one suite across Julia runtimes.
- `network` — measure an isolated command tree; the command follows `--`.
- `capabilities` — emit controller/network capabilities as JSON.
- `version` — print PerfChecker's version.

## Plan and run

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run \
  --suite=perf/suite.jl --profile=ci --reports=perf/results --progress=jsonl
```

- Profiles: `quick`, `ci`, `historical`, `release`.
- `--run-id=<id>` runs exact plan leaves; it cannot be combined with `--config`.
- The default run performs a compatibility preflight.
- Each JSONL progress line starts with `PERFCHECKER_PROGRESS `.

## Compare and gate

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check \
  --baseline=perf/bundles/stable --candidate=perf/bundles/change \
  --limit=julia.wall.time=0.05 --statistic=julia.wall.time=p99 \
  --min-samples=10 --reports=perf/comparison
```

- Limits are relative fractions; `0.05` allows a 5% increase for a lower-is-better metric.
- `--statistic=metric=p95` selects `median`, `mean`, `minimum`, `maximum`, `p95` or `p99`.
- When both selected values are exactly zero, an explicit policy passes: the candidate preserved the baseline.

## Network

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/network_workload.jl
```

On Windows use `--provider=wsl2_netns` with optional `--distribution=<name>`. Output is omitted by default; opt in with `--include-output=true`.

POSIX line continuations (`\`) do not work in PowerShell; put each command on one line.

```@raw html
<a id="Git-targets-and-comparisons"></a>
<a id="Network-command"></a>
```
