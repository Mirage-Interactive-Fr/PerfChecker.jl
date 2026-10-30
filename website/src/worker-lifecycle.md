# Worker lifetime and accepted results

A collector can return a valid table before its worker finishes shutting down.
The worker can then fail in an exit hook, leave a manager task unfinished or
report a cleanup error. Accepting the table at the earlier boundary loses that
failure. This review branch qualifies the owned resources before returning a
successful check or writing its successful cache metadata.

The lifecycle changes require the Malt 1.6 dependency API. PerfChecker's Julia
compatibility starts at 1.10; the dependency version is not a Julia version.
These changes are developed on `release/sdk-1.0`; upstream 1.1.1 and its historical
results keep their original provenance. PerfChecker remains an external
measurement tool with its own runtime policy, independent of Étendu3D's Julia
1.13 target.

## Ownership boundaries

| Owner | Resources | Successful boundary |
|---|---|---|
| Malt worker | Julia process, RPC connection, output pipes and manager tasks | Process reaped, connections closed, senders and pending replies retired, managed tasks finished |
| PerfChecker check | Worker-creation tasks, workers, copied environments and allocation inventories | All creation outcomes joined; results require qualified workers, while input removal requires finished users and restoration |
| Backend cleanup | Application state, collector artifacts and restoration callbacks | Every safe cleanup attempted; failures propagated rather than logged and forgotten |
| Runtime campaign | Child controller, owned descendants and captured output | Actual termination observed and owned process cleanup completed |
| Invoking application | The outermost controller process | Final exit status checked after its exit hooks, even if a report was already emitted |

Resource completion and a successful computation are separate observations.
PerfChecker checks normal worker exit, the absence of cleanup errors and failed
manager tasks, as well as resource completion. An abnormal but fully reaped
worker still invalidates the measurement.

## Order of a check

The controller validates its shutdown options before starting workers. It then
prepares the target environments, collects qualification evidence, runs the
collector and converts its result in memory. A backend such as line allocation
tracking can require the worker to stop before conversion so Julia flushes its
process-exit artifacts; that ordering remains part of the backend contract.

After work finishes or fails, the controller joins all creation tasks and
attempts every relevant worker shutdown. It runs the cleanup hooks which are
safe at that point, restores or retires owned artifacts and removes only roots
whose live users have finished. One failed cleanup does not prevent an
independent safe cleanup from being attempted.

Successful results and cache metadata are published only after this boundary
succeeds. If calculation and cleanup both fail, the cleanup exception retains
the primary failure as well. Cancellation with incomplete cleanup remains a
failed cleanup; it does not become an ordinary cancelled job which has forgotten
its worker. The same rule applies to cleanup which finished but reported a
fault. Resource closure permits retiring safe private inputs; it does not erase
the fault or make the computation successful.

## Reusing a cache without losing the exit evidence

Earlier cache identities bind the configuration, blocks, Julia and hardware,
but do not establish that the collecting worker shut down successfully. The
presence of an indexed CSV is therefore insufficient for new acceptance.

New successful cache entries carry a JSON shutdown receipt alongside their
metadata. It binds the result identity, the CSV's SHA-256, the receipt schema,
the collecting controller and Malt identities, and the qualified terminal
report. The receipt is written last, after cleanup and the result/index writes.
This ordering keeps a partially published entry from becoming accepted merely
because its CSV exists.

Allocation-profile caches have a second payload: the `.allocation-profile.toml`
sidecar holds the retained sites, stacks and independent operation totals used
to reconstruct the profile. Hashing only the CSV would leave this input outside
the acquired evidence. The receipt therefore also binds the sidecar's SHA-256.
Valid TOML with an unchanged schema/result UUID can still contain changed sites
or totals and must be rejected when its bytes differ from that digest.

The profile reader reads the sidecar once into an owned byte buffer, checks
that buffer against the receipt and parses that same buffer. It does not verify
one file read and then reopen the path for parsing. Missing payloads, missing or
invalid digests and changed bytes leave the cache unqualified before a worker
is admitted. These checks do not trigger automatic recollection. Deliberate
historical CSV reading remains available through `csv_to_table`.

Cache lookup requires a coherent receipt. A missing or inconsistent receipt
raises `PerfChecker.HistoricalCacheUnqualified`; lookup does not start a worker,
recollect the workload or rewrite the historical table to hide the missing
proof. `csv_to_table` remains available for deliberate historical reading.

A valid reused receipt describes the collecting run's acquired shutdown. Its
PID is historical; it is not queried as a new worker or interpreted as proof
about whichever process currently has that number. Reuse preserves that
provenance.

### What the receipt does and does not establish

The digest checks establish consistency with the recorded collection, assuming
the cache and its receipt are trusted. They are not a signature, authentication
of a publisher or protection against a writer which can replace both payloads
and receipt. The source identities describe the collecting PerfChecker/Malt
sources; they are not an attestation of every transitive dependency.

The receipt is also distinct from a Julia `Manifest.toml`. It supplements the
existing configuration/runtime/environment provenance rather than replacing
the resolved environment inventory. Preserve the exact Project/Manifest and
source selections separately when the experiment requires that provenance.

Writing the receipt last prevents an incomplete publication from being accepted
on the presence of a CSV alone. It is not a multi-file durable transaction:
the contract does not promise `fsync`, recovery from a power loss or rollback
of every result/index write. A partial store may remain readable historically
while being ineligible for accepted cache reuse.

Callers must serialize writes to the same result/cache entry and keep its
inputs stable during lookup. The receipt does not acquire a writer lock or
take one atomic snapshot of the CSV, sidecar, index and receipt together. The
sidecar's checked-buffer guarantee concerns that parser input; it does not
make concurrent replacement of the rest of the result store safe. Independent
owners can use separate result roots instead of sharing a writable entry.

## Shutdown budgets

The controller option `worker_shutdown` accepts a named tuple or a dictionary
with symbol keys. Its only keys are `timeout`, `exit_timeout` and `term_timeout`,
in seconds. Values must be finite, nonnegative real durations; booleans and
unknown keys are rejected.

The default phase allowances are 15 seconds for graceful exit and 15 seconds
for TERM, inside a total allowance of 50 seconds. A custom total is one monotonic
budget for a worker, including its manager tasks and connection closure. It is
not a deadline for the entire experiment or all of its workers together.

Shutdown always requests complete closure, including unmonitored pipes.
`close_unmonitored=false` is deliberately not an acceptance option here. Malt's
more general borrowed-pipe API remains available to applications which own their
output reading themselves.

These deadlines are cooperative. A serializer or output callback which cannot
be safely preempted can outlive the allowance. A zero timeout can therefore
produce an incomplete observation for a live worker; it does not authorize
forgetting that worker or deleting its environment.

## Failure and recovery

`PerfChecker.WorkerShutdownFailure` carries the terminal Malt `.report` and its
rejection reasons. For example, exit code 17 can be rejected even when the
process, pipes and tasks have all finished. Malt's incomplete-shutdown exception
instead describes resources which have not yet reached that boundary.

`PerfChecker.CheckCleanupFailure` retains the observed `.errors` and
`.directories`, plus strong `.retained_workers` references when worker closure
is still incomplete. When calculation and cleanup both fail, `.primary` retains
the primary exception with its backtrace. The historical two-argument exception
constructor remains available.

Keep the exception while recovering its retained workers. Malt can retry their
shutdown with a suitable allowance; a later resource-complete report does not
retroactively make the failed measurement valid. Inspect the retained private
inventories before restoring or removing them. Only remove roots owned by that
invocation after their live users and restoration work are finished.

An incomplete constructor rollback also matters when no worker was assigned to
the controller's worker array. Its startup exception can still report owned
resources. Absence of an array entry is not proof that deleting the prepared
root is safe.

### Cancellation while the worker constructor is running

`cancel_suite!` acknowledges one interruption request. Observe the terminal
outcome with `suite_job_status` and `wait_suite`; the request itself does not
permit removing inputs or reporting a successful check. In particular, Malt
can catch the interruption before the public `Worker` handle is assigned and
return a `WorkerStartupException` containing both the original cause and its
rollback report.

PerfChecker distinguishes whether resources are still owned from whether a
rollback reported a fault. Resource closure requires a reaped process, closed
connections, completed tasks, no active senders and no pending replies. Faults
are reported errors, failed manager tasks or failed asynchronous replies. A
report can satisfy the resource conditions and still contain one of those
faults: `complete=true` is not an error-free cancellation certificate.

| Constructor interruption outcome | Suite outcome | What the caller retains or may retire |
|---|---|---|
| Rollback resources closed, no reported fault | `:cancelled`; `wait_suite` throws the original `InterruptException` | Safe private roots can be removed after their users/restoration finish; no measurement is accepted |
| Rollback resources still owned | `:failed`; `CheckCleanupFailure` preserves the startup failure/report | Retain related private roots and available recovery ownership; a missing public handle does not release them |
| Rollback resources closed but a fault was reported | `:failed`; `CheckCleanupFailure` preserves the fault and primary interruption | Private roots may be retired once safe; keeping a failure does not require keeping already retired resources |

Normal-exit qualification for an accepted measurement must not be applied
unchanged to constructor rollback. An interrupted startup can require Malt to
send SIGKILL to its owned child. That expected termination signal alone does
not make rollback faulty. The resource and fault checks above determine
whether the original interruption can be exposed as cancellation; they do not
claim the child completed a measurement with code/signal zero.

`wait_suite(job; strict=false)` still throws `CheckCleanupFailure`. It does not
turn a faulted or incomplete rollback into cancellation or a partial result.
The original `InterruptException` is exposed only after cleanup succeeds
without faults. Recovery can later finish the retained resources, but the
failed suite stays failed; it does not publish a successful result/cache or
become cancelled retroactively. Inspect the exception's causes and inventories
before deciding which owned roots can now be removed.

## Runtime campaigns and native exit status

On POSIX, normal termination requires an observed exit code of zero **and** an
observed termination signal of zero. A process killed by SIGTERM can expose
`exit_code = 0` together with signal 15; checking the code alone loses the
failure. A bundle on disk is evidence of emitted data, not a normal exit.

Windows' owned-process provider instead records its actual native exit code
after waiting for the process and completing its owned job and output cleanup.
Its `termination_mode` is `windows_native`; POSIX `termination_signal` is
inapplicable and remains `nothing`. The `posix` mode carries code and signal.
Neither mode is inferred merely from an old record's `status = "passed"`.

Runtime records retain `process_exited`, `cleanup_complete`, the native mode,
exit code and applicable signal. PASS, resume, comparisons and regression
investigations all require the termination evidence. A missing proof is not
silently replaced by zero. Historical records remain readable and unchanged,
but their absence of this evidence does not qualify a new successful execution.

## Qualification limits

The regression tests use real workers, complete child controllers, deliberate
nonzero exit hooks and controlled SIGTERM. They also test failure propagation,
cache ordering, cleanup callbacks, cancellation and retained resources. A
synthetic SIGSEGV status tests classification without causing a native crash or
creating a core dump.

These tests target ownership and acceptance. They do not reproduce or explain
the earlier Render and Fleet controller SIGSEGV incidents. Their acquired
performance campaigns are preserved. Minimal profiling fixtures exercise the
tool's functional paths; their timings do not establish a new application
performance result. Native Windows execution requires its own platform run;
testing its status policy on Linux does not supply that hardware evidence.
