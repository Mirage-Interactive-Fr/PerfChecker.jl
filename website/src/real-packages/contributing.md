# Contribute an experiment

To contribute an example, open a pull request with the workload code, its
measurements and plots. You can add a package, an operation or an improvement
to an existing example. Include enough information for another maintainer
to repeat the comparison.

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

Generate the plots from saved measurements so documentation builds stay fast.
Attach large bundles and recordings to a release or another durable download
location. Include notebooks as `.jl` files that readers can edit and run.

List unsuccessful checks with their errors, and identify tools or platforms
you could not test.

For an optimization, explain the code change and compare the repeated
measurements before and after it. Include the correctness-check result and
machine settings so others can try the change on their own systems.
