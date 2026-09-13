using PerfChecker, BenchmarkTools, HTTP, JSON, Statistics
include(joinpath(@__DIR__, "service.jl"))
port = parse(Int, get(ENV, "OXYGEN_EXAMPLE_PORT", "18872"))
case = EventService.request_case("heap")
url = "http://127.0.0.1:$port/events/heap"
headers = ["Content-Type" => "application/json"]
request() = HTTP.post(url, headers, case.payload)
output = joinpath(@__DIR__, "../results")
mkpath(output)
try
    EventService.start(port)
    response = request() # Compile and establish the local connection before sampling.
    @assert case.verify(nothing, response)
    trial = @benchmark request() samples=30 evals=1 seconds=1
    @assert case.verify(nothing, request())
    record = Dict("scope" => "loopback HTTP client and server in one Julia process; warm connection",
        "package" => "Oxygen", "version" => string(pkgversion(EventService.Oxygen)),
        "http_version" => string(pkgversion(HTTP)), "julia_version" => string(VERSION),
        "threads" => Threads.nthreads(), "correctness" => "passed",
        "time_ns" => trial.times, "gc_time_ns" => trial.gctimes,
        "allocated_bytes" => trial.memory, "allocations" => trial.allocs,
        "request_body_bytes" => ncodeunits(case.payload), "response_body_bytes" => length(response.body),
        "packets" => nothing, "wire_bytes" => nothing)
    file = tempname(output) * "-loopback.json"
    open(io -> JSON.print(io, record, 2), file, "w")
    println("Median round trip: ", median(trial.times) / 1e6, " ms. Evidence: ", file)
finally
    EventService.stop()
end
