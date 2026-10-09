# VS Code configuration

Configure PerfChecker for the package folder you are measuring. In a multi-root workspace, use folder settings so one package cannot inherit another package's environment by accident.

## Choose Julia environments

PerfChecker resolves `runnerProject` relative to the selected package folder. Its default is `perf`. If that default is unchanged and `perf/Project.toml` is absent, `perf/controller` is used when its project exists. An explicit setting always wins. `scenarioProject` follows the same default fallback for shared scenario workers.

The controller needs PerfChecker and the interface/provider packages used by the request. The target environment needs the measured package, its dependencies and any analyzer selected for target workers. Existing TestItems need TestItemRunner **1.3.2 or newer** and their test dependencies in the selected runner environment.

### Prepare a controller

Run these Julia commands **from the measured package's root**, where its
`Project.toml` is located:

```julia
import Pkg
Pkg.activate("perf/controller")
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1"))
Pkg.add(["BenchmarkTools", "TestItems", "TestItemRunner", "HTTP"])
Pkg.develop(path = ".")
Pkg.status()
```

This creates a separate controller environment, installs registered PerfChecker
V1, a benchmark collector and TestItems support, and makes your local package importable there.
`HTTP` is needed only for an MCP advisor; omit it if you do not use one. Add your
package's other test dependencies deliberately if its items import them.
`Pkg.develop` points at the package root rather than copying or publishing it.

Open **Preferences: Open Workspace Settings (JSON)**, or the selected folder's
settings in a multi-root workspace, and set the example below in
`.vscode/settings.json`. Set **Runner Project** to `perf/controller` explicitly.
Leave **Scenario Project** as `.` only if the package environment contains the
dependencies and analyzers needed by those scenario workers.

Example folder settings, with an existing controller and target project:

```json
{
  "perfchecker.juliaExecutable": "julia",
  "perfchecker.runnerProject": "perf/controller",
  "perfchecker.scenarioProject": ".",
  "perfchecker.suite": "perf/suite.jl",
  "perfchecker.scenarioCatalog": "perf/scenarios.toml",
  "perfchecker.scenarioSamples": 10,
  "perfchecker.scenarioThreads": 1,
  "perfchecker.analysisTools": ["jet", "latency"]
}
```

An absolute environment path is also accepted. `juliaExecutable` is an executable path or launcher, not a shell command with additional arguments. PerfChecker supplies startup, history, project and worker arguments itself. No environment is installed merely by opening Studio.

Run **PerfChecker: Open Julia terminal** and inspect `Base.active_project()` and
`Pkg.status("PerfChecker")` to check the controller selection. This terminal is
an interactive inspection surface; successful imports there are a useful setup
check, not a performance result.

## Core and suite settings

All setting names below have the prefix `perfchecker.`.

| Setting | Default | Meaning |
| --- | --- | --- |
| `juliaExecutable` | `julia` | Julia executable or juliaup launcher |
| `runnerProject` | `perf` | Controller project; default-only fallback to `perf/controller` |
| `suite` | `perf/suite.jl` | Julia suite file relative to the selected folder |
| `factory` | `build_suite` | Zero-argument function constructing the suite |
| `profile` | `quick` | Suite execution profile |
| `reports` | `perf/results/vscode` | Saved suite reports |
| `uiConfiguration` | `perf/perfchecker-ui.json` | Shared visual suite selection |
| `gitTargets` | `[]` | Named branches, tags or commits measured alongside other targets |
| `comparisonPolicies` | `[]` | Exact or grouped baseline policies |

The visual suite editor manages the richer selection. See [comparison configuration](../reference/comparisons.md) for policy fields and aggregation semantics.

## Existing TestItems

| Setting | Default | Meaning |
| --- | --- | --- |
| `testItemTags` | `[]` | Match any selected tag; empty selects all except `test_only` |
| `testItemExcludeTags` | `[]` | Additional tags excluded from performance runs |
| `testItemSamples` | `1` | Explicit repetitions, each in a fresh process |

There is no automatic warmup of a native test item. The repetitions affect both scope and cost. Read [TestItems and tags](../test-items.md) before reusing functional tests as performance workloads.

## Shared scenarios and analyzers

| Setting | Default | Meaning |
| --- | --- | --- |
| `scenarioCatalog` | `perf/scenarios.toml` | Explicit scenario catalogue |
| `scenarioProject` | `perf` | Worker environment for measurements and analyzers |
| `scenarioSamples` | `10` | Fresh-state samples per scenario and collector |
| `scenarioThreads` | `1` | Julia threads per scenario worker |
| `analysisTools` | `["jet", "alloccheck", "latency"]` | Default requested analyzers |
| `analysisTimeout` | `120` | Worker deadline in seconds |
| `investigationReports` | `perf/results/investigations` | Saved investigation evidence |
| `investigationMaxExperiments` | `4` | Maximum declared experiments per investigation |
| `investigationBudgetSeconds` | `300` | Total investigation deadline, including requests/startup |

Unavailable is separate from passing or failing. Remove a tool you do not need, or explicitly install it in the prepared worker environment. PerfChecker will not silently install it for you.

## Advice and MCP settings

For an installed authenticated Codex CLI, use **PerfChecker: Connect authenticated Codex CLI** or **Connect Codex CLI** in Chat. The [named-agent recipe](../mcp-advisor.md#Connect-an-authenticated-Codex-CLI) documents supported executables, sandbox boundaries and existing-account usage. This session connection supplies the advice and implementation tools without overwriting your saved settings or JSON configuration.

For an MCP server with an advice tool, use **PerfChecker: Configure advisor and manage models** to check the connection, discover tools and save configuration. For chat, select `mcp_http`, a tool that accepts an advice request, and `text` response mode. A tool named `ask` is only an example; MCP defines no standard chat-tool name.

Local HTTP endpoints must use `localhost`, `127.0.0.1` or `[::1]`. Other hosts, including private LAN addresses, require HTTPS and `advisorAllowRemote = true` (or `allow_remote = true` in the advisor JSON file). In Remote SSH or a development container, these addresses and executable paths belong to the VS Code extension host. See [MCP configuration fields](../mcp-advisor.md#Understand-configuration-fields) before choosing the endpoint.

| Setting | Default | Meaning |
| --- | --- | --- |
| `advisorEnabled` | `true` | Permits explicitly requested optional advice |
| `codexExecutable` | `codex` | Authenticated native Codex executable for the explicit local connection; Windows requires `.exe` |
| `advisorConfig` | empty | JSON config path; takes precedence over provider settings |
| `advisorProtocol` | `chat_completions` | Provider protocol; chat requires `mcp_http` |
| `advisorEndpoint` | local Chat Completions URL | Existing model or MCP endpoint |
| `advisorModel` | `local` | Provider model identifier; not an installation |
| `advisorInstructions` | empty | Prompt customization, up to 5,000 characters |
| `advisorMcpTool` | empty | Explicit advice tool |
| `advisorMcpPromptArgument` | `prompt` | Argument receiving instructions and bounded context |
| `advisorMcpArguments` | `{}` | Required extra arguments; no prompt override/secrets |
| `advisorMcpResponse` | `text` | Unverified text, or structured evidence references |
| `advisorMcpVersion` | `2026-07-28` | Explicit supported MCP protocol revision |
| `advisorAllowRemote` | `false` | Allows transmission to a remote HTTPS endpoint |
| `advisorKeyEnvironment` | empty | Name of the environment variable containing the token |
| `advisorTimeout` | `90` | Total provider-worker deadline in seconds |
| `advisorInvestigates` | `false` | Structured model selection of declared experiments |

Disabling `advisorEnabled` keeps deterministic advice usable and retains already installed model files. An explicitly connected Codex chat remains authorized for that session; choose **Disconnect Codex** to stop using it and resume the saved disabled provider state. [MCP configuration](../mcp-advisor.md#Configure-the-advice-tool) includes complete JSON and VS Code examples.

## Implementation settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `advisorImplementationMcpTool` | empty | Separate tool authorized after reviewed advice and confirmation |
| `advisorImplementationMcpPromptArgument` | `prompt` | Implementation prompt argument |
| `advisorImplementationMcpWorkspaceArgument` | `workspace` | Isolated checkout argument |

Implementation reuses the MCP endpoint, revision, authentication and extra arguments. Its tool and prompt/workspace names are explicit extension settings; an advice reply cannot select them automatically. Prompt and workspace names must differ. Extra arguments cannot override either reserved field.

The explicit local Codex connection supplies these implementation tool names in memory. External servers must access the isolated checkout. A remote HTTPS endpoint has no automatic access to your local filesystem. Use a trusted local tool, or a deliberately configured shared filesystem/bridge with its own confinement. MCP does not provide an operating-system sandbox.

## Troubleshooting

| Problem | Resolution |
| --- | --- |
| Project does not exist | Check the selected folder and `Project.toml`; use an absolute path |
| Suite factory missing | Verify the configured suite file and function name |
| Tool package absent | Install deliberately into the environment selected for that worker |
| Chat asks for MCP text mode | Update the JSON config if `advisorConfig` is set; it overrides provider settings |
| Credentials absent | Start VS Code with the named environment variable available to its extension host |
| Probe passes, chat fails | Check required tool arguments and that the selected tool returns advice |
| Agent cannot see the code | Check access to the supplied isolated checkout, not the original root |
| Codex connection refused | Check native executable, required flags, existing login and absence of project `.codex` configuration |
| Saved advisor config seems inactive | Disconnect the temporary Codex connection to resume your saved provider |
| Notebook cannot execute | Select an installed Julia kernel; see [notebook prerequisites](vscode-workflows.md#Investigation-notebooks) |

Worker logs are available through **PerfChecker: Show worker output**. Keep tokens out of configuration files and troubleshooting reports.
