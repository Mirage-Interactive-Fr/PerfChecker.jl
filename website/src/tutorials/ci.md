# Run checks in CI

CI repeats an experiment you can already run locally. Decide which result should fail the job, and keep the reports.

```@raw html
<a id="Existing-test-items"></a>
```

## Measure existing test items

```sh
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --list
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
```

- The second command exits nonzero if an item does not validate.
- `performance="not_compared"` means no regression budget was applied.
- Do not gate on a single first-call item duration.

For functional jobs that must exclude `:perf_only`, load PerfChecker and TestItemRunner, then:

```julia
@run_package_tests filter=testitem_filter(:test)
```

```@raw html
<a id="GitHub-Actions-example"></a>
```

## GitHub Actions

```yaml
name: Performance items
on: [push, pull_request]
permissions:
  contents: read
jobs:
  items:
    runs-on: ubuntu-latest
    env:
      JULIA_NUM_THREADS: '1'
      JULIA_NUM_GC_THREADS: '1'
      OPENBLAS_NUM_THREADS: '1'
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - name: Prepare test environment
        run: julia --startup-file=no --project=test -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
      - name: Measure selected items
        run: julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: performance-items
          path: results/items
```

```@raw html
<a id="Software-suites-and-regression-gates"></a>
```

## Regression gates

Run a suite, then compare two saved bundles:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=ci --reports=results/ci --progress=jsonl

julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check --baseline=results/baseline --candidate=results/candidate --limit=julia.wall.time=0.05 --limit=julia.alloc.bytes=0.02 --min-samples=10 --reports=results/comparison
```

- Limits are relative fractions: `0.05` allows a 5% increase for a lower-is-better metric.
- They are illustrative, not universal thresholds. Inspect distributions before choosing one.
- `check` fails when a limit fails; `compare` does not.

```@raw html
<a id="Retain-the-right-artifacts"></a>
```

## Keep the right artifacts

- Native items: `testitems.json`.
- Suite runs: the whole report directory, including `bundles/`.
- Keep runners, thread settings and fixtures comparable between baseline and candidate.

## Persistent defaults in CI

::: info Introduced in 1.1.0
The Preferences.jl integration below requires PerfChecker 1.1.0 or newer.
Registered PerfChecker 1.0.1 does not include it.
:::

[Persistent controller defaults](../reference/checks.md#Persistent-controller-defaults)
let a project retain `threads`, `repeat` and `quiet`. In CI, make an experiment's
important options explicit, or deliberately commit exported project preferences.
An untracked `LocalPreferences.toml` on a developer's machine is not a portable
CI configuration. Explicit check, feature, variant and run options win over the
persistent defaults.

1. Inspect `check_preferences()` in the controller environment before the run.
2. Keep the saved bundle's `check_configuration.values`, `origins` and
   `config_hash`, together with the workload and resolved dependency environment.
3. Compare runs with the same effective settings. Changing a value changes the
   experiment; changing only its source from a preference to an explicit option
   does not change the cache identity.
4. For a fresh experiment, request a fresh run and inspect its cache status.
   A cache hit reports the current request's configuration, not a new measurement.

Worker startup, package preparation, optional warmup and the measured expression
are different costs. `repeat=false` changes warmup for the collectors that use
it; it is not a BenchmarkTools or Chairmarks sampling limit. A different thread
count can change workload behavior. Neither setting alone demonstrates a
performance improvement. The integration's tests check persistence, overrides,
cache identity and a suite whose preferences change between workers; they do
not establish a universal runtime-overhead estimate.

## Check installed releases with PkgEval

[PkgEval.jl](https://github.com/JuliaCI/PkgEval.jl) installs and tests packages in
a Linux sandbox with a selected Julia runtime. It checks compatibility of an
installed release, rather than collecting a benchmark or comparing two workload
distributions. It does not qualify every companion, editor interface or physical
counter. Local PkgEval has Linux/kernel and container requirements; see its
[setup documentation](https://github.com/JuliaCI/PkgEval.jl#quick-start).

PerfChecker's **Registered PkgEval** workflow is introduced in 1.1.0.
In its registered-release mode, it resolves
a General revision to an exact commit, selects a non-yanked
registered version, and verifies its registered source tree inside the sandbox.
It records the PkgEval controller revision, Julia environment and selected
package identity. It tests that registered archive, **not the workflow branch's
PerfChecker checkout**. Editing a test on a branch cannot change an existing
registered archive.

### Read a PkgEval result

Open the workflow run and download its artifacts:

| Artifact | What to inspect |
| --- | --- |
| `pkgeval-request` | `request.toml`: source kind, package identity, selected tree, General and controller revisions, workflow revision and run URL |
| `pkgeval-stable` | `result.toml`, `evaluation.log` and `PkgEval-Manifest.toml` for Julia stable |
| `pkgeval-nightly` | The corresponding files for Julia nightly, evaluated separately |

First inspect `source_kind`. For a registered release, match `version`,
`registered_tree` and `general_revision` to the release you intend to assess.
For a Git candidate, check its revision, tree and repository instead. Then read
`status`, `reason`, `exception` when present,
the installation/precompilation/testing completion fields, and the full log.
A successful package-test result has `status="test"`. A controller failure,
failed assertion and timeout are different outcomes; a cancelled job alone does
not identify the failing test. In the pinned controller, `duration_seconds`
records CPU time for the Testing phase, including completed child processes;
it is not elapsed wall time. Installation and precompilation phase timings
also use CPU time. The final `PkgEval … after …s` line reports total elapsed
wall time around sandbox execution. These timings and `peak_rss_bytes`
describe this attempt, not a performance regression against another release.

The [initial 1.0.1 evaluation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/runs/38044386943)
tests registered tree `00c133336911b8600d63a8d6c59ce1befc5ce690`.
On Julia stable it reached 2,013 passing assertions, one error and one result in
Julia's **Broken** category. The error came from a replay test that copied an installed read-only
JSON fixture and then tried to edit its copy. The development
[fixture correction](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/pull/167)
creates a writable private copy and checks that the original bytes and mode stay
unchanged. It does not repair the immutable 1.0.1 archive.

The nightly attempt recorded `status="kill"` and `reason="time_limit"` under
the 2,700-second sandbox budget. Installation and precompilation completed;
testing did not. This was not the separate 75-minute GitHub job limit. Its
zero duration and RSS fields are unavailable measurements, not evidence of
zero cost. Its final log records 2,833.81 seconds of total wall time, which also
includes sandbox launch, diagnostic dumps and shutdown; this does not mean
the configured timer was increased. The sampled Malt/profile stack does not
identify a regression, and a source location in a termination log does not
establish a REPL hang.
Neither attempt qualifies the development corrections or a future release.

The stable attempt recorded 2,652.31 seconds of total wall time and 2,385.04
seconds of Testing CPU time. PkgEval starts its 2,700-second timer after
launching the sandbox; the total wall-time measurement also includes launch
and shutdown. Their 47.69-second arithmetic difference is therefore not a
measured margin on that timer and does not establish room for additional tests.
See the pinned controller's [timer](https://github.com/JuliaCI/PkgEval.jl/blob/268f1d3d83df9abafb30c372a9755358fab7aa21/src/evaluate.jl#L141-L184)
and [total-duration measurement](https://github.com/JuliaCI/PkgEval.jl/blob/268f1d3d83df9abafb30c372a9755358fab7aa21/src/evaluate.jl#L363-L367).

Both logs warn that the cpuset controller was unavailable: CPUs 0–1 were
requested, but kernel enforcement was not verified. The workflow also has a
separate 75-minute job limit covering controller setup and evaluation. Keep
these scopes and the actual test timings in view; the fixture correction alone
does not close
[the PkgEval follow-up](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues/29).

### Evaluate a future registered release

Open **Actions → Registered PkgEval → Run workflow** on a branch containing
the workflow. Supply:

| Input | Meaning |
| --- | --- |
| `source_kind` | Keep `registered` for an archive selected from General |
| `package_version` | An already registered version; empty selects the latest non-yanked version at the chosen General revision |
| `general_revision` | A General commit or ref, resolved and recorded as an exact commit before evaluation |
| `expected_tree` | Optional registered tree SHA-1; a mismatch stops selection before evaluation |
| `package_images` | Keep `upstream` for the pinned PkgEval defaults; `yes` explicitly allows native package-image generation |
| `time_limit_minutes` | Keep the default `45`, or explicitly select `90` for the complete sandbox evaluation |

To assess a fix, wait for the release containing it to be registered and select
that release and its tree. Re-running 1.0.1 will still test 1.0.1. The weekly
Monday 04:41 UTC schedule selects the latest non-yanked version at a newly
resolved General commit. Pull-request checks test the source selector and record
the original 1.0.1 selection; they do not launch stable or nightly sandboxes.
That selection receipt is not a new package evaluation.
Keep the stable and nightly artifacts and report each verdict separately.

### Evaluate an explicit Git candidate

To assess an unpublished fix, manually dispatch the same workflow with
`source_kind=git_candidate`. Set `candidate_revision` to the exact lowercase
40-character commit SHA from the
[PerfChecker repository](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl),
choose `general_revision` for dependency resolution, and leave `package_version`
and `expected_tree` empty. Branch names and tags are not accepted as candidate
revisions. Scheduled evaluations use registered mode; pull-request checks only
validate selection.

The selector reads the commit's `Project.toml` and records its declared version,
name and UUID, `candidate_revision`, `candidate_tree` and the fixed
`source_repository`. PkgEval receives that repository URL and commit revision.
General supplies its dependencies; it does not supply a registered PerfChecker
archive for this run.

Inspect the same request, stable and nightly artifacts. Candidate results also
record `candidate_package_url` and `candidate_package_revision`, with
`sandbox_registry_tree_verified=false`. The evaluated version must match the
commit's declared version. These fields identify the requested candidate;
they do not claim a separate hash verification of PkgEval's installed source.
The default 2,700-second sandbox budget, disabled result cache and separate verdicts
remain unchanged. A candidate pass can qualify that candidate's tests, but
cannot repair or qualify the immutable registered 1.0.1 archive.

### Distinguish compilation configurations

Leave `package_images=upstream` for an evaluation using the pinned controller's
defaults. On Julia 1.13, that controller passes `--pkgimages=existing`: it can
reuse native package images but does not generate new ones. Its source explains
that this avoids the cost of generating images for ordinary PkgEval jobs.

An explicit `package_images=yes` dispatch instead passes `--pkgimages=yes`
through the official `Configuration.julia_args` option. The pinned controller
uses these arguments for both precompilation and `Pkg.test`; PerfChecker's
isolated Julia workers inherit the package-image policy through `Base.julia_cmd()`.
This configuration may change how much compilation is repeated across workers.
It does not change the tests, one Julia thread or disabled PkgEval shared cache.
Record and report its verdict separately from an
upstream-default evaluation; a configured pass is not a pass under the defaults.

Both `request.toml` and `result.toml` retain `package_images` and the exact
`julia_args`, together with `time_limit_minutes` and `time_limit_seconds`;
the result's `configuration` records the PkgEval configuration.
The single sandbox timer includes setup, installation, precompilation and testing.
A separate precompilation phase does not give testing another 2,700 seconds.
Native package-image generation can itself consume more of this budget; selecting
`yes` does not establish that the full suite will finish within it.

The default sandbox budget remains 45 minutes. An explicit `time_limit_minutes=90`
dispatch gives the same complete evaluation 5,400 seconds, with a separate
120-minute GitHub job limit; the default 45-minute evaluation retains its
75-minute job limit. Tests, thread count and shared-cache policy remain unchanged.
A `yes`/90-minute result is a configured qualification, not a pass under upstream
defaults. Since it changes both compilation policy and budget, its completion
alone cannot establish a compilation speedup or repair an earlier timeout.

See the pinned controller's
[package-image selection and argument forwarding](https://github.com/JuliaCI/PkgEval.jl/blob/268f1d3d83df9abafb30c372a9755358fab7aa21/scripts/evaluate.jl#L78-L113)
and [matching precompilation arguments](https://github.com/JuliaCI/PkgEval.jl/blob/268f1d3d83df9abafb30c372a9755358fab7aa21/scripts/evaluate.jl#L201-L224).
