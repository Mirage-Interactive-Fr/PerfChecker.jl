# Web interface (Oxygen)

Select workloads and versions, start measurements and browse finished runs in a browser.

## Start a Bibliography check

From `examples/bibliography/`:

```sh
julia --startup-file=no setup.jl web
julia --startup-file=no --project=.controller/web web.jl
```

Open `http://127.0.0.1:8871/perfchecker/v1/`. Select Bibliography, `export_bibtex` and `benchmark`, review the plan, then launch.

## Reopen saved runs

```julia
using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, Oxygen, WGLMakie

serve_suite("perf/results"; host = "127.0.0.1", port = 8080)
```

Open `http://127.0.0.1:8080/perfchecker/v1/`. Rendering a saved plot does not rerun the benchmark.

## What the studio does

- select packages, features, check types, releases and Git targets;
- choose ranges instead of clicking every version;
- filter and sort result history;
- launch a local job and follow progress;
- open artifacts, logs, allocation views, distributions and flame graphs;
- serialize the current selection so another page can open the same evidence.

## Safety

Loopback is the default. Binding elsewhere is refused unless `allow_remote_control = true` and an authenticator are set.

```julia
auth = studio_token_authenticator("perf/users.toml")

serve_suite("perf/results"; host = "0.0.0.0", port = 8080,
    allow_remote_control = true, authenticator = auth)
```

The built-in token store keeps SHA-256 token digests and `admin`, `runner` and `agent` roles. Browser sessions use HttpOnly cookies and CSRF checks. TLS, token rotation, backups and public deployment remain your responsibility.

See [Remote controllers](../operations/hosted.md) before exposing a controller beyond a workstation.

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/web/selection.png" alt="Oxygen studio with one Bibliography export benchmark selected from 35 available checks" caption="Bibliography: one workload and one collector selected, with one worker thread and 50 samples." />
```

```@raw html
<DocMedia src="/examples/bibliography/history-web/history-time.png" alt="Oxygen showing the Bibliography export timing curve across nine tagged versions" caption="Nine actual measured versions, selected from the saved historical campaign. Inspect a point to read its exact version and value." />
```


```@raw html
<a id="Oxygen-web-studio"></a>
<a id="Start-with-one-Bibliography-check"></a>
<a id="Reopen-existing-suite-reports"></a>
<a id="Read-a-saved-result"></a>
<a id="Studio-workflow"></a>
<a id="Compare-a-saved-history"></a>
<a id="Other-workload-types"></a>
<a id="Safety-boundary"></a>
```
