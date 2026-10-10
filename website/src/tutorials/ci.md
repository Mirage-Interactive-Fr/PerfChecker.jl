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

::: info Development after 1.0.1
The Preferences.jl integration below is not included in registered PerfChecker
1.0.1. Use a reviewed development revision until a release includes it.
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

PerfChecker's **Registered PkgEval** workflow is a development addition after
1.0.1. It resolves a General revision to an exact commit, selects a non-yanked
registered version, and verifies its registered source tree inside the sandbox.
It records the PkgEval controller revision, Julia environment and selected
package identity. It tests that registered archive, **not the workflow branch's
PerfChecker checkout**. Editing a test on a branch cannot change an existing
registered archive.

### Read a PkgEval result

Open the workflow run and download its artifacts:

| Artifact | What to inspect |
| --- | --- |
| `pkgeval-request` | `request.toml`: version, registered tree, General and controller revisions, workflow revision and run URL |
| `pkgeval-stable` | `result.toml`, `evaluation.log` and `PkgEval-Manifest.toml` for Julia stable |
| `pkgeval-nightly` | The corresponding files for Julia nightly, evaluated separately |

First match `version`, `registered_tree` and `general_revision` to the release
you intend to assess. Then read `status`, `reason`, `exception` when present,
the installation/precompilation/testing completion fields, and the full log.
A successful package-test result has `status="test"`. A controller failure,
failed assertion and timeout are different outcomes; a cancelled job alone does
not identify the failing test. `duration_seconds` and `peak_rss_bytes` describe
this sandbox attempt, not a performance regression against another release.

The [initial 1.0.1 evaluation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/runs/38044386943)
tests registered tree `00c133336911b8600d63a8d6c59ce1befc5ce690`.
On Julia stable it reached 2,013 passing assertions, one error and one broken
assertion. The error came from a replay test that copied an installed read-only
JSON fixture and then tried to edit its copy. The development
[fixture correction](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/pull/167)
creates a writable private copy and checks that the original bytes and mode stay
unchanged. It does not repair the immutable 1.0.1 archive. Nightly is a separate
result; a pending run is not a pass.

That stable attempt took 2,652.31 seconds against the 2,700-second evaluation
budget. Its 47.69-second margin does not establish enough room for a future
release with additional tests. The workflow also has a separate 75-minute job
limit covering controller setup and evaluation. Keep both limits and the
actual test timings in view; the fixture correction alone does not close
[the PkgEval follow-up](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues/29).

### Evaluate a future registered release

After the workflow is integrated, open **Actions → Registered PkgEval → Run
workflow**. Supply:

| Input | Meaning |
| --- | --- |
| `package_version` | An already registered version; empty selects the latest non-yanked version at the chosen General revision |
| `general_revision` | A General commit or ref, resolved and recorded as an exact commit before evaluation |
| `expected_tree` | Optional registered tree SHA-1; a mismatch stops selection before evaluation |

To assess a fix, wait for the release containing it to be registered and select
that release and its tree. Re-running 1.0.1 will still test 1.0.1. The weekly
Monday 04:41 UTC schedule selects the latest non-yanked version at a newly
resolved General commit. Pull-request runs of this workflow deliberately pin
the original 1.0.1 evaluation; they are not evidence for development changes.
Keep the stable and nightly artifacts and report each verdict separately.
