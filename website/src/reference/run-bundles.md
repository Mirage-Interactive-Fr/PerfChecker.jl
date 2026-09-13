# Run bundles

A run bundle is a directory containing the measurements, diagnostics and context
of one run. The CLI, Web interface (Oxygen), VS Code and report tools read the same files.
You can archive this directory as a CI artifact and inspect it later.

## What does `/1` mean?

Strings such as `perfchecker-run-bundle/1` and `perfchecker-agent-evidence/1`
identify **data formats**. The part before the slash names the format; `1` is
its schema version. It is not a URL, a directory suffix, a test count or the
version of the PerfChecker package.

You see the identifier in the `schema_version` field of JSON output. For example,
the beginning of a bundle's `manifest.json` contains this field:

```json
{
  "schema_version": "perfchecker-run-bundle/1"
}
```

This is a field excerpt, not a complete manifest. Readers use it to decide
whether they understand the file's structure. The format version changes when
the contract requires a new reader; it does not change for every run.

For a suite plan, `perfchecker-suite-plan/1` can be read as **“test plan, file
format version 1.”** The name identifies the kind of document. The integer
identifies the rules for reading it: which fields exist and what they mean.
Each kind of document has its own version number.

Why is there no `/2` or `/10` here? These documented formats still use their
first version. A future incompatible change could introduce `/2`; further
revisions could eventually reach `/10`. These are examples of possible future
identifiers, not formats currently supported by PerfChecker. Bug fixes, new
test runs and package releases do not automatically require a new file format.

For example, changing a field from a list of selected checks to a different
structure could require a new format version so an older consumer does not
silently interpret it incorrectly. An ordinary compatible change need not do
so. If your integration encounters an unsupported version, report it explicitly
instead of guessing that the file follows version 1.

You do not choose this integer when running a check. PerfChecker writes it in
the output. It matters when developing an integration or migrating saved data;
it is not a setting needed for the tutorials.

| Identifier | Where you encounter it | Meaning |
| --- | --- | --- |
| `perfchecker-suite-plan/1` | Serialized plan returned by the planning API | Version 1 of the selected-check plan format |
| `perfchecker-testitem-run/1` | JSON output from running selected test items | Version 1 of item measurements and outcomes |
| `perfchecker-run-bundle/1` | `manifest.json` in an archived run | Version 1 of the complete run format |
| `perfchecker-agent-evidence/1` | Dictionary returned by `agent_evidence(bundle)` | Version 1 of a selected evidence summary for an advisor |
| `perfchecker-query/1` | Serialized `PerformanceQuery` | Version 1 of a reusable selection of results |
| `perfchecker-query-result/1` | Serialized query output | Version 1 of the selected results |

For example, `agent_evidence(bundle)["schema_version"]` returns the string
`"perfchecker-agent-evidence/1"`. The evidence itself is in the other fields of
that dictionary. See [Queries and documentation blocks](../report-queries.md)
for selecting and displaying those results.

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

## Contents

- `manifest.json`: run/attempt identity, state, suite plan, runtime,
  environment, capabilities, timestamps, reuse key, and warnings;
- `measurement-definitions.json`: versioned meaning, unit, preference, method,
  scope, and comparability of each metric;
- `observations.jsonl`: numeric or categorical evidence with comparison keys and
  attributes;
- `diagnostics.jsonl`: compatibility failures, collector warnings, attribution
  findings, and other non-observation evidence;
- `artifacts.json`: metadata for profiles, plots, logs, and provider artifacts;
- `integrity.json`: SHA-256 and byte length for every immutable protocol file.

Large files live under `artifacts/`; metadata should carry media type,
sensitivity, and provenance. Integrity covers the protocol documents, while
artifact-specific digests belong in artifact records.

## Julia API

Use `bundle_directory` from the [saved Bibliography plot example](../interfaces/visualization.md#Build-a-plot-from-a-saved-run),
or the path to any existing suite bundle containing `manifest.json`:

```julia
using PerfChecker
bundle = read_run_bundle(bundle_directory)
verify_run_bundle(bundle_directory; require_integrity = true)

bundle_passed(bundle)
bundle_dict(bundle)
list_run_bundles("perf/results"; recursive = true)
```

`write_run_bundle` writes to a temporary sibling and atomically renames the
directory. It refuses to overwrite an existing destination. `migrate_run_bundle`
rewrites supported legacy data into a new destination rather than mutating the
source in place.

## Identity and reuse

`run_id` is the logical experiment; `attempt_id` identifies one physical
attempt. A content-derived `reuse_key` describes the normalized plan, runtime,
and measurement definitions. Reused evidence must remain labelled as reused and
must never silently impersonate a fresh run.

Consumers must verify integrity, schema version, completion state, diagnostic
severity, measurement-definition identity, and semantic outcome before making a
regression decision.
