# Providers and discovery

Connect an existing service after collecting evidence. For narration, PerfChecker supports llama.cpp/Chat Completions, Ollama `/api/chat`, and an explicitly selected [MCP HTTP tool](mcp.md). A Chat Completions URL is not an MCP server. No provider is required for deterministic advice.

Save your actual endpoint/model in `perf/advisor.json`, then inspect inventory before sending evidence:

```json
{
  "protocol": "chat_completions",
  "endpoint": "http://127.0.0.1:8080/v1/chat/completions",
  "model": "YOUR-INSTALLED-MODEL",
  "timeout": 90,
  "max_evidence_chars": 12000,
  "allow_remote": false,
  "api_key_env": ""
}
```
```julia
using PerfChecker, HTTP
config = load_advisor_config("perf/advisor.json")
setup = advisor_setup(config)
display((setup["status"], setup["evidence_sent"], setup["generation_tested"]))
advice = read_advice("results/advice.json")
narrative = narrate_advice(advice; config) # explicit provider request
display(investigation_view(narrative))
```

Discovery has `evidence_sent=false` and `generation_tested=false`; inspect `status` and selected availability. Narration does send bounded saved evidence. Read its `status`, `cards` and deterministic `fallback`; generated prose remains unverified.

::: details Actual discovery receipt

### Controlled HTTP discovery

HTTP activates provider transport. This complete local discovery fixture returns
one model name; it never loads a model or requests generation:

```julia
using PerfChecker, HTTP, Sockets
listener = listen(ip"127.0.0.1", 0)
port = getsockname(listener)[2]
close(listener)
server = HTTP.serve!("127.0.0.1", port; verbose=false) do request
    HTTP.Response(200, ["Content-Type"=>"application/json"],
        "{\"data\":[{\"id\":\"controlled-local-fixture\"}]}")
end
try
    config = AdvisorConfig(endpoint="http://127.0.0.1:$port/v1/chat/completions",
        model="controlled-local-fixture", timeout=45)
    result = advisor_setup(config)
    display((result["status"], result["evidence_sent"], result["generation_tested"]))
finally
    close(server)
end
```

```@raw html
<p>Observed output: <strong><code>(&quot;complete&quot;, false, false)</code></strong>, with
<code>selected_available=true</code>. The <a href="../examples/tool-recipes/receipts.json">receipt</a>
records one <code>GET /v1/models</code> to the controlled loopback provider. This qualifies
the discovery/transport path, without assessing model reasoning. For a real
provider, replace the fixture with a configured service and inspect actual
availability. See <a href="providers.html">advice setup</a>.</p>
```


This controlled HTTP result is not a real provider conversation or evidence of model quality.

:::

::: details Other transports, trust and model management

Use `protocol="ollama"` with your existing `/api/chat` endpoint for Ollama; a Chat Completions-compatible llama.cpp service uses the configuration above. `model` selects the installed model for those protocols. For MCP, the server chooses its model; supply model/limit arguments only when its actual tool schema accepts them. Remote endpoints require `allow_remote=true` and HTTPS. Store the credential only in the environment variable named by `api_key_env`.

PerfChecker does not install services or automatically download weights. The [editor](../interfaces/vscode.md), [Web](../interfaces/web-studio.md) and [Pluto](../interfaces/pluto.md) setup controls can discover and save configuration. Local Ollama management supports explicit confirmed download/delete and unload; deletion affects every project sharing that server. Remote management is disabled. Reported sizes include shared layers; cancellation can leave partial server downloads.

An advisor configuration file takes precedence over editor provider settings; a connected temporary local session takes precedence until disconnected. Web studio persists its panel configuration under its reports directory; Pluto action buttons explicitly launch requests. Changing fields launches none.

For another protocol, extend `advisor_transport(::Val{:my_provider}, config::AdvisorConfig, request::AbstractDict)`, translating the bounded request and honoring the timeout. Return the declared response contract; include usage only when the provider reports it.

:::
