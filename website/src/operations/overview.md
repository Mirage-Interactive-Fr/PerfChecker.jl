# Choose an automation workflow

Automation repeats an experiment you can already run locally. Begin with a
working test item or suite, decide which result should fail the job, and retain
the reports so another person can inspect a failure.

| Need | Start with | Result |
| --- | --- | --- |
| Run my package's items on every change | [CI/CD](../tutorials/ci.md) | Functional outcomes and saved item measurements |
| Reject a measured regression | [Comparisons](../tutorials/comparisons.md), then CI/CD | An explicit baseline, metric and acceptance limit |
| Validate compatible versions of the PerfChecker packages | [Qualified collections](../reference/qualification.md) | Receipts for the affected integration tests |
| Dispatch work to another machine | [Hosted controller and workers](hosted.md) | Jobs and reports associated with the machine that executed them |

A completed command is not necessarily a passed performance check. Test-item
reports currently distinguish functional success from `performance="not_compared"`.
A regression gate needs a supported comparison and an explicit limit.

For a concrete sequence to automate, first reproduce one
[Bibliography item](../tutorials/bibliography.md#Reuse-the-upstream-tests-as-native-items).
Move that same command into CI before extending the selection. Remote hosting
and optional model services are not prerequisites for CI.
