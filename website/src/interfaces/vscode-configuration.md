# VS Code configuration

Configure PerfChecker for the package folder you are measuring. In a multi-root workspace, use folder settings so one package cannot inherit another package's environment by accident.

## Choose Julia environments

PerfChecker resolves `runnerProject` relative to the selected package folder. Its default is `perf`. If that default is unchanged and `perf/Project.toml` is absent, `perf/controller` is used when its project exists. An explicit setting always wins. `scenarioProject` follows the same default fallback for shared scenario workers.

The controller needs PerfChecker and the interface/provider packages used by the request. The target environment needs the measured package, its dependencies and any analyzer selected for target workers. Existing TestItems need TestItemRunner **1.3.2 or newer** and their test dependencies in the selected runner environment.

### Prepare a controller

Run these Julia commands **from the measured package's root**, where its
`Project.toml` is located. Choose `core_version` from the
[extension compatibility table](vscode.md#Version-compatibility):

```julia
import Pkg
core_version = "1.0.1" # Use "1.1.0" with extension 1.0.2.
Pkg.activate("perf/controller")
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = core_version))
Pkg.add(["BenchmarkTools", "TestItems", "TestItemRunner", "HTTP"])
Pkg.develop(path = ".")
Pkg.status()
```

This creates a separate controller environment, installs registered PerfChecker
V1, a benchmark collector and TestItems support, and makes your local package importable there.
`HTTP` is needed only for an MCP advisor; omit it if you do not use one. Add your
package's other test dependencies deliberately if its items import them.
`Pkg.develop` points at the package root rather than copying or publishing it.

### Guided setup from Studio

Guided setup is available in extension **1.0.1**. Install it from the
[Marketplace or release VSIX](vscode.md#Install-and-prepare). If you still use
extension 1.0.0, use the manual controller recipe above or upgrade.

With PerfChecker for VS Code 1.0.1 or newer, choose **Set up workspace and create
suite** in an unconfigured Studio, or **PerfChecker: Create feature suite**.
The extension first checks the selected controller and then offers:

| Choice | Action |
| --- | --- |
| **Create controller environment** | Review the required Core version, then confirm **Install controller** to install it with BenchmarkTools, Chairmarks and TestItemRunner into `perf/controller` |
| **Use an existing controller** | Choose a folder containing `Project.toml`; verify that Core meets the installed extension's requirement without installing packages |
| **Read the setup guide** | Open this documentation for manual preparation |

Successful verification sets `runnerProject` for that workspace folder.
`scenarioProject` follows it only when you have not configured that setting
already. A cancelled or failed setup does not switch the controller setting.
Inspect the selected target environment and add your measured package's test
dependencies when required; preparing collectors alone does not make every
package's tests importable.

Opening Studio remains a configuration action. Downloads require the explicit
installation confirmation. Setup uses `juliaExecutable`; cancellation requests
worker cleanup, and **PerfChecker: Show worker output** records dependency
errors.


For an MCP connection, add `HTTP` explicitly to this controller,
then follow [MCP configuration](../mcp-advisor.md). The setup installs the listed
measurement packages. The separate Pluto environment uses the qualified Pluto
release's own HTTP dependency range.

The notebook setup installs and checks **PerfCheckerPluto 1.0.1
or newer within the 1.x series**, separately from the controller. An existing
Pluto project using companion 1.0.0 requires an explicit upgrade confirmation;
the compatibility check does not update it silently. Declining keeps that
environment unchanged. Its Core version must meet the
[extension compatibility table](vscode.md#Version-compatibility). The guided
setup installs the companion from the independent root `v1.0.1` tag while its
separate General registration is pending.
See the
[separate Pluto installation recipe](../guide/installation.md#Prepare-the-integrated-Pluto-candidate)
and [existing notebook migration](vscode-workflows.md#Use-the-corrected-suite-plot-renderer).


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
| `plutoProject` | `perf/pluto` | Separate Pluto project for the notebook integration |

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

Use **PerfChecker: Configure MCP connection and models**, or **Configure MCP connection** in chat. For a saved HTTP provider, choose **Advisor provided by an MCP HTTP tool**, enter its address and explicit revision, then **Test connection / discover**. Inspect **Required arguments and tool schema**, select **Use**, check the prompt and other arguments, then **Save configuration**. Chat requires `mcp_http` and `text` response mode. MCP defines no standard advice-tool name. Discovery sends no saved evidence and does not test answer generation.

Extension **1.0.1** also provides **Connect local MCP server** in chat and **PerfChecker: Connect local MCP server (stdio)**. This opens **Local MCP server · stdio** with an absolute native executable, a JSON argument array and an absolute working directory. Discover its paginated inventory, choose advice with **Use** and optionally a separate tool with **Use for implementation**, then **Connect for this editor session**. Follow the [complete stdio recipe](../mcp-advisor.md#Connect-a-local-stdio-server) and [platform qualification](vscode.md#Qualification-and-reporting-a-problem); extension 1.0.0 did not include this connector.

MCP is the tool protocol; a server is not necessarily an agent or model. The chosen tool must accept the prompt and return advice. Both connection types require `HTTP` in the selected Julia controller: the stdio connector adapts a temporary HTTP endpoint. **Local** means the extension host, including a Remote SSH host or container; executable paths and checkout access must work there. Interactive OAuth login is unavailable. An authenticated Codex CLI remains an [optional connector example](../mcp-advisor.md#Connect-an-authenticated-Codex-CLI), with its own executable requirements.

| Setting | Default | Meaning |
| --- | --- | --- |
| `advisorEnabled` | `true` | Permits explicitly requested optional advice |
| `codexExecutable` | `codex` | Authenticated native Codex executable for the explicit local connection; Windows requires `.exe` |
| `advisorConfig` | empty | JSON config path; takes precedence over provider settings |
| `advisorProtocol` | `chat_completions` | Provider protocol; chat requires `mcp_http` |
| `advisorEndpoint` | local Chat Completions URL | Existing model or MCP endpoint |
| `advisorModel` | `local` | Chat Completions/Ollama model identifier; ignored by MCP HTTP |
| `advisorInstructions` | empty | Prompt customization, up to 5,000 characters |
| `advisorMcpTool` | empty | Explicit advice tool |
| `advisorMcpPromptArgument` | `prompt` | Argument receiving instructions and bounded context |
| `advisorMcpArguments` | `{}` | Required extra arguments; no prompt override/secrets |
| `advisorMcpResponse` | `text` | Unverified text, or structured evidence references |
| `advisorMcpVersion` | `2026-07-28` | Explicit supported MCP protocol revision |
| `advisorMcpStdioCommand` | empty | Optional absolute executable used to prefill the stdio form; never auto-starts |
| `advisorMcpStdioArguments` | `[]` | Initial executable argument array; no secrets or shell expressions |
| `advisorMcpStdioDirectory` | empty | Initial absolute working directory; empty prefills the selected workspace |
| `advisorAllowRemote` | `false` | Allows transmission to a remote HTTPS endpoint |
| `advisorKeyEnvironment` | empty | Name of the environment variable containing the token |
| `advisorTimeout` | `90` | Total provider-worker deadline in seconds |
| `advisorInvestigates` | `false` | Structured model selection of declared experiments |

The MCP server selects its own model and output limits. If its tool schema accepts model or limit options, put those named arguments in `advisorMcpArguments`; the generic provider's `model` and `max_tokens` fields are not sent by the MCP transport.

Disabling `advisorEnabled` keeps deterministic advice usable and retains already installed model files. An explicitly connected local provider takes precedence for that session; **Disconnect local MCP server** or **Disconnect Codex** resumes the saved configuration and its enabled/disabled state. Live stdio selections and generated endpoint/credential are not saved. Reconnect explicitly after editor restart, cancellation, timeout or server exit. The stdio child inherits the extension host environment except private connector tokens; other environment variables remain available to it. Never put secrets in settings or argument fields. [MCP configuration](../mcp-advisor.md#Configure-the-advice-tool) includes complete HTTP JSON and VS Code examples.

## Implementation settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `advisorImplementationMcpTool` | empty | Separate tool authorized after reviewed advice and confirmation |
| `advisorImplementationMcpPromptArgument` | `prompt` | Implementation prompt argument |
| `advisorImplementationMcpWorkspaceArgument` | `workspace` | Isolated checkout argument |
| `advisorImplementationMcpArguments` | unset | Independent implementation arguments; when unset, falls back to advice arguments |

Implementation reuses the MCP endpoint, revision and authentication. Its tool, prompt/workspace names and extra arguments are selected independently; an advice reply cannot select them automatically. For saved HTTP settings, an unset `advisorImplementationMcpArguments` retains the advice arguments; set `{}` for no extra implementation arguments. Prompt and workspace names must differ, and extra arguments cannot override either reserved field. In stdio mode, use the separate implementation fields in the connection panel; they last only for that session.

A configured implementation tool must access and honor the supplied isolated checkout. The optional local Codex connector supplies its own tool names in memory. A remote HTTPS endpoint has no automatic access to your local filesystem. Use a trusted local tool, or a deliberately configured shared filesystem/bridge with its own confinement. MCP does not provide an operating-system sandbox.

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
| Saved advisor config seems inactive | Disconnect the temporary stdio or Codex connection to resume your saved provider |
| Local MCP executable or checkout is missing | Check absolute paths on the extension host, including Remote SSH/container paths |
| Local MCP server exited or timed out | Wait for cleanup, inspect its prerequisites, then explicitly reconnect |
| Pluto setup cannot resolve HTTP | Use the separate `plutoProject`; qualified Pluto 1.0.4 uses HTTP 1.x, while the MCP controller uses HTTP 2.x |
| Existing Pluto/controller project has an incompatible Core or Pluto companion | Explicitly upgrade Core to the version required by the installed extension, and the companion to tag `v1.0.1`; existing suite notebook source also needs the migration above |
| Notebook session unavailable | Inspect **PerfChecker Pluto** output and [session controls](vscode-workflows.md#Manage-the-session-and-saved-source); extension 1.0.0 needs an installed Julia kernel |

Worker logs are available through **PerfChecker: Show worker output**. Keep tokens out of configuration files and troubleshooting reports.
