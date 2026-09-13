module EventService
import Oxygen
import HTTP, JSON
# Oxygen renamed the macro between the historical releases in this example.
if isdefined(Oxygen, Symbol("@oxidize"))
    Core.eval(@__MODULE__, :(Oxygen.@oxidize))
elseif isdefined(Oxygen, Symbol("@oxidise"))
    Core.eval(@__MODULE__, :(Oxygen.@oxidise))
else
    # Early Oxygen releases have a process-global router. Suite workers are
    # isolated processes, so these routes cannot modify the Web interface (Oxygen).
    Core.eval(@__MODULE__, :(using Oxygen))
end
include(joinpath(@__DIR__, "../src/PerfCheckerKitchenSink.jl"))
using .PerfCheckerKitchenSink

# HTTP versions can return either immutable strings or mutable byte vectors.
# Copy bytes before String conversion because that conversion can take ownership.
body_text(body::AbstractString) = String(body)
body_text(body) = String(copy(body))

# An independent router avoids changing the Web interface (Oxygen)'s routes when both are loaded.
for kind in ("heap", "counter", "buffer")
    handler = function(request::HTTP.Request)
        raw = JSON.parse(body_text(request.body))
        input = [Tuple(Int.(row)) for row in raw]
        operation = kind == "heap" ? drain_heap : kind == "counter" ? count_events : recent_events
        HTTP.Response(200, ["Content-Type" => "application/json"]; body = JSON.json(operation(input)))
    end
    if isdefined(@__MODULE__, :post)
        post(handler, "/events/" * kind)
    else
        # The first releases expose registration only through macros.
        Core.eval(@__MODULE__, :(Oxygen.@post $("/events/" * kind) $handler))
    end
end

# The metrics keyword did not exist in the early API. Resolve this once rather
# than catching keyword errors (or doing reflection) inside timed requests.
const supports_metrics = :metrics in Base.kwarg_decl(which(internalrequest, (HTTP.Request,)))
dispatch_request(request) = supports_metrics ? internalrequest(request; metrics = false) : internalrequest(request)

"Prepare a fixed request and an independent expected response; no socket is opened."
function request_case(kind = "heap", n = 2048)
    input = events(n)
    expected = kind == "heap" ? sort(input) : kind == "buffer" ? input[max(1, n-63):end] :
        Dict(k => count(e -> e[3] == k, input) for k in unique(e[3] for e in input))
    payload = JSON.json(input)
    expected_json = JSON.parse(JSON.json(expected))
    return (
        prepare = () -> HTTP.Request("POST", "/events/" * kind,
            ["Content-Type" => "application/json"], payload),
        operation = dispatch_request,
        verify = (request, response) -> response.status == 200 &&
            JSON.parse(body_text(response.body)) == expected_json,
        payload = payload, expected = expected_json,
    )
end

"Start only this example's loopback service. The caller must terminate it in finally."
start(port = 18872) = serve(; host = "127.0.0.1", port, async = true,
    docs = false, metrics = false, show_banner = false, access_log = nothing)
stop() = terminate()

"Parameter dictionary entry point for the shared-scenario runner."
scenario(parameters) = request_case(String(Base.get(parameters, "kind", "heap")), Int(Base.get(parameters, "n", 2048)))
include(joinpath(@__DIR__, "feature-routes.jl"))
end
