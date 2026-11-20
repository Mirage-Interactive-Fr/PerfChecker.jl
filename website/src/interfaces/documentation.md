# Documenter

Generate documentation from a saved run bundle. The build reads existing
measurements and retains their comparison outcome; it does not rerun a check.

```@raw html
<a id="Documenter-integration"></a>
<a id="Build-one-performance-page"></a>
```

```@raw html
<a id="Generate-and-build-a-page"></a>
```

## Generate and build a page

Install Documenter alongside PerfChecker in your documentation project.
Load a real saved bundle, then generate its default version-comparison page:

```julia
using PerfChecker, Documenter

bundle = read_run_bundle("perf/results/ACTUAL-RUN/bundles/ACTUAL-BUNDLE")
documenter_page(bundle, "docs/src/generated/performance.md")
```

Add `"Performance" => "generated/performance.md"` to the existing
`Documenter.makedocs` pages list. Generate the page before building.
For a small standalone local documentation build:

```julia
Documenter.makedocs(;
    root = abspath("docs"), sitename = "Performance",
    format = Documenter.HTML(prettyurls = false),
    pages = ["Performance" => "generated/performance.md"])
```

Open `docs/build/generated/performance.html`. The default summary reports
measured series and comparisons; a single-release profile may be
**INCONCLUSIVE** because it has no comparison.

```@raw html
<p>Real saved output: <a href="../examples/tool-recipes/recorded-performance.md">generated Bibliography Markdown</a> reports <strong>INCONCLUSIVE, 2 series, 0 comparisons</strong>. Its <a href="../examples/tool-recipes/receipts.json">wrapper receipt</a> and <a href="../examples/tool-recipes/documentation-builds.json">HTML build receipt</a> record local Documenter and DocumenterVitepress builds of the allocation bundle.</p>
```

```@raw html
<a id="Shared-declarative-configuration"></a>
```

```@raw html
<a id="Select-evidence-with-document-blocks"></a>
```

## Select evidence with document blocks

A query selects the saved observations that belong on the page:

```julia
query = PerformanceQuery(
    id = "export-latency",
    resources = [:observations, :comparison, :plots],
    predicates = [
        QueryPredicate("package", :equals, "Bibliography"),
        QueryPredicate("feature", :equals, "export_bibtex"),
        QueryPredicate("metric", :equals, "julia.wall.time")])
block = PerformanceDocumentBlock("export-latency", "Bibliography export latency",
    query; views = [:observations, :comparison, :plots])
documenter_page(bundle, "docs/src/generated/performance.md"; blocks = [block])
```

The generated block contains run/runtime provenance and matching tables.
An empty selection prints `No matching evidence`; it is separate from a zero
measurement. The **Interactive plots** section lists matching plot IDs rather
than embedding figures. Supply a block's `interactive_url` to link to an
[exported Makie view](visualization.md).

Use `config = "perf/perfchecker-ui.json"` instead of `blocks` to read
`documentation.blocks` from shared configuration.
[Report queries](../report-queries.md) describes the query fields.

::: details One-call builds and VitePress

`documenter_makedocs(bundle; root="exports/docs", sitename="Performance")`
generates the default page and builds it locally in one call. For VitePress:

```julia
using DocumenterVitepress
documenter_vitepress_makedocs(bundle; root = "exports/vitepress",
    sitename = "Performance",
    repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl")
```

The wrappers do not accept custom `blocks` or `config`; use explicit page
generation and `Documenter.makedocs` for custom reports.
The shipped kitchen-sink `documenter.jl results/ACTUAL-RUN` writes
`exports/performance.md` from a completed run.

:::

Keep the complete [run bundle](../reference/run-bundles.md), its provenance and
observation units with shared figures. These commands build files locally;
publication belongs to your documentation deployment workflow.
