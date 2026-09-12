# Configure an advisor and manage optional models

The deterministic advisor requires no model. The optional advisor panel lets
you choose Ollama, a local or remote Chat Completions endpoint, or one MCP HTTP
advice tool. It opens without contacting the provider or downloading weights.

## VS Code

Run **PerfChecker: Configure advisor and manage models**, use the settings icon
in **Scenarios & advice**, or choose **Model settings** in an investigation.

1. Select a provider and enter its endpoint. Remote connections require an
   explicit HTTPS opt-in. Enter only the *name* of a credential environment
   variable; never paste a token into the panel.
2. Choose **Tester la connexion / découvrir**. This reads the available models
   or MCP tools, without sending project evidence or generating advice.
3. Choose **Utiliser** beside a model/tool. For MCP, check the prompt argument
   and any other required arguments shown in its schema. The selection remains
   explicit; a tool name is not a guarantee that the server contains an assistant.
4. Customize the instructions and save. The panel updates the configured advisor
   file, or creates `perf/advisor.json`, then selects it in workspace settings.
   Existing custom provider fields are retained through the common validator.
5. Diagnose a scenario and choose **Explain with configured model**. The displayed
   saved evidence is used directly; otherwise the extension offers its history.

Choose **Conseils déterministes uniquement** and save to disable optional advice.
This does not remove model files. Choosing experiments is separately enabled
and bounded by count and duration. MCP requires structured responses for this
mode; free text is displayed as unverified advice and never executed.

## Optional local model files

Install/start Ollama through its [official guide](https://docs.ollama.com/quickstart).
The panel connects to that existing service; it does not install system software.
With a **local Ollama** endpoint selected, the panel provides:

- Model inventory with sizes reported by the server.
- Explicit download of an exact model name, with a confirmation step.
- Unloading from memory while retaining the files.
- Deletion from the shared server after confirmation.
- Cancellation and a configurable deadline, including worker startup.

Size before download and free disk space can be unknown. Reported installed
sizes include shared layers and must not be summed as unique disk usage.
Cancellation stops the local worker; the server may retain partial downloads.
Refresh its inventory before deciding whether another operation is needed.
Deleting a model affects every project using that Ollama installation. Management
is disabled for remote servers and other providers.

## Web studio and Pluto

The web studio links to the **same panel**. Saving applies to that studio and
persists under its reports directory in `advisor-settings.json`. Investigation
and model-management jobs cannot run concurrently in that studio. Requests use
the studio session token and are restricted to the existing loopback service.

Generated Pluto notebooks have an **Optional advisor setup** section with
provider, prompt, MCP fields, discovery, save and model lifecycle controls.
Only the action button launches a request; changing fields never does. The
confirmation checkbox is required for model mutations and overwriting an
existing configuration. Refresh displays the returned models/tool schemas;
copy the selected identifier into the configuration before saving. The advisor
file is then used by the existing narration/investigation controls.

The REPL and CLI consume the same backend, for example:

After saving `perf/advisor.json` through the panel, the equivalent Julia calls are:

```julia
using PerfChecker
config = load_advisor_config("perf/advisor.json")
result = advisor_setup(config) # inventory only; no generation/evidence
job = launch_advisor_setup(config; action=:models)
investigation_status(job)
cancel!(job)
```

The `advisor-setup` CLI takes `--source=request.json` containing `config`,
`action`, optional `model`, and `confirmed` for mutations. Its JSON output has
explicit availability, `evidence_sent=false`, and `generation_tested=false`.
The connection check cannot establish model quality, and some otherwise
compatible model endpoints do not expose a model-list route.

See [MCP advice](mcp-advisor.md) for protocol limits and [advisors](advisors.md)
for deterministic fallback and evidence verification.
