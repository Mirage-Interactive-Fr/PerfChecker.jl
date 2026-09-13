# Run bundles

A run bundle is a directory holding the measurements, diagnostics and context of one run. The CLI, web interface, VS Code and report tools read the same files.

## What `/1` means

Strings such as `perfchecker-run-bundle/1` identify a **data format** — not a URL, a directory suffix or the package version. The part before the slash is the format name; `1` is its schema version.

- `perfchecker-suite-plan/1` — selected-check plan.
- `perfchecker-testitem-run/1` — test-item measurements and outcomes.
- `perfchecker-run-bundle/1` — complete run.
- `perfchecker-agent-evidence/1` — bounded evidence summary for an advisor.
- `perfchecker-query/1` — a reusable selection of results.
- `perfchecker-query-result/1` — query output.

The integer changes only when the contract requires a new reader. If your integration sees an unsupported version, report it — do not guess that it follows version 1.

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
- `integrity.json` — SHA-256 and byte length for each immutable file.

## Julia API

```julia
using PerfChecker
bundle = read_run_bundle(bundle_directory)
verify_run_bundle(bundle_directory; require_integrity = true)

bundle_passed(bundle)
bundle_dict(bundle)
list_run_bundles("perf/results"; recursive = true)
```

`write_run_bundle` writes to a temporary sibling and renames atomically. It refuses to overwrite. `migrate_run_bundle` rewrites supported legacy data into a new destination.

## Identity and reuse

- `run_id` is the logical experiment; `attempt_id` is one physical attempt.
- `reuse_key` describes the normalized plan, runtime and measurement definitions.
- Reused evidence stays labelled as reused; it never impersonates a fresh run.

Before making a regression decision, a consumer must verify integrity, schema version, completion state, diagnostic severity and measurement-definition identity.

```@raw html
<a id="Contents"></a>
```
