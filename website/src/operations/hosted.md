```@raw html
<a id="Hosted-controller-and-remote-agents"></a>
```

# Remote controllers and agents

Operate a shared service with remote workers. A local test or CI job does not need this.

Here an **agent** is a worker service on another machine, not an AI assistant. The controller and agent need compatible installed packages and the intended suite revision before accepting jobs.

## Start the controller

Prepare the [Web controller](../interfaces/web-studio.md) locally first. Install
the same suite code and collectors on the host that will execute jobs. Load the
suite, rather than a saved result directory:

```julia
using PerfChecker, PerfCheckerWeb

suite = load_software_suite("perf/suite.jl")
auth = studio_token_authenticator("perf/users.toml")
serve_suite(suite; host = "0.0.0.0", port = 8080,
    profile = :quick, reports_root = "perf/results",
    allow_remote_control = true, authenticator = auth,
    secure_cookies = true)
```

For a cloud host, terminate HTTPS at a reverse proxy and forward the complete
`/perfchecker/v1/` prefix to this service. For a LAN host, use its reachable
hostname and the same HTTPS setup. The hostname below is a placeholder for your
own deployment, not a PerfChecker-hosted service. Restrict access to the intended
users and keep the Julia process running. A reverse proxy does not install the
suite or its worker dependencies.

## Job destinations

- `local` — run on the controller host.
- `agent:any` — lease to any compatible registered agent.
- `agent:<id>` — require one named agent.

Agents pull bounded leases and verify the immutable plan revision and selected run IDs before executing.

- The server never sends arbitrary Julia expressions or shell commands as a job payload.
- Remote execution stays tied to suite code already deployed on the agent.

```julia
using PerfChecker, PerfCheckerWeb

suite = load_software_suite("perf/suite.jl")
run_studio_agent(
    suite;
    server = "https://perf.example/perfchecker/v1",
    agent_id = "linux-amd64-01",
    token = ENV["PERFCHECKER_AGENT_TOKEN"],
)
```

Run this on the worker, in its prepared controller environment. Its suite plan
must match the controller's immutable revision and selected rows. Remote HTTP
is refused; use HTTPS. Plain HTTP is available for a deliberate loopback test.
Choose `agent:linux-amd64-01` in the launch plan to require this worker, or
`agent:any` to accept a compatible worker. A queued remote job waits for a lease;
it does not silently run on the controller instead.

```@raw html
<a id="Authentication-and-authorization"></a>
```

## Authentication

The built-in TOML token store suits a controlled deployment. It stores token digests, roles and optional agent restrictions.

Create `perf/users.toml` with a digest of a token you generate and keep privately:

```toml
[[users]]
id = "operator"
token_sha256 = "REPLACE_WITH_64_HEX_DIGEST"
roles = ["runner"]

[[users]]
id = "worker"
token_sha256 = "REPLACE_WITH_ANOTHER_64_HEX_DIGEST"
roles = ["agent"]
agent_ids = ["linux-amd64-01"]
```

The placeholders intentionally fail validation until replaced. Compute a digest
in Julia from a token supplied privately through the environment:

```julia
using SHA
digest = bytes2hex(SHA.sha256(ENV["PERFCHECKER_STUDIO_TOKEN"]))
```

Put that digest in the user store and keep the token outside the repository.
Supply the worker's separate token through `PERFCHECKER_AGENT_TOKEN`, as in the
example above. A digest is not a token accepted by the service.

- `admin` — UI administration.
- `runner` — job creation.
- `agent` — agent leasing.

Install a custom authenticator/authorizer when identity must come from an existing service.

For any non-loopback deployment:

1. require `allow_remote_control = true` explicitly;
2. provide an authenticator;
3. terminate TLS at Oxygen or a hardened reverse proxy;
4. rotate and scope tokens; keep them out of repositories and logs;
5. isolate controller/agent service accounts and writable directories;
6. set retention, backup and redaction policies for bundles and artifacts;
7. restrict which suite revisions are deployed to agents.

HttpOnly cookies and CSRF checks protect browser actions; they do not replace network policy, TLS, secret management, OS isolation or audit retention.

## Inspect and launch through HTTP

The Studio uses these routes too. For a scripted client, install `HTTP` and
`JSON` in its environment. Set `PERFCHECKER_STUDIO_URL` to your HTTPS prefix and
`PERFCHECKER_STUDIO_TOKEN` to a runner token. Do not print request headers.

```julia
using HTTP, JSON

base = rstrip(ENV["PERFCHECKER_STUDIO_URL"], '/')
headers = ["Authorization" => "Bearer " * ENV["PERFCHECKER_STUDIO_TOKEN"]]
capabilities = JSON.parse(String(HTTP.get(base * "/capabilities", headers).body))
identity = JSON.parse(String(HTTP.get(base * "/me", headers).body))
plan = JSON.parse(String(HTTP.get(base * "/suite-plan?profile=quick", headers).body))

# Inspect package, feature, backend, version and status before choosing a row.
rows = plan["runs"]
[(row["id"], row["package"], row["feature"], row["backend"], row["status"])
 for row in rows]
```

`capabilities` reports `perfchecker-capabilities/1`, whether the controller is
read-only, supported profiles and concurrency. `/me` returns the authenticated
identity. The plan contains its `plan_revision` and the actual run IDs; use those
IDs rather than constructing them from display labels.

After inspecting the rows, assign `chosen_id` to the ID of the check you want:

```julia
chosen_id = "PASTE_REVIEWED_RUN_ID" # Copy the exact ID from the inspected rows.
payload = Dict(
    "profile" => "quick", "plan_revision" => plan["plan_revision"],
    "selected_run_ids" => [chosen_id], "execution_target" => "local",
)
response = HTTP.post(base * "/jobs",
    [headers; "Content-Type" => "application/json"], JSON.json(payload))
job = JSON.parse(String(response.body))
job_id = job["job_id"]

status = JSON.parse(String(HTTP.get(base * "/jobs?id=" * job_id, headers).body))
# To cancel this job explicitly:
# HTTP.post(base * "/jobs/cancel", [headers; "Content-Type" => "application/json"],
#     JSON.json(Dict("job_id" => job_id)))
```

A launch returns HTTP 202 with the job ID, state and progress. Query the same ID
until it reaches `complete`, `failed` or `cancelled`; inspect its final report
rather than treating acceptance as success. For a remote worker, replace
`local` with the intended `agent:<id>` or `agent:any`.

### Cancel and stop safely

`POST /jobs/cancel` immediately marks the controller's job `cancelled`. What
happens to the measurement depends on its destination:

- **Local job:** the controller requests cooperative interruption of its suite.
  Poll `worker_state` until it reaches `cancelled` or `failed`; the job's
  `state = "cancelled"` alone does not prove that cleanup has finished. If worker
  or allocation-trace cleanup fails, the final job becomes `failed` and its
  `message` preserves the error and retained private-inventory paths.
- **Remote job:** cancellation invalidates the lease and rejects a late result.
  It does **not** interrupt the agent's current synchronous measurement.
  Heartbeats carry progress, not stop commands. Interrupt the agent process
  once on its own host and allow its worker and trace cleanup to finish.

The agent exits on `InterruptException` or `CheckCleanupFailure`, including
with `once=false`; it does not claim another job after either event. Ordinary
job/reporting errors can continue to the next lease with `once=false`. A fatal
exit leaves the current lease unresolved. On a later claim, an expired lease
can be retried until the controller's `max_agent_attempts` limit is reached.
Restarting a controller also recovers leased work for another attempt. Design
workloads to tolerate replay; execution is not exactly once.

Force-killing the controller or agent, a power loss, or repeated interrupts can
bypass cleanup and leave workers or `.mem` files behind. A retained inventory
is diagnostic evidence, not permission to delete every `.mem` file in a tested
package. Follow [allocation cleanup and ownership](../reference/checks.md)
before restarting after a cleanup failure.

| Response | Recovery |
| --- | --- |
| 401 | Check the token and selected service; a token digest cannot authenticate |
| 403 | Use an identity with the required runner or agent role |
| 409, `suite plan is stale` | Fetch and review the current plan, then submit its revision and IDs |
| 400 | Read the returned error; check profile, selected rows and bounded overrides |
| 404 for a job | Verify the exact job ID and controller URL |

### Browser sessions

Browser users enter their token in Studio, which exchanges it for an HttpOnly
session cookie. Subsequent browser actions include the session's CSRF token;
the Bearer-token example above does not reuse browser cookies. Studio currently
has no Sign out button. A session expires after `session_hours` (eight hours by
default). To revoke it immediately, use the session API from the browser's
developer console on the Studio page:

```javascript
const base = document.body.dataset.apiBase;
const session = await fetch(`${base}/session`).then(response => response.json());
const response = await fetch(`${base}/session`, {
  method: "DELETE",
  headers: { "X-CSRF-Token": session.csrf_token },
});
if (!response.ok) throw new Error(`Session revocation failed: ${response.status}`);
```

This removes the server-side session and expires its cookie. It does not revoke
the original bearer token; rotate that credential separately when needed.

## Capability matching

Before dispatch, match a job against the agent's runtime, platform, Julia version, collector packages, network-isolation provider, privileges and relevant native tools.

- An agent that can launch a command is not automatically qualified to produce comparable evidence.
- Persist the capability snapshot with each run.

## Progress and recovery

One progress model drives Oxygen, VS Code, REPL, Pluto, CLI JSONL and agents.

- States: queued, leased, running, complete, failed, cancelled.
- Consumers should use stable job/run IDs, tolerate reconnects, and verify the final bundle before accepting it into CI or documentation.
