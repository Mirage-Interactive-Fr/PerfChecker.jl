# Included inside EventService after creating its isolated Oxygen router.
# These public route macros also existed in Oxygen 1.0.
Core.eval(@__MODULE__, quote
    @get "/features/plain" function(req::HTTP.Request)
        "ready"
    end
    @get "/features/add/{a}/{b}" function(req::HTTP.Request, a::Int, b::Int)
        a + b
    end
    @get "/features/query" function(req::HTTP.Request)
        parameters = Oxygen.queryparams(req)
        parse(Int, parameters["a"]) + parse(Int, parameters["b"])
    end
    @get "/features/json" function(req::HTTP.Request)
        Dict("ready" => true, "values" => collect(1:64))
    end
    @get "/features/html" function(req::HTTP.Request)
        Oxygen.html("<p>ready</p>")
    end
    @post "/features/binary" function(req::HTTP.Request)
        HTTP.Response(200; body = Oxygen.binary(req))
    end
end)

const HTTP_FEATURES = ("plain", "path", "query", "json", "html", "binary", "not_found")

"One isolated HTTP feature with a fixed request and an independently known response."
function feature_case(kind::AbstractString)
    target, payload, expected, status = if kind == "plain"
        ("/features/plain", "", "ready", 200)
    elseif kind == "path"
        ("/features/add/19/23", "", "42", 200)
    elseif kind == "query"
        ("/features/query?a=19&b=23", "", "42", 200)
    elseif kind == "json"
        ("/features/json", "", Dict("ready" => true, "values" => collect(1:64)), 200)
    elseif kind == "html"
        ("/features/html", "", "<p>ready</p>", 200)
    elseif kind == "binary"
        bytes = repeat("0123456789abcdef", 256)
        ("/features/binary", bytes, bytes, 200)
    elseif kind == "not_found"
        ("/features/does-not-exist", "", nothing, 404)
    else
        throw(ArgumentError("Unknown HTTP feature: $kind"))
    end
    return (prepare = () -> HTTP.Request(kind == "binary" ? "POST" : "GET", target, [], payload),
        operation = dispatch_request,
        verify = (_, response) -> response.status == status &&
            (expected === nothing || (kind == "json" ? JSON.parse(body_text(response.body)) == expected : body_text(response.body) == expected)),
        payload = payload, target = target)
end
