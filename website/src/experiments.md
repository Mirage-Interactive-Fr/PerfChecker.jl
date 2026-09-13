# Choose an advanced experiment

Start here after you have collected a first result and can explain what it
measures. These workflows add control over the experiment: which implementation
runs, which Julia runtime runs it, or which machine supplies the observations.
They are independent of the optional model integrations.

| Your question | What you need first | Follow |
| --- | --- | --- |
| Does this source change make the same operation faster? | Two revisions and a common workload | [Compare versions](tutorials/comparisons.md) |
| How do I compare implementations while preparing and checking each sample separately? | A workload with an explicit correctness check | [Shared workload contracts](shared-scenarios.md) |
| Does a new Julia runtime change performance or compatibility? | A runnable software suite and installed runtimes | [Julia runtime comparisons](tutorials/julia-runtimes.md) |
| Can measurements from other machines help predict mine? | Matching measurements from donor machines and calibration runs on yours | [Machine calibration](machine-transfer.md) |

For a reproducible source comparison, use the
[Bibliography export experiment](tutorials/bibliography.md#Extend-to-historical-comparisons).
It holds dependency revisions fixed while changing the export implementation.
The nine-version history answers a broader question about released package
stacks, whose dependencies also change. Those are different experiments.

Keep the resulting reports: they record both the measurements and the conditions
under which they were collected. The [measurement model](measurement-model.md)
explains which differences prevent a numerical comparison.
