```@raw html
<a id="Send-PerfChecker-evidence-to-an-MCP-assistant"></a>
```

# MCP advice and implementation

Connect PerfChecker to an advice tool on your MCP server. PerfChecker is the **MCP client**: it discovers tools and calls the one you select. Discuss saved evidence, review the answer, then explicitly request implementation through a separately configured tool. The server may use an agent or another service to produce its answer. Deterministic findings remain available without a connection.

[MCP](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) is a standard protocol for exposing tools. A tool server does not necessarily contain a language model or an agent. For this workflow, choose a tool that accepts the supplied prompt and returns advice. Use an independently managed **Streamable HTTP** server, or explicitly launch a native **stdio** server from VS Code. The optional local Codex connector is one example, not a requirement for chat or implementation.

The local stdio connector and connection-panel labels below belong to the extension **1.0.1 development candidate**. They are not part of the public 1.0.0 extension. The Julia client still uses HTTP; the extension adapts its session-local HTTP connection to the selected stdio server.

## Choose a connection

| What you already have | Use | First action |
| --- | --- | --- |
| A compatible HTTP MCP server with an advice tool | Saved MCP configuration | Start your server, then discover and select its advice tool |
| A native MCP stdio server executable with an advice tool | Temporary local stdio connection | Choose **Connect local MCP server**, discover its tools, then explicitly connect |
| Only a model's Chat Completions URL | The provider interface for evidence narration | Use [Provider setup](advisor-ui.md); this URL is not an MCP server |
| No advice service or server | Deterministic findings and manual changes | Measure and diagnose, then inspect the saved advice |
| An authenticated native Codex CLI | Optional temporary local connector | Use the **Codex CLI (optional)** example below |

For each supported MCP connection, the controller must contain PerfChecker V1 and `HTTP`.
[Prepare the controller](interfaces/vscode-configuration.md#Prepare-a-controller)
first. Advice and implementation are separate actions: receiving an answer never
approves a source edit.

### Check the controller transport

From your package root, install the transport in the project selected as
**Runner Project**, not only in the package or scenario worker:

```julia
import Pkg
Pkg.activate("perf/controller") # Use your actual selected controller path.
Pkg.add("HTTP")
using PerfChecker, HTTP
Base.get_extension(PerfChecker, :HTTPAdvisorExt) !== nothing
```

The final expression must return `true`. For an existing controller, keep its
PerfChecker version and choose the `HTTP` release allowed by its compatibility
bounds. Loading `HTTP` in a different Julia project cannot enable the transport
in the advisor worker. The measured package may keep a separate Scenario
Project with its own collector dependencies.

If the connection reports **advisor protocol extension is unavailable**, check
the resolved Runner Project, install `HTTP` there, and retry the connection.
An agent login or API key does not install this Julia dependency. Once connected,
select a completed saved report in chat and check the displayed attachment
before asking about its measurements; a conversation without an attachment
cannot explain that report's results.

For interactive experiments, the [integrated Pluto candidate](interfaces/vscode-workflows.md#Pluto-notebooks-in-VS-Code)
keeps notebook execution in its separate project. Launch the chosen checks,
inspect their correctness and save completed reports before selecting that saved
evidence in Advisor chat. Follow-up questions and implementation review remain
explicit chat actions; reopening a notebook does not request an agent turn.

```@raw html
<a id="Configure-the-assistant"></a>
```

## Configure the advice tool

After preparing the controller, open **PerfChecker: Configure MCP connection and models** in VS Code, or **Configure MCP connection** in chat. The following steps configure a saved HTTP provider; use [Connect a local stdio server](#Connect-a-local-stdio-server) for an explicitly launched process.

1. In **Mode**, select **Advisor provided by an MCP HTTP tool**, enter your **Server address** and supported **MCP version** (`2026-07-28` or `2025-11-25`).
2. Choose **Test connection / discover**. This reads the tool catalogue without sending saved evidence or requesting advice.
3. Inspect the chosen advice tool's schema and choose **Use**. Set its exact prompt argument and required extra arguments.
4. Use **Text advice · no automatic experiments or Apply** response mode for chat: the tool must accept the configured string prompt and return nonempty text. Choose **Save configuration**. Check `perfchecker.advisorConfig`: a selected JSON file takes precedence over provider settings.
5. Open **PerfChecker: Chat with performance advisor**, deliberately attach a completed report, and ask one question. A successful catalogue probe proves neither answer generation nor the quality of an answer.

In the discovered inventory, select **Use** beside the advice tool your server actually provides.
Inspect its input schema: replace the prompt argument if it is not `prompt`, and
provide its other required arguments without secrets. Tool names and argument
names are case-sensitive. The screenshot's `ask_perfchecker` is a demonstration
inventory; the illustrative configuration below uses `review_export`. Use
your server's actual name and schema in both the file and extension settings.

The native walkthrough below uses the local protocol fixture `ask_fixture`.
Its prompt field is `question` and its other required argument is the `context`
object. Select your own server's discovered names and required arguments;
these fixture values are not universal MCP defaults.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-19" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="10 · MCP configuration and a follow-up conversation" preload="none" alt="Actual native PerfChecker MCP tool inventory, input schema and Use selection confirmation" caption="Discover the server tool, inspect its real properties and required arguments, then select Use. The actual schema frames are held for reading; this local protocol fixture uses ask_fixture, question and context. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux; connection discovery and selection are distinct from answer generation." />
```

```@raw html
<DocMedia src="/assets/screenshots/vscode-mcp-settings.png" alt="Actual PerfChecker V1 advisor setup webview in Chromium with a demonstration MCP HTTP endpoint, tool inventory and selected advice tool" caption="Use your server's endpoint and exact tool name, then probe and save the configuration. This running webview shows a local demonstration configuration and an example tool inventory; the address is not a service supplied to every user." />
```

The following illustrative schema uses `review_export(question, context)` for advice. These are example names, not MCP defaults or a supplied service. Use them only if your running server exposes this schema; otherwise copy its discovered names. The loopback address refers to that deliberately started local server. A complete `perf/advisor.json` example is:

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
  "instructions": "Explain the evidence and propose checks before changes.",
  "allow_remote": false,
  "api_key_env": ""
}
```

Replace the address, tool and arguments with your server's actual values. Set `perfchecker.advisorConfig` to this file, or leave it empty and use extension settings instead. A selected configuration file takes precedence over provider settings. A temporary optional connector must be disconnected before returning to this saved configuration.

The equivalent essential folder settings are:

```json
{
  "perfchecker.advisorProtocol": "mcp_http",
  "perfchecker.advisorEndpoint": "http://127.0.0.1:8765/mcp",
  "perfchecker.advisorMcpVersion": "2026-07-28",
  "perfchecker.advisorMcpTool": "review_export",
  "perfchecker.advisorMcpPromptArgument": "question",
  "perfchecker.advisorMcpArguments": {"context": {"language": "Julia"}},
  "perfchecker.advisorMcpResponse": "text",
  "perfchecker.advisorInvestigates": false
}
```

## Connect a local stdio server

Start with the [controller transport check](#Check-the-controller-transport), even for stdio. The selected Runner Project needs PerfChecker and `HTTP`; installing an MCP executable does not enable that Julia transport. Use a trusted workspace and finish or cancel the current advisor operation before connecting.

1. In chat, choose **Connect local MCP server**, or run **PerfChecker: Connect local MCP server (stdio)**. The connection panel selects **Local MCP server · stdio** in **Mode**.
2. Enter **Absolute MCP server executable**, **Executable arguments (JSON array)** and **Absolute server working directory**. Choose the explicit **MCP version** your server supports. The executable must be a native executable file; Windows `.cmd` and `.bat` launchers are unsupported. No shell, shell expansion or login command is started. Pass each argument as its own JSON string. Do not enter credentials in either argument field.
3. Choose **Test connection / discover**. This explicitly starts the server and reads `tools/list`, following pagination up to 32 pages. It sends no saved evidence and calls no advice or implementation tool. Open **Required arguments and tool schema** beside the tool you intend to use.
4. Choose **Use** for advice. Check **Selected MCP tool**, **Prompt argument** and **Other tool arguments (JSON)** against its actual schema. The prompt must be a string argument; the tool must return nonempty text. Supply all other required arguments without overriding the prompt field. MCP supplies no universal advice-tool name or model.
5. If you want implementation, choose **Use for implementation** beside a trusted tool. Check **Optional implementation tool**, **Implementation prompt argument**, **Isolated checkout argument** and **Other implementation arguments (JSON)** separately. Prompt and checkout argument names must differ. Each arguments object is limited to 12,000 bytes and must omit its reserved fields. An advice-only tool cannot edit code merely because it appears in this inventory.
6. Choose **Connect for this editor session**. This checks the selected tools and required argument names, without requesting advice. Open chat, deliberately attach completed evidence if relevant, and ask a question. Discovery and connection do not prove that the tool can answer it.

Here, **local** means local to the **VS Code extension host**. In Remote SSH or a development container, executable paths, working directories, environment variables and the isolated implementation checkout belong to that remote host or container. A server running on your desktop does not automatically see those files. Choose an implementation tool that can access and honor the supplied checkout on the extension host.

The server inherits the extension host environment except private PerfChecker connector tokens. Other environment variables and filesystem permissions remain available to the server; choose its executable and environment deliberately. PerfChecker drains server stderr without displaying arbitrary log content. MCP and this connector do not provide an operating-system sandbox or guarantee that an advice tool has no side effects.

The live executable choice, tool selections, loopback endpoint and generated credential are session-only. They are not written to settings or `perf/advisor.json`. Optional `advisorMcpStdioCommand`, `advisorMcpStdioArguments` and `advisorMcpStdioDirectory` settings only prefill the form; opening the panel or restarting the editor does not start a server. A connected local provider takes precedence over saved provider configuration, including a saved disabled state. Disconnect to resume that saved configuration.

Choose **Cancel operation** during setup to stop the owned process. Closing an unconnected discovery panel also stops its discovery server; closing the panel after connecting keeps the session available to chat. Finish or cancel an active request before choosing **Disconnect local MCP server** in chat or the panel, or running **PerfChecker: Disconnect local MCP server**. Cancellation, timeout, EOF or server exit closes the local connection and requires an explicit reconnect. Wait for cleanup; a cleanup failure is reported and can be retried with Disconnect. PerfChecker does not adopt unrelated server processes.

Implementation remains a separate reviewed request. [Save your files, create the Git checkpoint, inspect the collected diff, Apply and Restore](#Switch-from-advice-to-implementation) exactly as for an HTTP tool. Stopping a server cannot undo edits it already made; an interrupted request is not evidence that its checkout is unchanged.

## Understand configuration fields

| JSON field | Contract |
| --- | --- |
| `protocol` | `mcp_http` in the Julia/JSON configuration; VS Code's stdio mode supplies a temporary HTTP adapter |
| `endpoint` | Plain local HTTP(S), or explicitly allowed remote HTTPS; no credentials/query/fragment |
| `mcp_version` | `2026-07-28`, or `2025-11-25` for a legacy server |
| `mcp_tool` | One explicitly selected tool; checked with `tools/list` |
| `mcp_prompt_argument` | String argument receiving instructions and bounded evidence/conversation |
| `mcp_arguments` | Required extra arguments; prompt field is reserved; serialized size at most 12,000 bytes |
| `mcp_response` | `text` for chat/advice; `structured` for evidence references and experiment selection |
| `instructions` | Up to 5,000 characters; fixed response and evidence rules are appended |
| `timeout` | Total isolated-worker deadline, including startup and network exchanges |
| `max_evidence_chars` | Evidence projection limit, 1,000–100,000 characters; default 12,000 |
| `api_key_env` | Environment-variable name for an optional Bearer token |
| `allow_remote` | Explicitly permits transmission to a remote HTTPS endpoint |

Tool names and prompt-argument names are checked before the request. Required extra arguments must be configured. `model` and `max_tokens` configure Chat Completions/Ollama requests and are not sent by the MCP transport. Any model, limits and cost policy belong to the selected server tool. Put any model or limit arguments accepted by the selected tool's schema in `mcp_arguments`.

For remote servers, use HTTPS and set `allow_remote = true`. Put the Bearer token in the named environment variable available to VS Code's extension host, never in the JSON or `mcp_arguments`. OAuth login/refresh is not implemented.

```@raw html
<a id="Prompt-and-results"></a>
```

## Talk to the advisor

Open **PerfChecker: Chat with performance advisor**. Select saved deterministic advice if relevant, ask a question, and read the answer in the full editor tab. Follow-up questions include earlier exchanges as bounded context. Changing the selected evidence starts a conversation for that evidence.

The advice tool receives an instruction to answer in the user's language, distinguish measurements from hypotheses, and provide advice without modifying code or running experiments. This instruction does not enforce the absence of side effects; the selected service must honor the advice-only contract. When no evidence is selected, the tool is told no saved measurements were attached. You can still ask how to configure or use PerfChecker.

For a completed report, the attached advice can include measurement summaries
even when it has no recommendations. This context requires the development
1.0.1 candidate; regenerating advice with registered 1.0.0 does not add it.
Use the [development controller setup](interfaces/vscode-configuration.md#Prepare-a-controller).
Each summary identifies the case and
target, collector, quantity and unit, with the recorded minimum, median and
maximum. Execution status and correctness status remain separate. Correctness
also identifies its scope: the bundle, a matching case and target, or an
unrecorded or ambiguous result. Different comparison variants remain separate.

Read the record meaning beside its count. An operation measurement, a profile
frame and an allocation-profile record describe different observations;
`record_count` is not automatically a number of independent experiment repeats.
Operation totals also retain whether their state was fresh or reused.
PerfChecker builds these summaries from explicitly supplied bundles. Older
advice files can still be attached without summaries; regenerate advice from
the intended saved bundle to discuss its measurements, as in the example below.
The evidence limit can omit summaries. If the request reports **no measurement
summaries were sent in this request**, inspect the attachment and configured
limit before interpreting the answer; that message does not say the saved
report contains no measurements.

Replies are unverified text, separate from deterministic findings. Embedded HTML is displayed as text. Suggested commands are not executed by advice chat. You may implement the suggestions yourself.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-06" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="10 · MCP configuration and a follow-up conversation" preload="none" alt="Native PerfChecker conversation with a saved measured run, two contextual questions and controlled MCP replies" caption="Attach the actual measured run, ask a follow-up and agree on validation before requesting an edit. The recorded report shows 8072 B median over two samples with correctness passed; measured evidence IDs and bounded context were checked. The local MCP protocol fixture supplies controlled replies, with frames held for reading. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux. Source is unchanged during advice; cancellation is outside this passage." />
```

```@raw html
<DocMedia src="/assets/screenshots/vscode-advice-chat.png" alt="Actual PerfChecker V1 Advice webview rendered in Chromium with selected allocation evidence, two user questions, two replies and a follow-up prompt" caption="Use follow-up questions to separate observations from hypotheses and agree on validation before preparing an implementation. The actual V1 webview displays a demonstration conversation and evidence; select the image to read the full exchange." />
```

The public Julia API exposes the same bounded conversation. This complete
request example requires your configured, running MCP server and a completed
bundle; replace the configuration and bundle paths with your saved files:

```julia
using PerfChecker, HTTP
config = load_advisor_config("perf/advisor.json")
bundle = read_run_bundle("perf/results/YOUR-BUNDLE")
saved_advice = advise(bundle)
messages = [Dict("role" => "user", "content" => "How should I verify these allocations?")]
result = chat_advice(messages; config, advice = saved_advice)
display(investigation_view(result))
```

Messages alternate user/assistant and end with a user question: at most **21 messages**, **16,000 characters per message**, **32,000 total**. Replies have at most **16,000 characters**. The core API rejects oversized context; the extension can omit older complete exchanges to fit and reports the omission. The core API does not persist a conversation.

## Switch from advice to implementation

If your server also provides a trusted implementation tool, configure its separate tool, prompt and checkout argument names. Advice-only servers can still support chat; they do not gain implementation capability from this configuration. For example, a server exposing `prepare_export_patch(instruction, checkout, context)` would use:

```json
{
  "perfchecker.advisorImplementationMcpTool": "prepare_export_patch",
  "perfchecker.advisorImplementationMcpPromptArgument": "instruction",
  "perfchecker.advisorImplementationMcpWorkspaceArgument": "checkout"
}
```

These names are illustrative too. Select a tool that can inspect, edit and test the supplied isolated checkout and actually honors that path. Implementation reuses the advice connection, revision, credentials and additional arguments, then substitutes the explicitly configured tool and prompt name. The prompt/workspace argument names must differ; extra arguments cannot override either. In this example, both tool schemas must accept the configured `context` object. Check that shared extra arguments are valid for the implementation tool too.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-07" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="11 · A checkpoint and an isolated implementation" preload="none" alt="Actual native PerfChecker preparation action, warning and recovery checkpoint prefix" caption="Review the warning, save editor buffers and explicitly prepare an isolated proposal. The close view preserves the real Prepare implementation button and checkpoint prefix; the full reference continues outside the portrait frame and remains available in the editor. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

The extension's workflow is:

1. Get an advice reply and review the proposed change and validation.
2. Save all editor buffers. Choose **Prepare implementation from reviewed advice** and read the warning that generated edits may be incorrect.
3. The **I reviewed the advice · Prepare implementation** button confirms preparation. PerfChecker records a Git checkpoint of the current on-disk code, including tracked modifications and non-ignored untracked files, then creates an isolated temporary checkout.
4. The tool receives that checkout's canonical absolute path and an instruction to inspect, edit and test **only there**. It must leave changes for review and avoid publishing, pushing, deploying or modifying external services.
5. Read the implementation summary and open the proposed diff. The summary alone does not verify correctness or performance.
6. Select **Apply reviewed implementation changes** only after checking the actual diff. Application updates working-tree files without changing HEAD or the real Git index.
7. Rerun relevant correctness checks, including empty inputs, boundary values and the representative types your API accepts, then collect compatible before/after measurements. A shorter expression can change empty-input or numeric behavior. Use **Restore implementation checkpoint** if you need to reverse the applied patch and the repository has not drifted.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-20" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="11 · A checkpoint and an isolated implementation" preload="none" alt="Actual native PerfChecker source diff, initialized sum_squares reduction and explicit human review" caption="Read the actual isolated source diff and its explicit initializer, then validate representative inputs before applying. The recorded Float64 example covers empty, signed and 1,000-element inputs; other types need their own oracle. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

```@raw html
<DocMedia src="/assets/screenshots/vscode-implementation.png" alt="Running PerfChecker V1 chat webview showing the implementation warning, checkpoint reference, isolated change summary, reviewed diff and explicit apply action" caption="Review the actual diff before applying. The original working tree is still unchanged at this stage; Restore becomes relevant after Apply. The UI is real, while the advice and edited fixture are demonstration data." />
```

A useful first advice request is: “Explain the allocation observations in this
report. Separate measured facts from possible causes and suggest one correctness
check before proposing a change.” Before preparing implementation, name the
reviewed change and validation you want, for example: “Prepare only the reviewed
buffer-reuse change; preserve the public API and validate empty inputs, boundary
values and supported numeric types with its correctness tests. Do not claim a
speedup without comparable measurements.”
Check the diff and worker output yourself. The word `complete` in a tool reply
does not establish that tests passed or that performance improved.

!!! warning "The tool must enforce workspace access"
    MCP and the prompt do not provide an operating-system sandbox. The selected server/agent must honor the supplied workspace and preferably confine itself independently. A remote HTTPS server does not automatically see local files; it needs a deliberately configured shared filesystem or bridge. Advice mode likewise depends on the chosen tool respecting its advice-only contract.

Preparation requires Git and an existing HEAD commit. Unsupported repositories, unresolved conflicts, submodules, absolute symlinks and symlinks outside the repository are rejected. Ignored untracked files are excluded; ignored files already tracked or force-added to staging are retained. Save editor buffers first; unsaved content cannot be backed up by Git.

V1 also refuses clean/smudge filters (including Git LFS), `working-tree-encoding` and `ident` expansion so checkpoint operations cannot invoke transformation drivers. Ordinary CRLF conversion is supported. Use a repository without these attributes for implementation, or apply advice manually.

## Checkpoints and recovery

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-08" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="12 · Apply, validate, remeasure and restore" preload="none" alt="Actual native PerfChecker Apply and Restore controls with independently checked Julia results and allocation" caption="Apply the reviewed source change, inspect the independent Julia oracle and restore the previous source exactly. The recorded workload's allocation probe is 8072 B before and 0 B after; compatible timing measurements remain a separate step. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

The checkpoint uses a dedicated ref of the form `refs/perfchecker/checkpoints/<id>`. A reviewed proposal also has a retained Git ref. These preserve the proposal/recovery content independently from its temporary checkout. The original branch and staging are preserved.

The chat displays the checkpoint reference and retains proposal recovery metadata across extension-host reloads. An active per-workspace Git ref also keeps recovery discoverable independently of VS Code storage. Temporary agent workspaces are cleaned up after collection. Git refs remain available for recovery; they are not user commits added to your branch.

Starting a new conversation or changing the attached evidence keeps the current proposal and its restore action. Only **Discard proposal** explicitly abandons the active proposal pointer; the retained Git refs remain available for manual recovery.

To inspect manually, substitute the exact refs displayed by the extension:

```sh
git show <checkpoint-ref>:relative/path.jl
git diff <checkpoint-ref> <proposal-ref>
```

Use the extension's restore action for the reviewed applied proposal. Apply and restore conservatively refuse when the repository's checkpointed tree has changed, even in a file outside the proposal. Inspect that drift and recover individual content deliberately. The checkpoint contains the on-disk tree; it does not encode an unsaved editor buffer or recreate every historical staging boundary.

Cancellation stops the local client worker. The server may already have changed its isolated checkout or may continue work until it handles the disconnect. Failure/cancellation is not proof that an agent performed no edits. The extension retains the checkpoint but cleans up its temporary checkout after failure/cancellation; it does not necessarily retain a partial proposal for review. No partial change is automatically applied to the original project. A caller of the low-level API owns its workspace lifetime and must inspect it after an interrupted request.

## Low-level implementation API

Callers outside the extension must create their own checkpoint and isolated checkout, obtain the user's reviewed implementation request, and implement their own diff review/application/recovery workflow:

```julia
implementation_config = AdvisorConfig(
    protocol = :mcp_http, endpoint = "http://127.0.0.1:8765/mcp",
    mcp_tool = "implement", mcp_response = :text)
result = implement_advice(messages; config = implementation_config,
    workspace = isolated_checkout,
    advice = read_advice("perf/results/advice.json"))
```

`implement_advice` validates the request and canonicalizes the existing workspace path; it cannot prove that a directory is isolated. It does not create a backup or apply changes. The result has schema `perfchecker-narrative/1`, `advisor_mode = "implementation"`, and `implementation_status = "requires_diff_review"`, including after a provider failure because a tool might already have made edits. Check `status` separately. `complete` means the tool returned a reply, not that its changes are correct.

## What is transmitted

Evidence narration sends a bounded projection of recommendation IDs, rules,
observations, experiments, verifications and limits. It does not automatically
read project source, environment contents or raw logs, or add source-location
fields. Supplied `hypothesis`, `action` and `validation` strings are retained
without redaction; check them before transmitting evidence.

Chat additionally sends your typed messages and retained earlier replies. Anything you paste, including code or paths, therefore becomes part of the request. Implementation additionally sends the isolated checkout's absolute path, and the selected tool can inspect code accessible there. Authentication is sent only in the configured request header. Consider the endpoint's data/cost policy before opting into a remote connection.

A tool with filesystem access can inspect files beyond the bounded evidence projection; that projection does not restrict its filesystem permissions. The optional local Codex connector, for example, can inspect the selected advice workspace or isolated implementation checkout. Text results carry `reference_status = "unstructured_not_verified"`; individual statements get no invented citations. No API here adopts a performance baseline automatically.

```@raw html
<a id="Optional-bounded-investigation"></a>
```

## Structured investigations

Structured mode belongs to bounded investigation, rather than free-form implementation chat. Local stdio and Codex connections supply text chat tools. Disconnect a temporary connector before configuring a saved external structured tool. To let that assistant select an experiment, use `mcp_response = "structured"` and enable `advisorInvestigates`. The tool returns:

```json
{
  "cards": [{"evidence_id": "an exact supplied ID", "explanation": "Supported explanation"}],
  "experiment_id": "stop"
}
```

Unknown/duplicate evidence IDs and unknown experiment IDs are rejected. Only declared experiments can run; count and duration budgets still apply. Text mode refuses experiment selection. Source edits use the separate explicit implementation workflow.

Provider requests and worker startup consume the investigation's time budget.
Each provider deadline is the smaller of its configured timeout and the
remaining budget; experiment deadlines are bounded in the same way. The other
provider fields remain intact, including custom instructions, MCP tool and
argument settings, response mode, protocol revision and authentication.

## CLI and automation clients

Create a request JSON containing `messages` and optional deterministic `advice`. Implementation additionally requires `workspace` and can set `workspace_argument`:

```json
{
  "messages": [{"role": "user", "content": "Explain how to validate an allocation change."}]
}
```

```sh
julia --startup-file=no --project=perf/controller -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- chat --source=perf/chat-request.json --advisor-config=perf/advisor.json
```

Replace `chat` with `implement` only with an implementation-tool config and a caller-owned isolated checkout in the request. The CLI emits the narrative JSON and exits 0 for a completed reply, 1 for provider failures, cancellation or timeout. POSIX line continuations do not work in PowerShell; these examples use one line.

## Compatibility and failures

PerfChecker supports the HTTP subset needed for one explicit tool: JSON and request-scoped SSE replies, paginated discovery (at most 32 pages), legacy initialization/session release, and modern request metadata plus annotated argument headers. Revisions are explicit; no silent downgrade occurs. Responses are capped at **1 MB**; redirects and automatic retries are disabled.

See the official [2026-07-28 Streamable HTTP specification](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) and [2025-11-25 transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) for the server contracts. The extension's stdio connector uses newline-delimited JSON-RPC: `2025-11-25` initializes a session and `2026-07-28` discovers server capabilities and includes request metadata. Both require the tools capability and the exact selected revision; there is no downgrade. Messages are capped at 1 MB, and the local Julia-to-stdio adapter accepts requests up to 250,000 bytes. Server requests and interactive continuations are refused.

Deprecated HTTP+SSE endpoints, sampling, elicitation, roots, subscriptions, tasks, interactive OAuth login/refresh and multi-round-trip `input_required` interactions are unavailable. Choose a tool that can complete the configured request without those features. The stdio mode is an extension connector for text advice and explicit implementation, not a new Julia `AdvisorConfig(protocol = :mcp_stdio)` provider or a structured-experiment selector.

## Connection examples

The HTTP tool configuration above is the common path. Connector-specific names and executable requirements apply only to the corresponding example.

```@raw html
<a id="Connect-an-authenticated-Codex-CLI"></a>
<a id="Local-connector-steps"></a>
```

::: tabs

== HTTP tool configuration

Use [Configure the advice tool](#Configure-the-advice-tool) with your server's discovered schema. The example uses `review_export(question, context)`; it does not require Codex. For implementation, configure a separate trusted tool and follow the same [review, checkpoint and recovery workflow](#Switch-from-advice-to-implementation).

== Codex CLI (optional)

### Local connector steps

PerfChecker can connect an installed, authenticated Codex CLI through a local MCP bridge with separate advice and implementation tools. The connector invokes `codex exec`; it does not require `codex mcp-server`.

1. Use a native Codex CLI supporting the flags below and authenticate it yourself with `codex login` in a terminal. Prepare the Julia controller with PerfChecker and `HTTP`, as described in [VS Code configuration](interfaces/vscode-configuration.md).
2. If the executable is outside VS Code's PATH, set **PerfChecker: Codex Executable** (`perfchecker.codexExecutable`) to its native binary path. On Windows, use the native `.exe`; npm `.cmd` and `.bat` launchers are unsupported.
3. Open the trusted package workspace and **PerfChecker: Chat with performance advisor**. Choose **Connect Codex CLI**, or run **PerfChecker: Connect authenticated Codex CLI**. PerfChecker checks version, supported flags and existing login without starting a model turn.
4. Ask for advice, optionally attaching saved evidence. Review the answer, then use the [explicit implementation workflow](#Switch-from-advice-to-implementation) if you want the agent to prepare a change.
5. Choose **Disconnect Codex**, or run **PerfChecker: Disconnect local Codex**, to return to your saved advisor configuration. After an editor reload, connect again when needed.

Qualification used **Codex 0.159.2** for the executable contract and connector
lifecycle, and **Codex 0.162.0-alpha.2** for authenticated multi-turn advice and
reviewed source implementation. Two separate source fixtures were exercised:

| Source and controller | What the authenticated test checked |
| --- | --- |
| JavaScript fixture, including requests through the registered PerfChecker 1.0.0 Julia CLI | Contextual advice, an isolated patch, Node correctness, diff review, apply, exact restore and cancellation |
| Julia `sum_squares`, Julia 1.13.1 and Core 1.0.1 source tree `4fbc3c25543aa4f9b1154c227e5432f0cd62df91` | Two advice turns, an isolated source-only patch, real Julia correctness and allocation probes, apply, exact restore, cancellation of a started Codex turn and disconnect |

The Julia proof used the 1.0.1 source checkout, before General registration. It
checked empty Float64 input, signed values and a 1,000-element Float64 vector:
the expected results were `0.0`, `14.0` and `333833500.0`. The warmed
`@allocated` probe recorded **8072 B before and 0 B after** for that specific
workload. It did not measure a timing improvement or establish equivalence for
all Julia element types.

These authenticated connector tests are separate from native VS Code footage
using a controlled MCP response fixture. That footage exercises real editor
controls and Julia workers; its scripted responses are identified in the
captions. Consult the release qualification report for the final native
platform matrix. These are the CLI versions actually exercised; intermediate
releases have not been qualified by inference.

The connector requires `--no-daemon`, `--ignore-user-config` and `--ignore-rules`,
plus the `exec` ephemeral, sandbox and output flags. Its probe checks the selected
executable. Unsupported installations fail explicitly. Use a compatible HTTP server and advice tool if these flags are unavailable. See the official
[Codex noninteractive workflow example](https://developers.openai.com/cookbook/examples/codex/build_iterative_repair_loops_with_codex)
for the CLI execution model.

PerfChecker starts an authenticated HTTP endpoint on `127.0.0.1` with a random port. The endpoint and automatically generated Bearer token exist only in this editor session. They are not saved in settings or `perf/advisor.json`. The explicit connection authorizes chat for this session, including when your saved provider is disabled. It temporarily takes precedence over saved provider configuration; disconnecting or reloading restores that configuration and its enabled/disabled state. Never copy this temporary endpoint into a configuration file.

The advice tool is `ask_perfchecker(prompt)` and uses the CLI's `read-only` sandbox. The implementation tool is `implement_perfchecker(prompt, workspace)` and uses `workspace-write` in the canonical temporary PerfChecker checkout. Both run without the shared Codex daemon so cancellation owns the launched process. The checkpoint, diff review and restore workflow remain the same as for an external agent.

The connector uses your existing account and the CLI's default model. Custom user profiles, model/provider configuration, MCP servers, hooks and rules are not inherited. A project or implementation copy containing project `.codex` configuration is refused before invocation. Sandbox support depends on the CLI installation and platform. The agent can inspect files in its working directory; the configured model provider processes the requested context, and ordinary account usage or charges apply. Git proposals and checkpoints remain recoverable independently of the connection.

Maintainers can reproduce the authenticated connector test from the extension
repository after `npm test`:

```sh
PERFCHECKER_TEST_CODEX=/path/to/codex node --test test/codex-real.test.mjs
```

For the separate Julia-source proof, select the Julia executable, controller
project and exact expected Core tree deliberately:

```sh
PERFCHECKER_TEST_CODEX=/path/to/codex \
PERFCHECKER_TEST_CODEX_JULIA=1 \
PERFCHECKER_TEST_JULIA=/path/to/julia \
PERFCHECKER_TEST_JULIA_PROJECT=/path/to/controller \
PERFCHECKER_TEST_CORE_TREE=4fbc3c25543aa4f9b1154c227e5432f0cd62df91 \
node --test --test-name-pattern='real Codex Julia implementation' test/codex-real.test.mjs
```

The controller needs the stated PerfChecker source and `HTTP`. These opt-in
tests send real model requests against your existing account and remove their
disposable source, Git and implementation fixtures. Use their source and
measurement boundaries when interpreting the result for your own package.

:::

## Troubleshooting

| Result/problem | Next check |
| --- | --- |
| Provider unavailable | `HTTP` or the explicit provider package exists in Runner Project |
| Selected tool unavailable | Exact case-sensitive tool name and catalog authorization |
| Additional arguments required | Tool's input schema and `mcp_arguments` |
| HTTP error | Endpoint, revision, authentication and remote-HTTPS opt-in |
| Unsupported interaction | Choose a tool that finishes without sampling/elicitation/roots |
| Reply rejected | Nonempty text at most 16,000 characters; valid structured IDs if structured |
| Timeout | Increase explicit deadline if needed; it includes Julia startup |
| Cancellation | Local worker stopped; server interruption depends on the server |
| Apply/restore refused | Repository drifted; inspect before recovering content |
| Git transformation unsupported | Check attributes for filters/LFS, working-tree encoding or ident expansion |
| Codex executable unsupported | Native binary with the required flags; versions exercised are 0.159.2 and 0.162.0-alpha.2 |
| Codex not authenticated | Run `codex login` yourself, then reconnect |
| Project `.codex` configuration refused | Use a clean workspace or your explicitly configured compatible HTTP advice tool |
| Codex disconnected after reload | Connect again; saved provider settings and Git recovery are retained |

Unsupported interactions, malformed responses and tool errors retain the deterministic fallback. A failed optional advisor does not change measured verdicts.
