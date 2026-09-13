# Documenter integration

PerfChecker can generate documentation pages from saved measurements. A query
selects the records to include, and a document block specifies the tables and
figures to display. The documentation build reads those results without
rerunning the benchmark.

## Build one performance page

First [load a saved Bibliography benchmark bundle](visualization.md#Build-a-plot-from-a-saved-run)
into `bundle`. Install Documenter in the documentation environment. The example
below selects export observations from that existing bundle and writes a Markdown
page; it does not run the benchmark. Include that generated page in your own
Documenter `pages` list. Create the destination documentation project first.

```julia
using PerfChecker, Documenter

# `bundle` is the saved Bibliography bundle loaded in the preceding step.
query = PerformanceQuery(
    id = "export-latency",
    resources = [:observations, :comparison, :plots],
    predicates = [
        QueryPredicate("package", :equals, "Bibliography"),
        QueryPredicate("feature", :equals, "export_bibtex"),
        QueryPredicate("metric", :equals, "julia.wall.time"),
    ],
)
block = PerformanceDocumentBlock(
    "export-latency",
    "Bibliography export latency",
    query;
    views = [:summary, :comparison, :plots],
)

documenter_page(bundle, "docs/src/generated/performance.md"; blocks = [block])
```

Call `documenter_makedocs` or `documenter_vitepress_makedocs` when you want the
adapter to materialize blocks immediately before the normal documentation build.
The generated `perfchecker-document-block/1` model retains the query result,
requested views, interactive link, run identity, runtime, and environment.

## Shared declarative configuration

The following configuration fragment illustrates the saved JSON format;
`example-run` must be replaced with an actual plan run ID. VS Code and the web
studio can save documentation blocks beside UI selections in
`perf/perfchecker-ui.json`:

```json
{
  "schema_version": "perfchecker-ui-config/1",
  "selection": { "run_ids": ["example-run"] },
  "documentation": {
    "blocks": [{
      "schema_version": "perfchecker-document-block/1",
      "id": "network-budget",
      "title": "Network budget",
      "views": ["summary", "observations", "plots"],
      "query": {
        "schema_version": "perfchecker-query/1",
        "id": "network-budget",
        "resources": ["observations", "plots"],
        "where": [{
          "field": "metric",
          "operator": "prefix",
          "value": "network."
        }],
        "order_by": [],
        "limit": 100
      }
    }]
  }
}
```

`read_document_blocks` validates this file. Other documentation systems can
consume `performance_document_block(bundle, block)` directly; they do not need
Julia-specific rendering logic.

## Publication rules

- Publish immutable or explicitly refreshed bundles, never an unlabelled local
  “latest” directory.
- Show runtime, source/dependency provenance, measurement definition, and
  freshness near the chart.
- Link to the interactive studio for deep inspection, but preserve a static
  Markdown/SVG fallback.
- Redact logs, local paths, tokens, packet captures, and private endpoints before
  public documentation.
- Keep documentation generation read-only with respect to the measured project.
