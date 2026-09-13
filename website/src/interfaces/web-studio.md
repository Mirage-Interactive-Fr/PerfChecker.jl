```@raw html
<a id="Oxygen-web-studio"></a>
```

# Web interface (Oxygen)

The web interface lets you select workloads and versions, start measurements and
browse completed runs. It uses Oxygen to serve the interface and Makie or SVG
plots to display the results.

## Start with one Bibliography check

From `examples/bibliography/` in a PerfChecker checkout, prepare and launch the
example's web environment:

```sh
julia --startup-file=no setup.jl web
julia --startup-file=no --project=.controller/web web.jl
```

Open `http://127.0.0.1:8871/perfchecker/v1/`. Select Bibliography,
`export_bibtex` and `benchmark`, review the one-leaf plan, then launch it.
The [complete walkthrough](../tutorials/bibliography.md#Open-the-web-studio)
shows the controls and resulting report. Preparation resolves dependencies;
opening the page does not start a benchmark.

## Reopen existing suite reports

For your own report store, use the API below in an environment containing the
listed interface packages. Replace `perf/results` with the directory containing
your saved suite results. To launch new measurements, use a suite launcher such
as the Bibliography example above.

```julia
using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, Oxygen, WGLMakie

serve_suite(
    "perf/results";
    host = "127.0.0.1",
    port = 8080,
)
```

Open `http://127.0.0.1:8080/perfchecker/v1/`.

## Read a saved result

The job's progress describes orchestration; the selected graph describes its
recorded measurement. For Bibliography export, a timing curve shows elapsed
cost for the declared operation, a distribution shows individual samples, and
an allocation curve shows bytes allocated. Rendering the graph does not rerun
the benchmark. Time spent waiting for a plot to appear is not export latency.

Select the same collector and measurement boundary across versions before
interpreting a difference. A flame graph instead helps locate sampled work;
its width can represent CPU samples, task samples or allocation bytes. Follow
the [measurement tutorial](../guide/understanding-measurements.md) for units,
GC, examples and an interactive explanation of these weights.

## Studio workflow

The studio uses the shared suite-plan and UI-configuration contracts to:

- select packages, features, check types, releases, and Git targets;
- choose ranges instead of dragging every version card;
- filter and sort long result histories;
- attach colour labels and reorder selections;
- launch a local or authorized remote job and follow progress;
- open matching artifacts, logs, allocation views, distributions, and flame
  graphs;
- serialize query/filter state so a documentation page or agent can open the
  same evidence.

```@raw html
<DocMedia src="/examples/bibliography/web/selection.png" alt="Oxygen studio with one Bibliography export benchmark selected from 35 available checks" caption="Bibliography: one workload and one collector selected, with one worker thread and 50 samples." />
```

Follow the [Bibliography walkthrough](../tutorials/bibliography.md#Watch-one-export-check)
for the complete recorded run, its commands, captions and result screenshot.
Its workload selector groups the five collectors under one workload name.
Changing a plot hides the previous figure until the new one has loaded, so a
pending request cannot be mistaken for the selected result.

## Compare a saved history

The [Bibliography walkthrough](../tutorials/bibliography.md#Explore-all-nine-versions-in-Oxygen)
includes a recorded exploration of nine tagged versions. Select the historical
run, keep the export workload selected, and switch between time, allocated bytes,
sample distributions and changes from 0.1.0. Each view answers a different
question; the [measurement guide](../guide/understanding-measurements.md)
explains the units and interpretation.

```@raw html
<DocMedia src="/examples/bibliography/history-web/history-time.png" alt="Oxygen showing the Bibliography export timing curve across nine tagged versions" caption="Nine actual measured versions, selected from the saved historical campaign. Inspect a point to read its exact version and value." />
```

## Other workload types

For existing `@testitem` declarations, use the
[native-item page and routes](../test-items.md#Interfaces). For an advanced
shared workload contract, `serve_suite(::ScenarioCatalog)` opens the
[scenario investigation studio](../shared-scenarios.md). These entry points
accept different inputs; a suite file, scenario catalogue and item report are
not interchangeable.

## Safety boundary

Loopback is the default. Binding to a non-loopback address is rejected unless
`allow_remote_control=true` and an authenticator is installed. This protects
against accidentally exposing an endpoint that can execute package workloads.

The following operator configuration requires an existing token store at
`perf/users.toml`. It is not needed for the local example above.

```julia
auth = studio_token_authenticator("perf/users.toml")

serve_suite("perf/results";
    host = "0.0.0.0",
    port = 8080,
    allow_remote_control = true,
    authenticator = auth,
)
```

The built-in token store keeps SHA-256 token digests and supports `admin`,
`runner`, and `agent` roles with optional allowed-agent IDs. Browser sessions use
HttpOnly cookies and state-changing requests are protected by CSRF checks. TLS,
token issuance/rotation, reverse-proxy hardening, backups, and public deployment
remain operator responsibilities.

See [hosted controller and agents](../operations/hosted.md) before exposing a
controller outside a developer workstation.
