# Using a specialized local model

This is an optional advanced topic for evaluating an existing specialized
model. It assumes that [advisor setup](advisor-ui.md) already connects to a
working inference service. No tutorial elsewhere in this documentation requires
a specialized model.

PerfChecker can use a specialized model through its optional advisor provider.
The model explains recorded evidence and can choose from permitted experiments;
it does not determine whether a correctness check or performance budget passed.
PerfChecker does not train or automatically download models.

## Start with the deterministic advisor

You do not need a model to collect measurements, compare versions or inspect
profiles. The deterministic advisor also works without a download. Start there,
then add a model only if its explanations help your workflow.

To connect an existing inference server, follow [Advisor setup](advisor-ui.md).
The same configured endpoint can serve VS Code, Web interface (Oxygen), Pluto and scripts.
The model and its server stay outside the measured package environment.

## Connect a model with an adapter

A fine-tuned adapter must be compatible with the base model and inference server.
Load both through your server's configuration, then point PerfChecker's
`AdvisorConfig` at that endpoint. Keep the existing response validation enabled:
an answer must refer to supplied evidence and choose only permitted experiment
identifiers. See [Optional models and investigations](advisors.md) for the Julia
API and its fallback behavior.

Model weights, adapters and runtime files consume disk space separately. Runtime
memory also depends on the model, quantization, context length and concurrent
requests. Check these costs in the inference server before choosing a model;
the size of its file alone is not a RAM requirement.

## Check whether the advice is useful

Use saved investigations with known outcomes, including cases with no defect.
Compare the configured model with the deterministic advisor on the same input.
Check that it cites the right measurements, acknowledges missing evidence and
suggests an experiment that can actually answer the question. Valid JSON alone
does not establish that the explanation is correct.

For example, a Bibliography allocation decrease can support a claim about that
recorded export workload. It cannot establish a general speedup, native-memory
reduction or equivalent output without the corresponding measurements and
correctness checks. Keep the [comparison plot and its scope](tutorials/bibliography.md#Extend-to-historical-comparisons)
available when reviewing an explanation.

If you train an adapter independently, keep related projects and revisions in
the same dataset partition, reserve unseen cases for evaluation and have the
reference answers reviewed. Record the base model, adapter and dataset hashes
with the inference settings. No bundled experimental adapter is recommended for
general Julia optimization; configure and evaluate your own provider explicitly.
