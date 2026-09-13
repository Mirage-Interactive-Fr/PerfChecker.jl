# Contribute an experiment

An example is most useful when another maintainer can reproduce both the
original observation and the change that followed. Contributions can add a
package, a workload or a documented improvement to an existing example.
Open a pull request with the scripts, a small set of plots and the evidence
needed to interpret them.

Start from `examples/kitchen-sink`. Keep the lifecycle small: prepare the input,
perform one meaningful operation, verify the answer independently. Existing
TestItems are welcome. Add explicit tags only when an item must be restricted
to correctness or performance runs.

Include these facts with the result:

| Evidence | Why it matters |
| --- | --- |
| Package versions or immutable revisions, dependency manifests | Reconstruct the compared implementations |
| Workload and fixture source, seed or frozen corpus | Repeat the same work |
| Oracle and its outcome | Reject fast but incorrect answers |
| Julia version, machine, operating system, threads and CPU allocation | Understand the execution conditions |
| Collector, sample count, units and preparation boundary | Know what the numbers measure |
| Raw observations or a downloadable bundle | Replot and inspect variation |
| Baseline, change and repeated confirmation | Separate an improvement from noise |

Keep plotting and measurement separate. A documentation build should render
saved evidence quickly. Put large bundles, interactive exports and recordings
in release assets or another durable location. YouTube embeds can accompany a
written walkthrough, but a notebook should be provided as a notebook, not only
as a video of someone using it.

Explain unsuccessful or unsupported checks. An absent native tool, a missing
GPU or an incompatible runtime is not a passing test. Avoid claiming coverage
of a whole platform from a successful local smoke test.

A good contribution ends with a concrete conclusion: what changed, how much
the repeated measurement changed, what remained correct, and under which
conditions the result was observed. The community can then test the same
change on other machines rather than relying on a screenshot alone.
