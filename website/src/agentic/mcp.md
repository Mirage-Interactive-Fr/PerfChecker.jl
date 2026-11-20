# Connect an MCP tool

Discuss saved performance evidence with an assistant exposed by your MCP server. PerfChecker is the **client**: it discovers tools and calls the exact tool you select. The server can use any agent/provider; MCP alone supplies neither a model nor an assistant.

Core publishes **no built-in MCP server tools**. Its Julia APIs call tools supplied by the server you configure; the discovery result contains that server's actual names and schemas.

| Action | Core API | What the external server supplies |
| --- | --- | --- |
| Discover available tools | `advisor_setup` | Tool names and input schemas; no advice tool is invoked |
| Explain evidence or discuss it | `narrate_advice`, `chat_advice` | An explicitly selected advice tool; chat requires text mode |
| Prepare a reviewed code change | `implement_advice` | A separately selected implementation tool accepting the isolated checkout path |
| Select a permitted experiment | `investigate` | An explicitly configured structured-response tool; declared experiments and budgets still constrain execution |

`tools/list` and `tools/call` are protocol methods, not names of performance tools. [Implementation and bounded investigations](advice.md) explain the separate permissions and response modes.

Start your compatible Streamable HTTP server independently. Prepare a controller containing PerfChecker and HTTP, then save `perf/advisor.json` with your endpoint and discovered tool schema. This example assumes your server actually exposes `review_export(question, context)`; those names are illustrative, not supplied defaults.

```json
{
  "protocol": "mcp_http",
  "endpoint": "http://127.0.0.1:8765/mcp",
  "mcp_version": "2026-07-28",
  "mcp_tool": "review_export",
  "mcp_prompt_argument": "question",
  "mcp_arguments": {"context": {"language": "Julia"}},
  "mcp_response": "text",
  "timeout": 90,
  "max_evidence_chars": 12000,
  "allow_remote": false,
  "api_key_env": ""
}
```

Discover first, then deliberately send one question about a completed bundle:

```julia
using PerfChecker, HTTP
config = load_advisor_config("perf/advisor.json")
@assert Base.get_extension(PerfChecker, :HTTPAdvisorExt) !== nothing
setup = advisor_setup(config)
display(setup) # inventory only; inspect status and selected_available
bundle = read_run_bundle("perf/results/bundles/ACTUAL-BUNDLE")
saved_advice = advise(bundle)
messages = [Dict("role"=>"user", "content"=>
    "Explain the allocation observations. Separate facts from hypotheses and suggest one correctness check.")]
reply = chat_advice(messages; config, advice=saved_advice)
display(investigation_view(reply))
if get(reply, "status", "error") == "complete"
    push!(messages, Dict("role"=>"assistant", "content"=>reply["external_review"]))
    push!(messages, Dict("role"=>"user", "content"=>
        "Which empty-input and numeric-type cases should I verify before changing code?"))
    followup = chat_advice(messages; config, advice=saved_advice)
    display(investigation_view(followup))
end
```

These calls require your running service; no provider answer is fabricated here. Discovery returns `evidence_sent=false`, `generation_tested=false`. A completed text reply is in `external_review`, with `reference_status="unstructured_not_verified"`; read `status` separately. Suggested commands are not executed by chat. Move to [reviewed implementation](advice.md) only after agreeing on a specific change and validation.

::: details Server capabilities, privacy and cancellation

Select protocol revision `2026-07-28` or `2025-11-25` explicitly; there is no downgrade. The server must advertise the tools capability. HTTP supports JSON and request-scoped SSE, with at most 32 discovery pages. Responses are capped at 1 MB. Redirects and automatic retries are disabled.

Choose a tool that finishes one configured request. Sampling, elicitation, roots, subscriptions, tasks, interactive OAuth and multi-round-trip `input_required` are unsupported.

Messages alternate between user and assistant and end with a user question. Each request permits at most 21 messages, 16,000 characters per message and 32,000 characters in total. Replies are limited to 16,000 characters.

The Julia API does not save a conversation. Supply earlier replies when continuing it.

Narration sends bounded evidence IDs, rules, observations, proposed experiments, verifications and limits. It does not read source files, environment contents or raw logs automatically. Supplied hypothesis, action and validation text is sent without redaction. Chat also sends typed messages and retained replies; check what you paste.

Remote endpoints require HTTPS and `allow_remote=true`. Credentials are read from the named environment variable and sent in the configured header. The endpoint's data and cost policy applies.

Advice mode asks the tool to avoid edits and experiments. MCP and prompts do not enforce filesystem permissions; a trusted server must honor that contract.

Cancellation stops the local Julia worker. An external HTTP server can continue until it handles the disconnect. Failure retains deterministic fallback and does not alter measured verdicts.

:::

::: details Native stdio and editor clients

The Julia provider is HTTP; `protocol=:mcp_stdio` is not an AdvisorConfig mode. [VS Code](../interfaces/vscode.md) can adapt a native stdio server into a temporary local HTTP session.

In **Configure MCP connection and models**, choose **Local MCP server · stdio**. Enter its absolute executable, arguments as a JSON array and absolute working directory. Discover the tools, select their actual advice and implementation schemas, then explicitly connect.

No shell expansion or login is inferred. Windows command/batch launchers are unsupported. Local paths and inherited environment belong to the extension host, including Remote SSH/containers. Discovery starts the chosen process but sends no evidence or tool invocation.

The endpoint and generated credential are session-only. Closing Chat, cancellation, timeout, EOF or server exit closes the local connection. Explicitly reconnect after owned-process cleanup.

If cleanup fails, use **Retry Disconnect**. New requests remain blocked and implementation recovery state is retained. MCP does not provide an OS sandbox.

An authenticated native Codex CLI is an optional connector, alongside your own HTTP or stdio tool. The server/tool workflow above has no Codex dependency.

:::

::: details CLI client

Save your real messages in `perf/chat-request.json`:

```json
{"messages":[{"role":"user","content":"How should I validate an allocation change?"}]}
```
```sh
julia --startup-file=no --project=perf/controller -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- chat --source=perf/chat-request.json --advisor-config=perf/advisor.json
```

The CLI emits narrative JSON: exit 0 means a completed reply; exit 1 means provider failure, cancellation or timeout. It does not validate the reply's claims.

:::
