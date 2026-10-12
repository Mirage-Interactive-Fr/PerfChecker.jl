```@raw html
<a id="Optional-models-and-bounded-investigations"></a>
```

# Optional advisors

PerfChecker's deterministic advice works with no model and no network. An optional model can explain saved evidence or pick the next experiment from an explicit catalogue. Advice does not execute suggested commands. MCP implementation uses a separately configured tool and reviewed isolated checkout; see [MCP advice and implementation](mcp-advisor.md).

- Generated prose is unverified. Correctness, quality, performance and availability keep independent verdicts.
- The deterministic advisor remains the fallback for any provider failure.

## Start with saved evidence

```@raw html
<p>Download the JET walkthrough's <a href="examples/jet-dispatch/summary.json" download="summary.json">recorded summary</a> as <code>summary.json</code>. The <a href="examples/jet-dispatch/run.jl" download="run.jl">recording code</a> names its scenario <code>net-revenue</code>; the portable summary retains its two implementations but omits that scenario field and the diagnosis envelope. Restore only those fields, then derive advice through the public API:</p>
```

```julia
using PerfChecker, JSON
summary = JSON.parsefile("summary.json")
diagnosis = Dict(
    "schema_version" => "perfchecker-diagnosis/1",
    "records" => [merge(record, Dict("scenario" => "net-revenue"))
                  for record in summary["diagnosis"]])
advice = advise(diagnosis)
println("Recommendations: ", length(advice["recommendations"]))
println("Dynamic: ", count(r -> r["implementation"] == "dynamic", advice["recommendations"]))
println("Typed: ", count(r -> r["implementation"] == "typed", advice["recommendations"]))
item = first(advice["recommendations"])
for key in ("rule_id", "hypothesis", "action", "validation", "predicted_gain")
    println(key, ": ", item[key])
end
```

Actual output from this saved evidence with Core 1.1.0:

```text
Recommendations: 6
Dynamic: 6
Typed: 0
rule_id: inference.runtime_dispatch
hypothesis: JET reports an inference issue for this specialization.
action: Benchmark and profile this scenario to find out whether the diagnostic affects an expensive call path.
validation: Rerun JET, correctness checks and measurements for each affected implementation.
predicted_gain: not_measured
```

This reads the six existing JET findings; it runs no workload and contacts no
model. The typed implementation has no JET finding to explain. The advice asks
for measurements rather than claiming a speedup: the walkthrough's
[separate before/after measurements](native-profiling.md#JET:-possible-inference-and-dispatch-problems) answer
that different question.

```@raw html
<a id="Local-default-and-interchangeable-providers"></a>
```

## Providers

Enable a provider only after you have collected a measurement or diagnosis. Model configuration is not part of installing PerfChecker.

- **llama.cpp** — Chat Completions endpoint.
- **Ollama** — `/api/chat` endpoint.
- **Chat Completions** — a local or explicitly allowed remote server.
- **MCP HTTP** — one advice tool on an MCP server. See [MCP tools](mcp-advisor.md).

The supplied configurations support llama.cpp and Ollama. `model` selects the
model for Chat Completions and Ollama. An MCP server chooses its own model and
limits; provide model or limit arguments only when its selected tool schema
accepts them.

- A remote endpoint requires `allow_remote = true` and HTTPS.
- An optional credential is read from the environment variable named by `api_key_env`. Never put the secret in a config file.
- PerfChecker does not install providers, start model servers or download weights
  automatically. The [advisor panel](advisor-ui.md#Optional-local-model-files) can
  request an Ollama model download after explicit confirmation.

```julia
using PerfChecker
config = load_advisor_config("perf/advisor.json")
advice = read_advice("results/advice.json")
narrative = narrate_advice(advice; config)
display(investigation_view(narrative))
```

This optional step does contact the configured provider. Inspect
`narrative["status"]`, `narrative["cards"]` and `narrative["fallback"]`: a complete
reply remains unverified prose, while the fallback retains the deterministic
recommendations above. No model reply is presented as a recorded result here.

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

The projection does not automatically read project source, environment contents
or raw logs. It retains the supplied `hypothesis`, `action` and `validation`
strings without redaction: inspect them before sending evidence. Automatic
source-location fields and workspace roots are not added to the projection.
Chat additionally sends your typed messages and retained replies. Explicit
implementation sends its isolated checkout path and permits the selected tool
to inspect code there. Configured authentication credentials are sent in the
request header. See the [complete transmission contract](mcp-advisor.md#What-is-transmitted).

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

Inspect the result immediately:

```julia
result["status"]
[(experiment["id"], experiment["status"]) for experiment in result["experiments"]]
length(result["unexecuted"])
```

The output contains an overall state (`complete`, `budget_exhausted`,
`advisor_stopped` or `cancelled`), the attempted experiment IDs and their own
statuses, and the number left unexecuted. These are the recipe's output fields,
not a recorded model-driven campaign. Read the per-run correctness and
availability alongside them; an experiment's `complete` status does not mean
its performance passed a comparison.

- Omit `advisor` for deterministic ordering.
- A failed model decision falls back to that ordering; a valid `stop` is respected.
- Each attempt consumes the count and wall-time budgets, including model requests and worker startup.
- Provider and experiment deadlines are capped at the remaining time budget.
  Bounding a provider's timeout preserves its other configuration, including
  instructions and MCP tool, argument, response and authentication settings.
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
