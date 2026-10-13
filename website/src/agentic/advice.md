# Advice and reviewed implementation

Start with deterministic findings from saved evidence, then discuss possible changes. PerfChecker needs no model to derive advice, and an advice reply never approves source edits.

## Start with saved evidence

```@raw html
<p>Download the JET walkthrough's <a href="../examples/jet-dispatch/summary.json" download="summary.json">recorded summary</a> as <code>summary.json</code>. The <a href="../examples/jet-dispatch/run.jl" download="run.jl">recording code</a> names its scenario <code>net-revenue</code>; the portable summary retains its two implementations but omits that scenario field and the diagnosis envelope. Restore only those fields, then derive advice through the public API:</p>
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
[separate before/after measurements](../tools/jet.md#Follow-a-finding-through-a-change) answer
that different question.

```@raw html
<a id="Local-default-and-interchangeable-providers"></a>
```


## Prepare, review and recover

To ask a tool to prepare a change, select a trusted implementation tool that accepts both a prompt and an isolated checkout path. The tool must be able to access that checkout and honor its scope. HTTP does not mount or upload local files. Configure different argument names for the prompt and checkout path.

1. Review the advice. Choose the exact change and correctness tests; save editor buffers.
2. Checkpoint the on-disk original and create an isolated checkout **before** invoking the tool. Generated changes can be wrong; keep rollback available.
3. Authorize edits only in that checkout. Review its actual diff and run the agreed oracle; a completion message is not test evidence.
4. Apply only reviewed changes. Keep the checkpoint until empty inputs, boundary values and supported types pass, and compatible before/after measurements answer the performance question.
5. If the result is unsuitable, inspect intervening drift before restoring the checkpoint.

Outside the editor, you own that checkpoint, isolated workspace, diff review, application and recovery. This call invokes the already configured tool; it does not create a backup or apply a patch:

```julia
using PerfChecker, HTTP
# isolated_checkout already exists and the original has been checkpointed.
# Use your server's actual implementation tool and argument schema.
implementation_config = AdvisorConfig(protocol=:mcp_http,
    endpoint="http://127.0.0.1:8765/mcp", mcp_tool="prepare_export_patch",
    mcp_prompt_argument="instruction", mcp_response=:text)
messages = [Dict("role"=>"user", "content"=>
    "Prepare only the reviewed buffer-reuse change. Preserve the public API; test empty inputs, boundary values and supported numeric types. Leave the diff for review; do not publish.")]
proposal = implement_advice(messages; config=implementation_config,
    workspace=isolated_checkout, workspace_argument="checkout")
display(proposal["status"])
display(proposal["implementation_status"])
```

The implementation status is `requires_diff_review`, including after a provider failure: the tool may already have edited files. Read the execution status and on-disk diff separately. There is no provider-neutral model response recorded for this request.

::: details Editor checkpoint and rollback

In [VS Code](../interfaces/vscode.md), choose **Prepare implementation from reviewed advice**. Read the warning, then choose **I reviewed the advice · Prepare implementation**. The extension creates a Git checkpoint and an isolated temporary checkout. Review the diff before choosing **Apply reviewed implementation changes**; use **Restore implementation checkpoint** for recovery.

Applying keeps HEAD and the real index unchanged. The checkpoint covers tracked modifications and non-ignored untracked files, but excludes unsaved buffers.

Git and an existing HEAD are required. Conflicts, submodules, escaping/absolute symlinks, clean/smudge filters (including LFS), working-tree encoding and ident expansion are refused. Ordinary CRLF conversion is supported.

Dedicated `refs/perfchecker/checkpoints/<id>` and proposal refs retain recovery independently of the temporary workspace and editor storage. Starting another conversation or changing evidence does not discard recovery. **Discard proposal** clears the active pointer; the refs remain available.

Apply and restore refuse when the checkpointed repository tree has drifted, including outside the proposal.

Cancellation waits for owned local-connector cleanup. If cleanup fails, the copy and recovery state remain; new requests are blocked until **Retry Disconnect** succeeds. Remote HTTP interruption does not establish server shutdown. Cancellation does not mean no edits occurred.

:::

```@raw html
<a id="Bounded-investigations-and-provider-evaluation"></a>
```

::: details Bounded investigations and provider evaluation

## Bounded investigations

```julia
using PerfChecker
catalog = load_scenario_catalog("perf/scenarios.toml")
result = investigate(catalog; project = "perf",
    tools = [:jet, :alloccheck], samples = 10, max_experiments = 4,
    budget_seconds = 300, timeout = 120, reports = "results/investigation")
```

This version uses deterministic ordering and needs no provider. To explicitly let your MCP tool select only declared experiments, construct a separate **structured** configuration (chat text configuration cannot select experiments):

```julia
# Replace endpoint/tool/arguments with your server's actual structured tool schema.
structured_config = AdvisorConfig(protocol=:mcp_http,
    endpoint="http://127.0.0.1:8765/mcp", mcp_tool="select_experiment",
    mcp_response=:structured)
# Pass advisor=structured_config to investigate only when intentionally enabling it.
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

```@raw html
<a id="Evaluate-usefulness-before-adding-autonomy"></a>
```

## Evaluate provider usefulness

`examples/advisor-corpus` contains ordinary cases: an injected allocation, dynamic dispatch, an incorrect oracle and unavailability, with a healthy control. `expected.json` records independent labels.

Run `evaluate.jl` in a prepared environment, optionally with a provider config. The report covers evidence selection, elapsed time, omissions and unsupported rule selections.

- Writer evaluation starts from recorded advice; its timing is formatting/request cost, not discovery time.
- Investigator timing includes measurements.
- Automatic ID validation cannot grade prose fidelity or usefulness.
- Local inference has no API fee, but energy and machine costs are unmeasured.

Results from one small model and host do not establish general model accuracy.

MCP structured mode accepts cards with supplied evidence IDs and an allowed `experiment_id` or `stop`. Unknown/duplicate evidence IDs and undeclared experiments are rejected. Text chat cannot select experiments. Source editing remains a separate explicit request.

Existing specialized models can use the same [provider setup](providers.md). Evaluate on saved cases with known outcomes and healthy controls; valid JSON does not establish faithful reasoning. Record base model, adapter/dataset hashes and inference settings; keep related revisions in one dataset partition and reserve unseen cases. PerfChecker does not train adapters or automatically download weights.

:::

::: details Optional authenticated connector receipt

One existing authenticated Julia-source proof used the optional Codex connector, Julia 1.13.1 and Core 1.0.1 source tree `4fbc3c25543aa4f9b1154c227e5432f0cd62df91`, before General registration. It exercised two advice turns, an isolated source-only proposal, correctness/allocation probes, reviewed apply, exact restore, cancellation and disconnect. Empty Float64 input, signed values and a 1,000-element Float64 vector returned `0.0`, `14.0` and `333833500.0`. The warmed `@allocated` probe recorded **8,072 B before and 0 B after** for that fixture. It did not measure a timing gain or establish equivalence for all element types.

The authenticated tests exercised Codex 0.159.2 for the executable/lifecycle contract and 0.162.0-alpha.2 for multi-turn advice and reviewed implementation. These are separate from controlled HTTP/editor demonstration responses. They do not qualify every MCP service, model, client or later connector version. Use your actual tool response and test output when following the provider-neutral workflow above.

:::
