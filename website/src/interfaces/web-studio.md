```@raw html
<a id="Oxygen-web-studio"></a>
```

# Web interface (Oxygen)

Select workloads and versions, start measurements and browse finished runs in a browser.

The interruption and cleanup behavior on this page requires the
[corrected Web source](../guide/installation.md#Web-controller-with-corrected-shutdown).
The older root tag `v1.0.0` does not contain that correction, even though the
Web companion's own package version is still 1.0.0.

```@raw html
<a id="Start-with-one-Bibliography-check"></a>
```

## Start a Bibliography check

From `examples/bibliography/`:

```sh
julia --startup-file=no setup.jl web
julia --startup-file=no --project=.controller/web web.jl
```

After starting `web.jl` above, open `http://127.0.0.1:8871/perfchecker/v1/`
on the same machine. This local address is available only while the server is
running. Select Bibliography, `export_bibtex` and `benchmark`, review the plan,
then launch.

```@raw html
<a id="Reopen-existing-suite-reports"></a>
<a id="Read-a-saved-result"></a>
```

## Reopen saved runs

```julia
using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, Oxygen, WGLMakie

serve_suite("perf/results"; host = "127.0.0.1", port = 8080)
```

After `serve_suite` starts, open `http://127.0.0.1:8080/perfchecker/v1/`
on the same machine. Keep that Julia server running while using the interface.
Rendering a saved plot does not rerun the benchmark.

```@raw html
<a id="Studio-workflow"></a>
```

## What the studio does

- select packages, features, check types, releases and Git targets;
- choose ranges instead of clicking every version;
- filter and sort result history;
- launch a local job and follow progress;
- open artifacts, logs, allocation views, distributions and flame graphs;
- serialize the current selection so another page can open the same evidence.

```@raw html
<a id="Compare-a-saved-history"></a>
```

For a saved history, follow the [nine-version Bibliography exploration](../tutorials/bibliography.md#Explore-all-nine-versions-in-Oxygen).
```@raw html
<a id="Other-workload-types"></a>
```

For other inputs, use the [native TestItem routes](../test-items.md#Interfaces)
or [scenario studio](../shared-scenarios.md#Interfaces); a suite, scenario catalog
and native-item report have different entry points.

```@raw html
<a id="Safety-boundary"></a>
```

## Safety

The saved-directory overload above is a report viewer. To launch measurements,
load a `SoftwareSuite`, whose workload code is installed on the controller.
Loopback is the default. A suite controller refuses other bindings unless
`allow_remote_control = true` and an authenticator are set.

```julia
suite = load_software_suite("suite.jl")
auth = studio_token_authenticator("perf/users.toml")

serve_suite(suite; host = "0.0.0.0", port = 8080,
    profile = :quick, reports_root = "perf/results",
    allow_remote_control = true, authenticator = auth,
    secure_cookies = true)
```

The built-in token store keeps SHA-256 token digests and `admin`, `runner` and `agent` roles. Browser sessions use HttpOnly cookies and CSRF checks. TLS, token rotation, backups and public deployment remain your responsibility.

Use the server's LAN hostname or its HTTPS public hostname in the browser;
`0.0.0.0` is a binding address, not a destination. Keep port 8080 behind the
intended private network or HTTPS proxy. The browser's token entry creates a
session; it expires automatically, or can be revoked through `DELETE /session`
with its CSRF token. There is currently no Sign out button; see the
[session API example](../operations/hosted.md#Browser-sessions).
A controller running on another computer
measures that computer, unless the plan explicitly selects a registered remote
worker.

**Cancel** marks a job cancelled immediately. For a local job, wait for its
`worker_state` to finish cleanup; an incomplete cleanup changes the final job
to `failed` and retains its error/inventory paths. For a remote job, Cancel
rejects its result but does not stop the agent's measurement. Interrupt that
agent once on its host and let cleanup finish. Force-killing a process can leave
workers and `.mem` traces behind. See
[cancel and stop safely](../operations/hosted.md#Cancel-and-stop-safely) for lease
recovery and the distinction between a cancelled job and a stopped worker.

See [Remote controllers](../operations/hosted.md) for the token-store format,
requests and responses, remote-worker setup and recovery.

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/web/selection.png" alt="Oxygen studio with one Bibliography export benchmark selected from 35 available checks" caption="Bibliography: one workload and one collector selected, with one worker thread and 50 samples." />
```

```@raw html
<DocMedia src="/examples/bibliography/history-web/history-time.png" alt="Oxygen showing the Bibliography export timing curve across nine tagged versions" caption="Nine actual measured versions, selected from the saved historical campaign. Inspect a point to read its exact version and value." />
```
