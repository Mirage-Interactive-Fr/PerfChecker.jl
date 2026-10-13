# Saved results

Verify and reopen a completed run without measuring again. Use its actual bundle directory, not a plot JSON or `suite-result.json`.

Start Julia in a project containing PerfChecker (`] add PerfChecker` if needed).

Replace `ACTUAL-BUNDLE` below with the directory printed by your completed run.

```julia
using PerfChecker
bundle = read_run_bundle("perf/results/bundles/ACTUAL-BUNDLE")
verify_run_bundle("perf/results/bundles/ACTUAL-BUNDLE"; require_integrity=true)
query = PerformanceQuery(id="wall-time", resources=[:observations],
    predicates=[QueryPredicate("metric", :equals, "julia.wall.time")])
result = query_bundle(bundle, query)
display(result["counts"])
display(result["observations"])
```

```@raw html
<p>Successful verification reports <code>status="verified"</code> and <code>verified=true</code>. Query counts depend on the saved run; an empty selection stays empty. <a href="../examples/tool-recipes/recorded-performance.md">Recorded bundle replay</a> produced <strong>INCONCLUSIVE, 2 series, 0 comparisons</strong> for the real single-release Bibliography allocation bundle. Integrity and execution completion do not establish a performance comparison.</p>
```

::: details Bundle files and identity

## Directory layout

```text
run-directory/
├─ manifest.json
├─ measurement-definitions.json
├─ observations.jsonl
├─ diagnostics.jsonl
├─ artifacts.json
├─ integrity.json
└─ artifacts/
```

- `manifest.json` — run/attempt identity, state, plan, runtime, environment, timestamps.
- `measurement-definitions.json` — versioned meaning, unit, method, scope, comparability.
- `observations.jsonl` — numeric or categorical evidence with comparison keys.
- `diagnostics.jsonl` — compatibility failures, warnings, attribution findings.
- `artifacts.json` — metadata for profiles, plots, logs and provider artifacts.
- `integrity.json` — SHA-256 and byte length for the five protocol documents: manifest, definitions, observations, diagnostics and artifact descriptors. Artifact payloads under `artifacts/` are outside that digest set.

### Julia API

```julia
using PerfChecker
bundle_directory = "perf/results/bundles/ACTUAL-BUNDLE"
bundle = read_run_bundle(bundle_directory)
verify_run_bundle(bundle_directory; require_integrity = true)

bundle_passed(bundle)
bundle_dict(bundle)
list_run_bundles("perf/results"; recursive = true)
```

`write_run_bundle` writes to a temporary sibling and renames atomically. It refuses to overwrite. `migrate_run_bundle` rewrites supported legacy data into a new destination.

### Identity and reuse

- `run_id` is the logical experiment; `attempt_id` is one physical attempt.
- `reuse_key` describes the normalized plan, runtime and measurement definitions.
- Reused evidence stays labelled as reused; it never impersonates a fresh run.

Before making a regression decision, a consumer must verify integrity, schema version, completion state, diagnostic severity and measurement-definition identity.

Schema strings such as `perfchecker-run-bundle/1` name a data format and version. They are not URLs or package versions. Unsupported versions require an explicit reader.

:::

::: details Compare releases and revisions

## Compare releases and revisions

## Candidates

```julia
using PerfChecker
# Replace these with your existing package checkout and workload entrypoint.
source = "/path/to/Bibliography"
worker_environment = joinpath(source, "perf", "worker")
features = [FeatureSpec(:export_bibtex; backend=:benchmark,
    entrypoint="perf/features/export_bibtex.jl")]
candidates = [
    SuiteCandidate("before", "6a4cc9027dcc094d21b3681ccff86ca4aec84a23"),
    SuiteCandidate("after", "575ec810042cc791fd47a2c025a80246ccf039b5"),
    SuiteCandidate("tagged-0.4.0", "v0.4.0"),
]

package = PackageSuite("Bibliography"; source, worker_environment,
    versions = [v"0.3.0", v"0.4.0"], candidates, features)
```

Use a full Git revision when a branch can move. `compatibility_version` selects a feature variant; it does not change the candidate's source identity.

```@raw html
<a id="Exact-and-grouped-references"></a>
```

## References

Exact policy — one reference:

```julia
ComparisonPolicy("before-vs-0.4";
    package = "Bibliography", comparison_key = "bibliography-export/v1",
    baselines = ["0.4.0"], candidates = ["before"])
```

Grouped policy — summarize several references first:

```julia
ComparisonPolicy("experiments-vs-recent";
    package = "Bibliography", comparison_key = "bibliography-export/v1",
    baselines = ["0.3.0", "0.4.0"], candidates = ["before", "after"],
    aggregation = :median)
```

Aggregations: `:median` (default), `:mean`, `:minimum`, `:maximum`.

```@raw html
<a id="Use-the-VS-Code-target-picker"></a>
```

## Comparability

- Compare only when measurement definitions and `comparison_key` agree.
- Use a new key when inputs, output semantics, warm-up or procedure change.
- Hardware, runtime and source identity stay in the bundle so a confounded comparison is detectable.
- A missing result stays `missing` or `unavailable`; it never becomes an improvement.

For a recorded four-metric export example, see the [Bibliography history](../tutorials/bibliography.md#Compare-the-package-history). Allocation activity and resident memory remain different quantities.

## Regression limits

Compare compatible saved baseline and candidate bundles with explicit relative limits:

```sh
julia --project=perf -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check \
  --baseline=results/baseline --candidate=results/candidate \
  --limit=julia.wall.time=0.05 --limit=julia.alloc.bytes=0.02 \
  --min-samples=10 --reports=results/comparison
```

Limits are fractions: `0.05` permits at most a 5% increase. `check` writes diagnostics and returns failure when a limit fails; `compare` writes diagnostics without a failing verdict exit status. Use compatible measurement definitions and comparison keys; missing data cannot establish a pass.

:::

::: details Query fields and documentation blocks

## Query fields and documentation blocks

Fields address records, then their attributes; a `manifest.` prefix reads run context. Operators are `equals`, `not_equals`, `one_of`, `contains`, `prefix`, `greater_or_equal`, `less_or_equal` and `exists`. Queries select saved evidence; they execute no Julia expressions.

```julia
block = PerformanceDocumentBlock("wall-time", "Saved timing evidence", query;
    views=[:observations])
model = performance_document_block(bundle, block)
display(model["result"]["counts"])
```

The model retains selected results, views and provenance. [Documenter](../interfaces/documentation.md) can render it without a workload run.

:::

::: details Native dependency context

## Native dependency context

## Capture the visible dependency closure

Use this reference when a package calls code outside Julia or starts another
process. For tool selection and interpretation, start with
[native profiling](../native-profiling.md). The snapshot example below runs in
an environment with Bibliography installed, before importing it:

```julia
using PerfChecker

before = dependency_evidence(phase = "before_import")
using Bibliography
after = dependency_evidence(
    phase = "after_import",
    hash_libraries = false,
)

payload = dependency_evidence_dict(after)
println(payload["schema_version"])
println("Phase: ", payload["phase"])
for key in ("declared_packages", "declared_artifact_bindings",
    "loaded_current_process", "child_process_tree", "services", "native_heap")
    println(key, ": ", payload["coverage"][key])
end
```

Expected coverage output:

```text
perfchecker-dependency-evidence/1
Phase: after_import
declared_packages: true
declared_artifact_bindings: true
loaded_current_process: true
child_process_tree: false
services: false
native_heap: false
```

`true` identifies the capture's scope, not a measured cost. The resolved package
inventory can already contain Bibliography before `using Bibliography`; an import
does not resolve a new dependency closure. Inspect `payload["loaded_libraries"]`
for images observed in this process and `payload["warnings"]` for capture failures.

The current implementation records:

- resolved Julia packages and whether they are direct, path, repository, or JLL
  dependencies;
- reachable `Artifacts.toml` files, their SHA-256 digest, and binding names;
- shared libraries loaded in the current Julia process, including size and
  architecture;
- optional binary SHA-256 digests when `hash_libraries=true`.

This is evidence, not complete tracing. It does not yet see libraries loaded
only by child processes, remote services, native heap allocations, ABI details,
or compiler/linker flags. The generated payload marks those gaps explicitly.

## Measure native work by lifecycle phase

Keep these phases separate:

1. artifact download, verification, and extraction;
2. package/JLL import and dynamic loader activity;
3. first FFI call and native initialization;
4. steady-state wrapper overhead and native execution;
5. shutdown, flushing, and child-process cleanup.

Pair Julia measurements with provider-specific artifacts when required: native
profiles, sanitizer reports, database query plans, service metrics, or operating
system counters. Instrumented diagnostics should run in a separate lane because
profilers and sanitizers perturb timing.


:::

::: details Measurement definitions and compatibility

## Measurement definitions and compatibility

## Required context

Every measurement definition states:

- metric ID, unit, collector and definition version;
- phase: resolve, install, precompile, startup, import, first execution, steady state, endurance, shutdown;
- regime: clean depot, cached depot, fresh process, warm process, steady state;
- scope: expression, method, feature, task, process, process tree, interface, service, database, device;
- clock or counter source, and whether collection is exact, repeated, sampled, static or estimated;
- sample and aggregation semantics;
- whether compilation, GC, child processes, GPU synchronization, loopback and protocol overhead are included;
- expected perturbation and required privileges;
- runtime, source, dependency, artifact, platform, hardware and environment provenance;
- a semantic outcome proving both candidates did equivalent work.

Values are comparable only when their measurement definitions and comparison keys permit it.

## Comparability in a bundle

Suite bundles retain controller thread count, hardware fingerprint, local Git revision/branch/dirty state, and SHA-256 fingerprints of the effective Project and Manifest.

- Different OS, architecture, Julia thread count or known hardware makes a comparison `incomparable`.
- A changed runtime or resolved environment is a warning, because controlled campaigns may vary one deliberately.
- Older bundles with missing fingerprints carry less comparability information.

```@raw html
<a id="Julia-performance-families"></a>
```


:::
