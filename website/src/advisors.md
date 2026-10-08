```@raw html
<a id="Optional-models-and-bounded-investigations"></a>
```

# Optional advisors

PerfChecker's deterministic advice works with no model and no network. An optional model can explain saved evidence or pick the next experiment from an explicit catalogue. Advice does not execute suggested commands. MCP implementation uses a separately configured tool and reviewed isolated checkout; see [MCP advice and implementation](mcp-advisor.md).

- Generated prose is unverified. Correctness, quality, performance and availability keep independent verdicts.
- The deterministic advisor remains the fallback for any provider failure.

```@raw html
<a id="Local-default-and-interchangeable-providers"></a>
```

## Providers

Enable a provider only after you have collected a measurement or diagnosis. Model configuration is not part of installing PerfChecker.

- **llama.cpp** — Chat Completions endpoint.
- **Ollama** — `/api/chat` endpoint.
- **Chat Completions** — a local or explicitly allowed remote server.
- **MCP HTTP** — one advice tool on an MCP server. See [MCP tools](mcp-advisor.md).

The supplied configurations support llama.cpp and Ollama. The model name is independent of the protocol.

- A remote endpoint requires `allow_remote = true` and HTTPS.
- An optional credential is read from the environment variable named by `api_key_env`. Never put the secret in a config file.
- PerfChecker never downloads a model, starts a server, or installs a provider.

```julia
using PerfChecker
config = load_advisor_config("perf/advisor.json")
advice = read_advice("results/advice.json")
narrative = narrate_advice(advice; config)
display(investigation_view(narrative))
```

For another protocol, extend the public transport function:

```julia
function PerfChecker.advisor_transport(::Val{:my_provider}, config::AdvisorConfig, request::AbstractDict)
    # Translate the bounded request; honor config.timeout.
    # Return a Dict with choices[1].message.content containing response JSON.
    # Include usage only when reported; do not substitute zero for unknown usage.
end
```

## What leaves your machine

Evidence narration sends a bounded projection:

- recommendation IDs, rules, observations, proposed experiments, verifications and limits.

The projection does not include raw logs, source files, automatic source-location fields or workspace roots. Chat additionally sends your typed messages and retained replies. Explicit implementation sends its isolated checkout path and permits the selected tool to inspect code there. Credentials are carried only in the configured authentication header. See the [complete transmission contract](mcp-advisor.md#What-is-transmitted).

Validation checks references and allowed actions — not the truth of the prose. Evidence IDs must exist; duplicates and unknown experiment IDs are rejected; response size is bounded.

```@raw html
<a id="Investigation-limits"></a>
```

## Bounded investigations

```julia
catalog = load_scenario_catalog("perf/scenarios.toml")
result = investigate(catalog; project = "perf", advisor = config,
    tools = [:jet, :alloccheck], samples = 10, max_experiments = 4,
    budget_seconds = 300, timeout = 120, reports = "results/investigation")
```

- Omit `advisor` for deterministic ordering.
- A failed model decision falls back to that ordering; a valid `stop` is respected.
- Each attempt consumes the count and wall-time budgets, including model requests and worker startup.
- An experiment marked complete means its execution completed — not that performance is acceptable.
- No threshold or baseline is adopted automatically.

```@raw html
<a id="Interfaces"></a>
```

`discover`, `sync`, `tools`, `diagnose`, `narrate`, `chat`, `implement`, `investigate` and `evaluate-advisors` have CLI counterparts. Implementation callers outside VS Code own checkpointing and diff review.

```@raw html
<a id="Evaluate-usefulness-before-increasing-autonomy"></a>
```

## Evaluate usefulness before adding autonomy

`examples/advisor-corpus` contains ordinary cases: an injected allocation, dynamic dispatch, an incorrect oracle and unavailability, with a healthy control. `expected.json` records independent labels.

Run `evaluate.jl` in a prepared environment, optionally with a provider config. The report covers evidence selection, elapsed time, omissions and unsupported rule selections.

- Writer evaluation starts from recorded advice; its timing is formatting/request cost, not discovery time.
- Investigator timing includes measurements.
- Automatic ID validation cannot grade prose fidelity or usefulness.
- Local inference has no API fee, but energy and machine costs are unmeasured.

Results from one small model and host do not establish general model accuracy.
