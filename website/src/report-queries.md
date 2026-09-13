# Report queries

A query selects existing results by package, feature, metric or another field. It contains no Julia expressions and never launches a worker.

```julia
using PerfChecker

query = PerformanceQuery(
    id = "candidate-parser-regressions",
    resources = [:comparison, :plots, :diagnostics],
    predicates = [
        QueryPredicate("manifest.runtime.language", :equals, "julia"),
        QueryPredicate("package", :equals, "BibParser"),
        QueryPredicate("feature", :prefix, "parse"),
        QueryPredicate("metric", :one_of, ["julia.wall.time", "julia.alloc.bytes"]),
    ],
    order_by = ["relative_delta" => :desc],
    limit = 100,
)

result = query_bundle(bundle, query)
```

- Fields address a record directly, fall back to its `attributes`, or use a `manifest.` prefix.
- Operators: `equals`, `not_equals`, `one_of`, `contains`, `prefix`, `greater_or_equal`, `less_or_equal`, `exists`.
- Queries do not invent missing data. A selection with no matching records is empty.

## Documentation blocks

```julia
block = PerformanceDocumentBlock(
    "parser-performance", "BibParser performance", query;
    views = [:summary, :comparison, :diagnostics, :plots])

model = performance_document_block(bundle, block)
documenter_page(bundle, "src/performance.md"; blocks = [block])
```

The `perfchecker-document-block/1` model carries the query result, requested views, interactive link and run/runtime/environment provenance. Rendering never executes the measured workload.

See [Documenter integration](interfaces/documentation.md) for a complete page.

```@raw html
<a id="Report-queries-and-documentation-blocks"></a>
<a id="Portable-documentation-block"></a>
```
