# Remote controllers and agents

Operate a shared service with remote workers. A local test or CI job does not need this.

Here an **agent** is a worker service on another machine, not an AI assistant. The controller and agent need compatible installed packages and the intended suite revision before accepting jobs.

## Job destinations

- `local` — run on the controller host.
- `agent:any` — lease to any compatible registered agent.
- `agent:<id>` — require one named agent.

Agents pull bounded leases and verify the immutable plan revision and selected run IDs before executing.

- The server never sends arbitrary Julia expressions or shell commands as a job payload.
- Remote execution stays tied to suite code already deployed on the agent.

```julia
using PerfChecker, PerfCheckerWeb

run_studio_agent(
    "https://perf.example/perfchecker/v1";
    agent_id = "linux-amd64-01",
    token = ENV["PERFCHECKER_AGENT_TOKEN"],
)
```

## Authentication

The built-in TOML token store suits a controlled deployment. It stores token digests, roles and optional agent restrictions.

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

## Capability matching

Before dispatch, match a job against the agent's runtime, platform, Julia version, collector packages, network-isolation provider, privileges and relevant native tools.

- An agent that can launch a command is not automatically qualified to produce comparable evidence.
- Persist the capability snapshot with each run.

## Progress and recovery

One progress model drives Oxygen, VS Code, REPL, Pluto, CLI JSONL and agents.

- States: queued, leased, running, complete, failed, cancelled.
- Consumers should use stable job/run IDs, tolerate reconnects, and verify the final bundle before accepting it into CI or documentation.

```@raw html
<a id="Hosted-controller-and-remote-agents"></a>
<a id="Authentication-and-authorization"></a>
```
