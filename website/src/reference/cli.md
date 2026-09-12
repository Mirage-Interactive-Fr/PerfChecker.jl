# Command line

The public entry point is `perfchecker_main`. It works with an installed package;
no executable from a source checkout is required. Run from a prepared controller
environment (`--project=.` below selects the current directory):

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- <command> [options]
```

| Command | Purpose |
| --- | --- |
| `init` | Optionally write starter suite and workload files; this is not installation. |
| `testitems` | List or measure existing TestItemRunner items; `--list` executes no items. |
| `tools`, `native-plan` | List available integrations or prepare native-profiler arguments. |
| `machine`, `estimate` | Capture machine specifications or estimate from calibration records. |
| `discover`, `sync` | Propose scenarios and CI selections without executing target code. |
| `diagnose`, `advise` | Collect analyzer evidence or explain already saved evidence. |
| `narrate`, `investigate` | Use optional advice or run a bounded set of declared experiments. |
| `advisor-setup`, `evaluate-advisors` | Configure a provider or evaluate it against a labelled corpus. |
| `plan` | Resolve targets and print or write the immutable plan. |
| `preflight` | Resolve dependency compatibility without measuring. |
| `run` | Preflight, run the selected plan, and write reports. |
| `compare` | Compare two bundles without failing on a regression. |
| `check` | Compare two bundles and return non-zero when a limit fails. |
| `report` | Export portable JSON and Markdown from one bundle. |
| `verify` | Verify SHA-256 bundle integrity. |
| `migrate` | Rewrite a legacy bundle into a new destination. |
| `julia-campaign` | Compare one suite across Julia runtimes. |
| `network` | Measure an isolated command tree; command follows `--`. |
| `capabilities` | Emit controller/network capabilities as JSON. |
| `version` | Print PerfChecker's version. |

The examples below assume the referenced files already exist. `perf/suite.jl`
is your suite definition, `perf/perfchecker-ui.json` is an optional saved UI
selection, and baseline/candidate paths identify saved bundle directories.
For a complete example, start with [Bibliography](../tutorials/bibliography.md).

Shell blocks with a trailing `\` use POSIX line continuation. In PowerShell,
put that command on one line or use its backtick continuation character.

## Plan and run

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- plan \
  --suite=perf/suite.jl --profile=ci --output=perf/plan.json

julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- preflight \
  --suite=perf/suite.jl --profile=ci \
  --output=perf/results/compatibility.json --progress=jsonl

julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run \
  --suite=perf/suite.jl --profile=ci --reports=perf/results \
  --progress=jsonl
```

Add `--config=perf/perfchecker-ui.json` only after saving that selection file.

Profiles are `quick`, `ci`, `historical`, and `release`. Repeat `--run-id=<id>`
to run exact plan leaves; it cannot be combined with `--config`. The default run
performs a compatibility preflight; use `--preflight=false` only when another
verified step already did so.

Each JSONL progress line starts with `PERFCHECKER_PROGRESS ` followed by a
canonical JSON object, making it safe for CI, editors, and agents to parse while
ordinary logs remain readable.

## Git targets and comparisons

`--candidate` and `--comparison` accept repeatable JSON objects. A shared UI
configuration is usually easier for humans and avoids shell quoting differences.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check \
  --baseline=perf/bundles/stable --candidate=perf/bundles/change \
  --limit=julia.wall.time=0.05 \
  --statistic=julia.wall.time=p99 \
  --limit=julia.alloc.bytes=0.02 \
  --min-samples=10 --reports=perf/comparison
```

Limits are relative fractions: `0.05` means a five-percent allowed increase for
a lower-is-better metric. Repeat `--statistic=metric=p95` to select `median`,
`mean`, `minimum`, `maximum`, `p95`, or `p99` per metric. The optional
`--default-statistic` changes the default from `median` for metrics without an
explicit selection.

When both selected values are exactly zero, an explicit policy passes because
the candidate preserved the zero baseline. A candidate moving away from zero in
the non-preferred direction is a regression; `relative_delta` remains null
because no finite ratio exists.

## Network command

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/network_workload.jl
```

On Windows, use `--provider=wsl2_netns` and optionally
`--distribution=<name>`. `--include-output=true` stores bounded stdout/stderr;
the default avoids leaking application output into reports.
