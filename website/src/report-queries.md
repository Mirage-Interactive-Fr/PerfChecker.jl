```@raw html
<a id="Report-queries-and-documentation-blocks"></a>
```

# Report queries

A query selects existing results by package, feature, metric or another field. It contains no Julia expressions and never launches a worker.

## Select and inspect records

This small **example data** fixture mirrors the query contract test. Its values
illustrate filtering; they are not benchmark results.

```julia
using PerfChecker

manifest = Dict{String, Any}(
    "schema_version" => "perfchecker-run-bundle/1",
    "run_id" => "run-query", "attempt_id" => "attempt-query",
    "suite" => "demo", "state" => "complete",
    "runtime" => Dict("language" => "julia", "version" => "1.12.7"),
)
observations = [
    Dict{String, Any}("metric" => "julia.wall.time", "value" => 2.0,
        "unit" => "s", "case_id" => "demo/parse", "target_id" => "1.0",
        "attributes" => Dict("resource" => "cpu")),
    Dict{String, Any}("metric" => "julia.alloc.bytes", "value" => 32.0,
        "unit" => "By", "case_id" => "demo/parse", "target_id" => "1.0",
        "attributes" => Dict("resource" => "memory")),
]
bundle = RunBundle(manifest, Dict{String, Any}[], observations,
    Dict{String, Any}[], Dict{String, Any}[])
query = PerformanceQuery(
    id = "julia-time", resources = [:observations],
    predicates = [QueryPredicate("metric", :equals, "julia.wall.time")],
)
result = query_bundle(bundle, query)
println("Selected observations: ", result["counts"]["observations"])
record = only(result["observations"])
println(record["metric"], " = ", record["value"], " ", record["unit"])
```

Expected output:

```text
Selected observations: 1
julia.wall.time = 2.0 s
```

The allocation record is excluded. Filtering reads the saved value; it does not
time an operation or convert units.

::: details Apply a richer query to your own saved bundle

Replace `bundle_directory` with a complete run-bundle directory, not a plot JSON:

```julia
saved_bundle = read_run_bundle(bundle_directory)
saved_query = PerformanceQuery(
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

saved_result = query_bundle(saved_bundle, saved_query)
println(saved_result["counts"])
```

The output is a count for each resource: `observations`, `diagnostics`,
`artifacts`, `plots` and `comparison`. Counts depend on your saved evidence;
each requested collection is limited to 100 records independently.

:::

- Fields address a record directly, fall back to its `attributes`, or use a `manifest.` prefix.
- Operators: `equals`, `not_equals`, `one_of`, `contains`, `prefix`, `greater_or_equal`, `less_or_equal`, `exists`.
- Queries do not invent missing data. A selection with no matching records is empty.

```@raw html
<a id="Portable-documentation-block"></a>
```

## Documentation blocks

```julia
block = PerformanceDocumentBlock(
    "julia-time", "Selected timing evidence", query;
    views = [:observations])

model = performance_document_block(bundle, block)
println(model["schema_version"])
println(model["title"])
println(model["provenance"]["run_id"])
println(model["result"]["counts"]["observations"])
```

Expected output with the example data above:

```text
perfchecker-document-block/1
Selected timing evidence
run-query
1
```

The `perfchecker-document-block/1` model carries the query result, requested views, interactive link and run/runtime/environment provenance. Rendering never executes the measured workload.

To write it as a page, load Documenter and pass this same block:

```julia
using Documenter
path = documenter_page(bundle, "docs/src/performance.md"; blocks = [block])
println(isfile(path))
```

Expected output:

```text
true
```

The generated observation table contains:

| Case | Target | Metric | Value | Unit |
| --- | --- | --- | --- | --- |
| demo/parse | 1.0 | julia.wall.time | 2.0 | s |

See [Documenter integration](interfaces/documentation.md) for the site-build step.
