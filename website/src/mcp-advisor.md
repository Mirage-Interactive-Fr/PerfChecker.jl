# Send PerfChecker evidence to an MCP assistant

This optional provider is for users who already have an MCP server offering an
advice tool and a saved PerfChecker diagnosis. If you only want to run or inspect
tests, you do not need this page. Start with [advisor setup](advisor-ui.md) to
select a provider before configuring protocol details.

This integration sends a customizable request and bounded PerfChecker evidence
to one explicitly configured MCP advice tool. The default request asks, in
English, for performance-improvement clues, distinguishes observations from
hypotheses, and asks how to verify a proposed correction. It does not require
local model weights.

MCP is a tool protocol, not a model endpoint. Your server must expose a tool
that can answer a request, directly or through its own assistant. A server
containing only unrelated data tools cannot generate performance advice by
itself. PerfChecker does not install or start that server.

## Configure the assistant

Install HTTP in the dedicated PerfChecker controller environment. Copy
`examples/advisor-corpus/mcp-local.json` from the repository to your project's
`perf/advisor.json`. Replace its example address and tool name with your server's
actual settings; `ask` is a placeholder, not a guaranteed standard MCP tool.

| Setting | Purpose |
|---|---|
| `protocol` | `mcp_http` for the MCP endpoint |
| `endpoint` | Local HTTP or explicitly allowed remote HTTPS MCP endpoint |
| `mcp_version` | `2026-07-28`, or `2025-11-25` for a legacy server |
| `mcp_tool` | The one selected advice tool; its existence is checked with `tools/list` |
| `mcp_prompt_argument` | String argument receiving the combined prompt and evidence, usually `prompt` or `question` |
| `mcp_arguments` | Additional arguments required by that tool; cannot replace the generated prompt argument |
| `instructions` | Your preferences, up to 5,000 characters; empty uses the default request |
| `mcp_response` | `text` for advice only; `structured` for validated references and experiment selection |
| `timeout` | Total isolated worker time limit, including startup and MCP exchanges |

The `model` value is a report label for MCP. Selecting a model behind the tool,
if supported by that server, uses its documented `mcp_arguments` instead.

In VS Code, open **Model settings** to use the [guided advisor panel](advisor-ui.md),
test the connection and select a discovered tool. You can also set `perfchecker.advisorConfig`
to `perf/advisor.json`, or use the corresponding settings:
`advisorProtocol`, `advisorEndpoint`, `advisorMcpTool`, `advisorMcpPromptArgument`,
`advisorMcpArguments`, `advisorMcpVersion`, `advisorMcpResponse` and
`advisorInstructions`. The configuration file takes precedence over individual
settings. Run a diagnosis and choose **Explain with configured model**.

For a remote server, set `allow_remote=true` and use HTTPS. Name the optional
Bearer-token environment variable in `api_key_env`; do not store the token in
the configuration. OAuth login/refresh is not implemented. A compatible
Chat Completions model uses `chat_completions`, not `mcp_http`.

## Prompt and results

The default text-mode request asks for concrete clues to improve common Julia
code, supporting observations, hypotheses, candidate changes and verification.
Your `instructions` are prepended to this request. The payload contains bounded
recommendation IDs, rules, observations, proposed experiments, verifications and
limits. Raw logs, source files, credentials and workspace roots are not added.
This is a summary of saved evidence, not the full bundle or source code.

Text replies, limited to 16,000 characters, appear separately from deterministic
findings in VS Code, JSON/Markdown reports and the shared HTML/REPL/Pluto view.
They carry `reference_status="unstructured_not_verified"`; individual statements
are not assigned invented citations. Embedded HTML is displayed as text.
No instruction or suggested command in that reply is executed.

Julia and the CLI use the same file:

```julia
using PerfChecker
config = load_advisor_config("perf/advisor.json")
result = narrate_advice(read_advice("perf/results/advice.json"); config)
display(investigation_view(result))
```

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- narrate --source=perf/results/advice.json --advisor-config=perf/advisor.json --project=perf
```

## Optional bounded investigation

Keep `advisorInvestigates=false` for advice only. To let the assistant select
experiments, explicitly choose `mcp_response="structured"` and enable
`advisorInvestigates`. The selected tool must follow the JSON response contract:

```json
{
  "cards": [{"evidence_id": "an ID supplied in the request", "explanation": "Supported advice"}],
  "experiment_id": "stop"
}
```

It may replace `stop` with one of the experiment IDs supplied in that request.
Unknown/duplicate evidence IDs and unknown experiment IDs are rejected. The
existing count and duration budgets apply; PerfChecker executes only declared
experiments. Text mode refuses experiment selection. There is no unrestricted
handover, source editing, automatic baseline adoption or publication.

The configured server/tool has its own permissions. This integration supplies
neither filesystem roots nor access to the target repository; select an advice
tool whose behavior matches this mode of use.

## Compatibility and failure handling

The client supports the HTTP subset needed for one selected advice tool:
JSON and request-scoped SSE responses, paginated tool discovery (32 pages max),
legacy initialization/session release, and modern request metadata and annotated
argument headers. Protocol revisions are explicit; there is no silent downgrade.
Responses are capped at 1 MB, redirects and automatic retries are disabled.

Stdio, deprecated HTTP+SSE endpoints, sampling, elicitation, roots, subscriptions
and arbitrary tool chains are not implemented. Unsupported client interactions,
missing tools, errors and malformed structured replies preserve the deterministic
fallback. Cancellation stops the local worker; remote interruption depends on
the server honoring transport cancellation. No external server is qualified
merely by passing the local protocol tests.

Protocol references: [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning),
[Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).
