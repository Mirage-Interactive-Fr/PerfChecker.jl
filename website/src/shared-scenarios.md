```@raw html
---
search: false
---
```

# Shared scenarios

[Define and run shared scenarios](tools/scenarios.md), keeping preparation, measured operations and correctness checks separate.

Measurement and diagnostic workers keep their transport files and stdout/stderr
private. Exported failures contain exception types, callback phases and source
frames, without rendering exception messages, argument values, commands or
environments. Raw worker logs are omitted from both failed and successful
diagnostic evidence. Advisor phase markers retain their existing fixed whitelist.
If worker cleanup cannot be verified, further jobs are cancelled and the enclosing
process owner must reap remaining children; a diagnostic result does not certify
that cleanup succeeded.

```@raw html
<a id="Shared-scenarios,-discovery-and-advice"></a>
<a id="Declare-the-catalog"></a>
<a id="Discover-without-executing"></a>
<a id="CI-and-comparisons"></a>
<a id="Editor,-web-and-notebook-workflows"></a>
<a id="Open-http://127.0.0.1:8080/perfchecker/scenarios/"></a>
<a id="API-reference"></a>
<a id="Memory-and-contention-diagnostics"></a>
<a id="Legacy-worker-environment-copies"></a>
<a id="Migration-of-FeatureSpec-suites"></a>
<a id="Shared-scenarios"></a>
<a id="Define-a-case-once"></a>
<a id="Declare-a-catalog"></a>
<a id="Run,-diagnose-and-advise"></a>
<a id="Discovery"></a>
<a id="Exit-codes"></a>
<a id="Interfaces"></a>
<a id="Additional-diagnostics"></a>
<a id="Legacy-worker-copies"></a>
<a id="State-policy"></a>
```
