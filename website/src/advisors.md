# Optional models and bounded investigations

PerfChecker's deterministic advice is available without an AI dependency. An optional model can explain saved evidence or select the next experiment from an explicit catalogue. It cannot modify code or execute generated commands. Generated prose remains unverified; correctness, quality, performance and availability retain their independent verdicts.

## Local default and interchangeable providers

For step-by-step setup in VS Code and Julia, model removal, and a remote-provider
template, start with the [advisor setup guide](advisor-ui.md).
Use it after collecting a measurement or diagnosis; model configuration is not
part of installing PerfChecker.
An [MCP advice tool](mcp-advisor.md) can receive the same evidence with a custom
request, returning either free-text advice or structured experiment selections.
`instructions` customizes the request for local and remote model providers too.

Prepare an isolated controller environment with PerfChecker and HTTP. Start a local server yourself, then select its model and endpoint. PerfChecker never downloads a model, starts a server, or installs a provider implicitly.

The following API example requires a saved diagnosis/advice report at
`results/advice.json` and a provider configuration. The configuration path shown
is relative to a PerfChecker checkout; copy and adapt that file as described in
[advisor setup](advisor-ui.md) before using it in your own project.

```julia
using PerfChecker
config = load_advisor_config("examples/advisor-corpus/llama-local.json")
advice = read_advice("results/advice.json")
narrative = narrate_advice(advice; config)
display(investigation_view(narrative))
```

The supplied configurations support llama.cpp's Chat Completions endpoint and Ollama's `/api/chat` endpoint. The model name is independent of the protocol. Other compatible servers can use the same adapter. A remote endpoint requires explicit `allow_remote=true` and HTTPS; an optional credential is read from the environment variable named by `api_key_env`. Do not put the secret itself in configuration files. The default requires no paid API.

`llama-constrained.json` selects `chat_completions_schema`, which additionally
requests a JSON schema restricting the response to known evidence and experiment
IDs. The server must support this schema dialect; rejection is an explicit error,
not a silent downgrade. PerfChecker still validates the entire response, including
duplicate references and prose length. Constrained decoding improves format
reliability, not the truth or usefulness of the explanation. See
[Specializing a local model](model-specialization.md) for the separate training path.

For another protocol, a Julia package can extend the public transport function:

```julia
using PerfChecker
function PerfChecker.advisor_transport(::Val{:my_provider}, config::AdvisorConfig, request::AbstractDict)
    # Translate the bounded request to your provider, honoring config.timeout.
    # Return a Dict with choices[1].message.content containing the response JSON.
    # Include usage only when reported; do not substitute zero for unknown usage.
end
```

Set `protocol="my_provider"` and `provider_package="YourProvider"` in the advisor configuration. The isolated worker loads that installed package. A custom provider need not depend on HTTP. Provider code is executable trusted Julia code, like an analyzer extension; generated model output is never loaded as Julia code.

Only a bounded projection of recommendations and allowed experiment descriptions is sent. Raw process logs, source files and automatic source-location fields are excluded. Recommendation text is still project information. Returned evidence IDs must exist, duplicate IDs are rejected, response size is bounded, and selected experiments must belong to the allowlist. These checks establish references and allowed actions, not semantic truth of the prose. Failed, absent, cancelled or incompatible providers retain the deterministic advice as `fallback`.

## Investigation limits

```julia
catalog = load_scenario_catalog("perf/scenarios.toml")
result = investigate(catalog; project="perf", advisor=config,
    tools=[:jet, :alloccheck], samples=10, max_experiments=4,
    budget_seconds=300, timeout=120, reports="results/investigation")
```

Omit `advisor` for deterministic experiment ordering. A failed model decision falls back to this ordering; a valid `stop` is respected. Each attempt consumes the count and wall-time budgets, including model requests and worker startup. Completed evidence and unexecuted experiments are reported separately. An experiment marked complete means its execution completed, not that its performance is acceptable. No threshold or baseline is adopted automatically. Compare explicit before/after runs separately after correcting the target code; keep the shared oracle and measurement contract stable. Changes to the scenario or fixtures can make measurements incomparable and require review.

`discover`, `sync`, `tools`, `diagnose`, `narrate`, `investigate` and `evaluate-advisors` have CLI counterparts. `narrate --source=advice.json --advisor-config=local.json --project=perf` reads saved evidence. `investigate --catalog=perf/scenarios.toml --max-experiments=4 --budget-seconds=300` runs declared cases. JSON and Markdown reports preserve limits and availability.

## Interfaces

In VS Code, the investigation panel includes **Investigate selected**, **Explain with configured model**, **Model settings**, a searchable tool catalogue, and CI coverage proposals. Configure `perfchecker.advisorModel`, `advisorEndpoint` and `advisorProtocol`, or use `advisorConfig` for a custom Julia provider. `advisorInvestigates` is off by default. Count and duration budgets are separate settings. History keeps generated prose beside deterministic evidence; Problems and source actions derive from analyzer findings.

The Oxygen scenario studio takes `advisor=config` when started. Its browser cannot change the server-side provider or credentials. It exposes launch, cancellation, history, explanation and investigation controls. The generated Pluto investigation notebook provides explicit buttons, model configuration and saved-advice paths, and count/time limits. Opening a notebook or changing a selection never starts a model request. REPL and Documenter use `investigation_view` on the same reports.

CPU stacks and allocation sites are retained in scenario bundles. VS Code provides a filterable stack explorer; HTML/Pluto reports expose the profile evidence. `write_speedscope_profile` and `write_folded_profile` export collected stacks for external viewers. Profile weights are not treated as independent timing samples.

## Evaluate usefulness before increasing autonomy

The ordinary cases in `examples/advisor-corpus` inject an allocation, dynamic dispatch, an incorrect oracle and unavailability, with a healthy control. `expected.json` records independent labels for each selected analyzer. Run `evaluate.jl` in a prepared environment, optionally passing a provider configuration. The report measures evidence selection, elapsed time, omissions and unsupported rule selections. `evaluate_advisors(...; include_investigator=true)` additionally accepts an explicit catalogue per case and reports performed experiments and time to first supported advice.

Evaluation of a writer starts with already recorded advice; its timing is formatting/request cost, not time to discover the defect. Investigator timing includes measurements. Review prose separately for fidelity, understandable explanation and actionable verification; automatic evidence-ID validation cannot grade these. Local inference has no API fee, but energy and machine costs remain unmeasured. Results from one small model and host do not establish general model accuracy or a performance ranking.

Primary interfaces: [llama.cpp](https://github.com/ggml-org/llama.cpp), [Ollama API](https://docs.ollama.com/api/chat), [Qwen3 GGUF models](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF).
