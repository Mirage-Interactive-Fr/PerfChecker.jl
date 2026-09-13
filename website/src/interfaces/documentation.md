# Documenter

Generate a documentation page from a saved run. The build reads the results; it does not rerun the benchmark.

## One page

Load a saved bundle first:

```julia
using PerfChecker, Documenter

bundle = read_run_bundle(bundle_directory)

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

Add the generated page to your Documenter `pages` list. Use `documenter_makedocs` or `documenter_vitepress_makedocs` to materialize blocks during the normal build.

## Publication rules

- Publish immutable or explicitly refreshed bundles, never an unlabelled local "latest".
- Show runtime and source/dependency provenance near the chart.
- Keep a static Markdown/SVG fallback beside any interactive link.
- Redact logs, local paths, tokens and private endpoints.
- Documentation generation stays read-only with respect to the measured project.

## Next

[Run bundles](../reference/run-bundles.md) describes the files the page is built from.

```@raw html
<a id="Documenter-integration"></a>
<a id="Build-one-performance-page"></a>
<a id="Shared-declarative-configuration"></a>
```
