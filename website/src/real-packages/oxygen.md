# Oxygen: requests and a local server

[Oxygen.jl](https://oxygenframework.github.io/Oxygen.jl/stable/) is a web framework
built on HTTP.jl. This example exposes the event-processing operations from
[DataStructures](datastructures.md) as three POST routes: `/events/heap`,
`/events/counter` and `/events/buffer`.

It answers two different questions. How much work does a request require inside
the application? And how long does a local client wait for its response? The
first uses Oxygen's router without a socket. The second starts a real loopback
server and sends real HTTP requests.

## 1. Test the routes

After the [core setup](index.md), prepare the separate Oxygen environment:

```sh
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/test.jl
```

The tests send empty, singleton and larger event lists through all three routes.
They verify both the HTTP status and the decoded response against independent
expected answers. They also check that an error response fails the oracle and
that an unknown route returns 404. A second test set sends requests through a
real server bound to `127.0.0.1`, then closes that server in a `finally` block.

Current Oxygen versions use an independent router. Early versions have a global
router; PerfChecker measures each of them in an isolated worker process, so the
example cannot replace the Web Studio's routes.

## 2. Measure the request pipeline across releases

```sh
julia --project=. oxygen/measure.jl plan
julia --project=. oxygen/measure.jl quick
julia --project=. oxygen/measure.jl history
```

The historical selection starts with **Oxygen 1.0.0, released in May 2022**, and
continues through the minor-release generations up to **1.11.0 in August 2026**. It
measures the three routes with BenchmarkTools and the heap route with Chairmarks.
The body describes 2,048 deterministic events. **Only the Oxygen release is
varied explicitly.** Julia resolves DataStructures and HTTP according to that
release's declared compatibility requirements; the example does not pin a
DataStructures version. Each result records its resolved environment.
All **48 recorded checks passed their correctness oracles**.

For example, Oxygen 1.4–1.7.3 requires DataStructures 0.18, whereas later Oxygen
releases also allow 0.19. Such a dependency transition belongs to this Oxygen
comparison and can help explain a change in the measured request pipeline.
The [DataStructures history](datastructures.md) is a separate experiment that
varies DataStructures directly.

The timed operation includes route matching, JSON decoding, event processing
and JSON response encoding. Request construction happens before timing, and
response verification happens afterwards. There is **no TCP connection** in
this historical matrix.

Oxygen 1.0 uses HTTP.jl 0.9, 1.1 moved to HTTP.jl 1, and 1.11 uses HTTP.jl 2. A
historical difference can therefore come from Oxygen or its resolved dependency
stack. HTTP.jl's package version is not the HTTP/1.1 or HTTP/2 wire protocol.
The example handles registration macros in early releases, the addition of
independent routers with `@oxidise`, its later spelling `@oxidize`, and versions
where `internalrequest` has no `metrics` keyword. It resolves these API choices
before collecting samples. The request bytes and response oracle stay the same.

| Release | Published | Context |
| --- | --- | --- |
| 1.0.0 | 2022-05-28 | First release; HTTP.jl 0.9 and a global router |
| 1.1.0 | 2022-08-19 | Migration to HTTP.jl 1 |
| 1.2.0 | 2023-09-28 | PackageCompiler compatibility work |
| 1.3.0 | 2023-12-14 | Templating and package extensions |
| 1.4.0 | 2024-01-13 | Metrics dashboard |
| 1.5.0 | 2024-02-27 | Independent application contexts through `@oxidise` |
| 1.6.0 | 2025-01-11 | Context injection and Julia compatibility changes |
| 1.7.0 | 2025-02-05 | Next minor-release generation |
| 1.8.0 | 2025-11-19 | Next minor-release generation |
| 1.9.0 | 2025-12-14 | Next minor-release generation |
| 1.10.0 | 2026-01-01 | Last selected generation using HTTP.jl 1 |
| 1.11.0 | 2026-08-28 | Migration to HTTP.jl 2 |

These are [GitHub release publication dates](https://github.com/OxygenFramework/Oxygen.jl/releases).
The curves space versions equally and label their dates; they do not use a
calendar-time scale. All releases run on the same current Julia runtime, not
the Julia versions available when they were published.

The [1.1](https://github.com/OxygenFramework/Oxygen.jl/releases/tag/v1.1.0),
[1.5](https://github.com/OxygenFramework/Oxygen.jl/releases/tag/v1.5.0) and
[1.11](https://github.com/OxygenFramework/Oxygen.jl/releases/tag/v1.11.0)
transitions are useful boundaries to investigate. A change in these curves is
an observation about the resolved application stack, not proof that a specific
Oxygen commit caused it. Use the saved environment fingerprints and repeat the
neighboring versions before drawing that conclusion.

For example, repeat only the HTTP.jl 2 transition:

```sh
julia --project=. oxygen/measure.jl history 1.10.0 1.11.0
```

The gallery's **Resolved dependency versions** section shows which HTTP,
DataStructures and JSON versions actually ran at each point. Its download also
contains the remaining dependencies and manifest fingerprints.

The recorded resolution selected HTTP **0.9.17**, **1.11.0** or **2.6.7**,
depending on Oxygen's release. It selected DataStructures **0.18.22** for the
1.4–1.7 points and **0.19.6** for the others. These are results of dependency
resolution, not manually paired DataStructures test versions.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/oxygen/normalized.json" figure="/examples/real-packages/oxygen/normalized.svg" package-name="Oxygen" />
```

Elapsed time is the request pipeline's duration. Allocation activity includes
decoded JSON objects and the response, not just the data structure. GC time can
remain zero for short samples even when the operation allocates heavily. Use
the separate curves and distributions to see both absolute values and variation.

```@raw html
<PackageGallery package-name="Oxygen" directory="/examples/real-packages/oxygen" />
```

## 3. Add a real loopback round trip

```sh
julia --project=.controller/oxygen oxygen/loopback.jl
```

The script starts the service, warms the route and connection, measures 30
requests, verifies the answer and always stops its server. It saves the samples,
Oxygen and HTTP versions, Julia version and thread count to a new JSON file
under `results/`. Set `OXYGEN_EXAMPLE_PORT` if the default port 18872 is occupied.

This measurement includes the local HTTP client, server and waiting time in
one Julia process. It is a useful integration experiment; it is not a capacity
test with independent clients, remote latency or concurrent load.

The record includes **request and response body bytes**. These are application
payload sizes. HTTP headers, TCP/IP overhead, retransmissions and packets are
not counted; `wire_bytes` and `packets` are explicitly `null` rather than invented
zeros. For operating-system interface counters, see
[network measurement](../network-measurement.md). Select the loopback interface
explicitly on a system that exposes it and keep unrelated traffic out of the
measurement window.

## 4. Profile and inspect in the web interface

```sh
julia --project=. oxygen/measure.jl profiles
julia setup.jl web
julia --project=.controller/web web.jl oxygen
```

The last command starts **PerfChecker's** web interface on port 8873 by default.
The suite's target workers load their own Oxygen version. The controller's
version does not force the version measured in the isolated worker.

Follow [the interface recipes](interfaces.md) to use VS Code, Pluto or terminal
plots instead. GPU and remote-network performance are outside this example;
neither is implied by a successful local request test.
