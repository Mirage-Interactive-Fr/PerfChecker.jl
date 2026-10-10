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
- `narrate`, `chat` — explain saved advice, or ask an MCP tool using bounded conversation.
- `implement` — invoke an explicit MCP implementation tool on a caller-owned isolated checkout; caller owns checkpoint and diff review.
- `discover`, `sync` — propose scenarios and CI selections without running target code.
- `machine`, `estimate` — capture machine specs, or estimate from calibration records.
- `julia-campaign` — compare one suite across Julia runtimes.
- `network` — measure an isolated command tree; the command follows `--`.
- `capabilities` — emit controller/network capabilities as JSON.
- `version` — print PerfChecker's version.

## Interruption and cleanup errors

When the entry point handles an `InterruptException`, it returns **130** after
the operation's cleanup has run. A cleanup failure remains an error: it returns
**2** and prints the cause and retained inventory paths to standard error, even
when cancellation was requested. Wait for the controller to exit before treating
cancellation as complete. Forced process termination can have a different exit
status and does not confirm cleanup.

## Plan and run

Start in a prepared controller project containing PerfChecker and the collectors
used by your existing `perf/suite.jl`. Inspect the plan first:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- plan \
  --suite=perf/suite.jl --profile=ci
```

Check the package, workload, collector and target rows. Planning loads your suite
definition and resolves its targets; it does not measure the workload. Add
`--output=perf/selected-plan.json` to write that plan as JSON. This file is an
inspection record: `run` below reads the suite again, so retain the same suite
and source revision when you proceed.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run \
  --suite=perf/suite.jl --profile=ci --reports=perf/results --progress=jsonl
```

- Profiles: `quick`, `ci`, `historical`, `release`.
- `--run-id=<id>` runs exact plan leaves; it cannot be combined with `--config`.
- The default run performs a compatibility preflight.
- Each JSONL progress line starts with `PERFCHECKER_PROGRESS `.

Choose a fresh `--reports` directory when keeping earlier results. A completed
run writes `suite-result.json`, `suite-report.md`, JUnit output and a portable
bundle under `bundles/run-…`; a failed compatibility preflight writes
`compatibility.json` and returns before measurement. Read the final verdict and
the per-run statuses: exit code zero alone does not assert that every requested
collector was available or that a regression budget passed.

Use the actual bundle directory, rather than `suite-result.json`, when reopening
evidence. Replace `<run-directory>` in these commands:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- verify \
  --bundle='perf/results/bundles/<run-directory>'
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- report \
  --bundle='perf/results/bundles/<run-directory>' --reports=perf/reopened-report
```

`verify` checks integrity and emits JSON; `report` exports the saved evidence
without rerunning a workload. Keep the suite/workload sources separately from
these outputs. To inspect the same bundle visually, use the
[REPL](../interfaces/repl-pluto.md#REPL), [terminal UI](../interfaces/packages.md#Optional-terminal-UI)
or [plots](../interfaces/visualization.md).

```@raw html
<a id="Git-targets-and-comparisons"></a>
```

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

Both paths must identify actual bundles with compatible measurement boundaries.
Read `comparison.json` and `comparison.md` in the report directory for coverage,
units and inconclusive rows. `check` returns 1 when its comparison does not pass;
`compare` writes the same diagnostic reports without using the verdict as an
exit-code gate. Neither command starts another measurement.

```@raw html
<a id="Network-command"></a>
```

## Network

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/network_workload.jl
```

On Windows use `--provider=wsl2_netns` with optional `--distribution=<name>`. Output is omitted by default; opt in with `--include-output=true`.

POSIX line continuations (`\`) do not work in PowerShell; put each command on one line.
