using PerfChecker, HTTP, JSON, Statistics, Dates
include(joinpath(@__DIR__, "service.jl"))

"""
Measure a real binary echo on loopback, including interface packet/byte counters.

Run on Linux with `lo`. Each of four payload sizes receives 30 warmed requests.
Counters belong to the entire loopback interface, not uniquely to this process.
The idle control makes unrelated traffic visible; it cannot prove attribution.
The server is always stopped, including when an oracle fails.
"""
function measure_echo_network(; port = 18874, interface = "lo", samples = 30)
    Sys.islinux() || error("This packet example requires Linux loopback counters; run in WSL on Windows")
    records = Any[]
    response = Ref{Any}()
    try
        EventService.start(port)
        idle = measure_network_interface(() -> sleep(0.1); interface, repetitions = 3)
        for n in (64, 4096, 65536, 1048576)
            payload = repeat("x", n)
            request() = (response[] = HTTP.post("http://127.0.0.1:$port/features/binary", [], payload))
            request()
            @assert response[].status == 200 && String(copy(response[].body)) == payload
            observations = Any[]
            for _ in 1:samples
                counter = only(measure_network_interface(request; interface, repetitions = 1))
                @assert response[].status == 200 && String(copy(response[].body)) == payload
                push!(observations, Dict(string(k) => getproperty(counter, k) for k in propertynames(counter)))
            end
            push!(records, Dict("payload_bytes" => n, "application_request_bytes" => n,
                "application_response_bytes" => n, "samples" => observations, "correctness" => "passed"))
            println("Measured ", n, " byte echo: ", samples, " verified network samples")
        end
        return Dict("schema_version" => "perfchecker-example-network/1",
            "package" => "Oxygen", "version" => string(pkgversion(EventService.Oxygen)),
            "http_version" => string(pkgversion(HTTP)), "julia_version" => string(VERSION),
            "os" => string(Sys.KERNEL), "threads" => Threads.nthreads(),
            "started_at" => string(now(UTC)), "interface" => interface,
            "scope" => "Warm loopback HTTP client and server in one Julia process; host-interface counters",
            "counter_note" => "On loopback, each transfer appears in both transmit and receive counters. Do not sum these as physical wire traffic.",
            "idle_control" => [Dict(string(k) => getproperty(s, k) for k in propertynames(s)) for s in idle],
            "records" => records)
    finally
        EventService.stop()
    end
end

output = isempty(ARGS) ? tempname(joinpath(@__DIR__, "../results")) * "-network.json" : abspath(ARGS[1])
record = measure_echo_network()
mkpath(dirname(output))
open(io -> JSON.print(io, record, 2), output, "w")
println("Network evidence: ", output)
