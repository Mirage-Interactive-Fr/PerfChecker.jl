# MCP tools

Send bounded PerfChecker evidence to one MCP advice tool. Use this only if you already have an MCP server exposing a tool that can answer an advice request. To run or inspect tests, you do not need this page.

MCP is a **tool protocol**, not a model endpoint.

- Your server must expose a tool that can answer the request, directly or through its own assistant.
- A server with only unrelated data tools cannot generate performance advice.
- PerfChecker does not install or start that server.

## Configure

Install HTTP in the dedicated controller environment. Copy `examples/advisor-corpus/mcp-local.json` to your project's `perf/advisor.json` and replace the example address and tool name. `ask` is a placeholder, not a standard tool.

- `protocol` — `mcp_http`.
- `endpoint` — local HTTP or explicitly allowed remote HTTPS.
- `mcp_version` — `2026-07-28`, or `2025-11-25` for a legacy server.
- `mcp_tool` — the one advice tool; existence is checked with `tools/list`.
- `mcp_prompt_argument` — string argument receiving prompt plus evidence (usually `prompt` or `question`).
- `mcp_arguments` — extra arguments the tool requires; cannot replace the prompt argument.
- `instructions` — up to 5,000 characters; empty uses the default request.
- `mcp_response` — `text` for advice only; `structured` for validated references and experiment selection.
- `timeout` — total isolated worker time, including startup and exchanges.

For a remote server, set `allow_remote = true` and use HTTPS. Name the Bearer-token environment variable in `api_key_env`; do not store the token in the configuration. OAuth login/refresh is not implemented. A Chat Completions model uses `chat_completions`, not `mcp_http`.

```julia
using PerfChecker
config = load_advisor_config("perf/advisor.json")
result = narrate_advice(read_advice("perf/results/advice.json"); config)
display(investigation_view(result))
```

## What is sent

- Bounded recommendation IDs, rules, observations, proposed experiments, verifications and limits.

Not sent: raw logs, source files, credentials and workspace roots.

## Text replies

Text replies are limited to 16,000 characters and appear separately from deterministic findings, carrying `reference_status = "unstructured_not_verified"`.

- Individual statements get no invented citations.
- Embedded HTML is displayed as text.
- No suggested command is executed.

## Structured investigations

Keep `advisorInvestigates = false` for advice only. To let the assistant select experiments, set `mcp_response = "structured"` and enable it. The tool must return:

```json
{
  "cards": [{"evidence_id": "an ID supplied in the request", "explanation": "Supported advice"}],
  "experiment_id": "stop"
}
```

- Unknown or duplicate evidence IDs and unknown experiment IDs are rejected.
- Count and duration budgets still apply; only declared experiments run.
- Text mode refuses experiment selection.
- There is no unrestricted handover, source editing, automatic baseline adoption or publication.

## Compatibility and failure handling

The client supports the HTTP subset needed for one tool:

- JSON and request-scoped SSE responses;
- paginated tool discovery (32 pages max);
- legacy initialization/session release;
- modern request metadata and annotated argument headers.

Protocol revisions are explicit; there is no silent downgrade. Responses are capped at 1 MB; redirects and automatic retries are disabled.

Not implemented: stdio, deprecated HTTP+SSE endpoints, sampling, elicitation, roots, subscriptions and arbitrary tool chains.

Unsupported interactions, missing tools, errors and malformed structured replies preserve the deterministic fallback. Cancellation stops the local worker; remote interruption depends on the server.

```@raw html
<a id="Send-PerfChecker-evidence-to-an-MCP-assistant"></a>
<a id="Configure-the-assistant"></a>
<a id="Prompt-and-results"></a>
<a id="Optional-bounded-investigation"></a>
```
