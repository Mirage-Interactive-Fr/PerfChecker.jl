# Report queries and documentation blocks

A query selects existing results by package, feature, metric or another field.
The same selection can be used by scripts, Web Studio, documentation and advisors.
It contains no Julia expressions and never launches a worker.

Serialized queries carry `"schema_version": "perfchecker-query/1"`: the name and
version of their JSON format. See [format identifiers](reference/run-bundles.md)
for the meaning of `/1` in this and other outputs.

This example assumes `bundle` has been loaded from a saved suite run using
`read_run_bundle`. Follow [load a Bibliography bundle](interfaces/visualization.md#Build-a-plot-from-a-saved-run)
first. It selects parser records if present; an export-only bundle has no parser
records and returns an empty selection. Queries do not invent missing data.

```julia
using PerfChecker
query = PerformanceQuery(
    id = "candidate-parser-regressions",
    resources = [:comparison, :plots, :diagnostics],
    predicates = [
        QueryPredicate("manifest.runtime.language", :equals, "julia"),
        QueryPredicate("package", :equals, "BibParser"),
        QueryPredicate("feature", :prefix, "parse"),
        QueryPredicate("metric", :one_of,
            ["julia.wall.time", "julia.alloc.bytes"]),
    ],
    order_by = ["relative_delta" => :desc],
    limit = 100,
)

result = query_bundle(bundle, query)
```

Fields can address a record directly, fall back to its `attributes`, or use a
`manifest.` prefix. The initial deterministic operators are `equals`,
`not_equals`, `one_of`, `contains`, `prefix`, `greater_or_equal`,
`less_or_equal`, and `exists`. The format reference describes schema versions; use the operators supported
by the reader version you have installed.

Oxygen exposes the same grammar through `POST /query`. It caps the request body
and result size. `POST /agent-evidence` returns a bounded
JSON object with `"schema_version": "perfchecker-agent-evidence/1"`. It separates evidence from
authority: consuming a report does not authorize a rerun, code edit,
publication or issue submission.

## Portable documentation block

```julia
block = PerformanceDocumentBlock(
    "parser-performance",
    "BibParser performance",
    query;
    views = [:summary, :comparison, :diagnostics, :plots],
)

model = performance_document_block(bundle, block)
documenter_page(bundle, "src/performance.md"; blocks = [block])
```

The `perfchecker-document-block/1` model contains the query result, requested
views, interactive link and run/runtime/environment provenance. Documenter and
DocumenterVitepress materialize it before their build; other documentation
systems can consume the same dictionary. Documentation rendering never executes
the measured workload.

For a complete documentation example, continue to
[Documenter integration](interfaces/documentation.md). Static Markdown or SVG
provides a readable fallback when an interactive renderer is unavailable.
