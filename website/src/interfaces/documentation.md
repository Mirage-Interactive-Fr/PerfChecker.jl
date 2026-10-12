```@raw html
<a id="Documenter-integration"></a>
```

# Documenter

Generate a documentation page from a saved run. The build reads the results; it does not rerun the benchmark.

```@raw html
<a id="Build-one-performance-page"></a>
```

## One page

Run from your package root, with PerfChecker and Documenter installed in the
active project. Set `bundle_directory` to an existing saved bundle:

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
    views = [:observations, :comparison, :plots],
)

destination = documenter_page(bundle, "docs/src/generated/performance.md";
    blocks = [block])
println(relpath(destination, pwd()))
println(join(first(split(read(destination, String), '\n'), 3), '\n'))
```

Expected output:

```text
docs/src/generated/performance.md
# Performance

## Bibliography export latency
```

Below this heading, the generated page shows the bundle's run ID and runtime,
then **Comparisons**, **Observations** and **Interactive plots**. Each table
contains only matching saved evidence. A selection with no observations prints
`_No matching evidence._`; it does not become a zero-time measurement.

```@raw html
<a id="Shared-declarative-configuration"></a>
```

Build the generated page with Documenter, preserving the blocks selected above:

```julia
Documenter.makedocs(;
    root = abspath("docs"),
    sitename = "Performance",
    format = Documenter.HTML(prettyurls = false),
    pages = ["Performance" => "generated/performance.md"],
)
println(isfile("docs/build/generated/performance.html"))
```

Expected output after a successful HTML build:

```text
true
```

Open `docs/build/generated/performance.html` to read the generated tables.
`prettyurls = false` keeps that file directly openable from disk. This build
creates local documentation; it does not publish the site.

In an existing documentation build, add `"generated/performance.md"` to its
`pages` list instead. Generate the page before calling `Documenter.makedocs`.
To read blocks from a shared UI configuration, replace `blocks = [block]` in
`documenter_page` with `config = "perf/perfchecker-ui.json"`; the configuration
must contain `documentation.blocks`. See [Report queries](../report-queries.md).

The page includes observation and comparison tables. Its **Interactive plots**
section lists matching saved plot IDs; it does not embed the figures. Export a
view with [Makie](visualization.md) and supply its published URL as the block's
`interactive_url` to add a link.

For the default version-comparison summary, `documenter_makedocs` generates a
page and builds it in one call; `documenter_vitepress_makedocs` selects the
VitePress formatter. These wrappers do not accept custom `blocks` or `config`.
Use the explicit page-generation and build steps above for customized reports.

## Publication rules

- Publish immutable or explicitly refreshed bundles, never an unlabelled local "latest".
- Show runtime and source/dependency provenance near the chart.
- Keep the observation table and provenance beside each interactive view.
- Redact logs, local paths, tokens and private endpoints.
- Documentation generation stays read-only with respect to the measured project.

## Next

[Run bundles](../reference/run-bundles.md) describes the files the page is built from.
