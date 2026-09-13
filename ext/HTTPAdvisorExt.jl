module HTTPAdvisorExt
using PerfChecker, HTTP, Base64

function read_advisor_bytes(stream, limit)
    bytes = UInt8[]
    # HTTP 1 reads at most one transfer chunk per read(stream, n).
    # Consume the complete response while retaining a strict size bound.
    while length(bytes) <= limit && !eof(stream)
        append!(bytes, read(stream, min(65536, limit + 1 - length(bytes))))
    end
    return bytes
end

function post(config, body)
    headers = ["Content-Type" => "application/json"]
    if !isempty(config.api_key_env)
        secret = get(ENV, config.api_key_env, "")
        isempty(secret) && throw(ArgumentError("configured credential is absent"))
        push!(headers, "Authorization" => "Bearer " * secret)
    end
    bytes = Ref{Vector{UInt8}}()
    HTTP.open("POST", config.endpoint, headers;
        readtimeout = ceil(Int, config.timeout), connect_timeout = ceil(
            Int, min(config.timeout, 10)),
        retry = false, redirect = false, status_exception = false) do stream
        write(stream, sprint(io -> PerfChecker.JSON.print(io, body)))
        HTTP.closewrite(stream)
        response = HTTP.startread(stream)
        response.status == 200 ||
            throw(ArgumentError("advisor endpoint returned HTTP $(response.status)"))
        result = read_advisor_bytes(stream, 1_000_000)
        length(result) <= 1_000_000 ||
            throw(ArgumentError("advisor response exceeds limit"))
        bytes[] = result
    end
    PerfChecker._json_parse(String(bytes[]))
end

function PerfChecker.advisor_transport(
        ::Val{:chat_completions}, config::PerfChecker.AdvisorConfig, body::AbstractDict)
    post(config, body)
end

function PerfChecker.advisor_transport(
        ::Val{:chat_completions_schema}, config::PerfChecker.AdvisorConfig, body::AbstractDict)
    input = PerfChecker._json_parse(body["messages"][2]["content"])
    ids = [row["id"] for row in input["evidence"]]
    cards = Dict("type" => "array", "maxItems" => length(ids),
        "items" => Dict("type" => "object", "additionalProperties" => false,
            "required" => ["evidence_id", "explanation"], "properties" => Dict(
                "evidence_id" => Dict(
                    "type" => "string", "enum" => isempty(ids) ? ["unused"] : ids),
                "explanation" => Dict("type" => "string"))))
    # Bound prose length in the existing validator. Expanding a large maxLength
    # into a server grammar can exceed llama.cpp's grammar-complexity limit.
    schema = Dict("type" => "object", "additionalProperties" => false,
        "required" => ["cards", "experiment_id"], "properties" => Dict(
            "cards" => cards, "experiment_id" => Dict("type" => "string",
                "enum" => vcat(
                    ["stop"], [row["id"] for row in input["allowed_experiments"]]))))
    request = copy(body)
    request["response_format"] = Dict("type" => "json_schema",
        "json_schema" => Dict(
            "name" => "perfchecker_advice", "strict" => true, "schema" => schema))
    post(config, request)
end

function PerfChecker.advisor_transport(
        ::Val{:ollama}, config::PerfChecker.AdvisorConfig, body::AbstractDict)
    response = post(config,
        Dict("model" => config.model, "messages" => body["messages"], "stream" => false,
            "format" => "json", "options" => Dict(
                "temperature" => 0, "num_predict" => config.max_tokens)))
    Dict(
        "choices" => [Dict("message" => Dict("content" => response["message"]["content"]))],
        "usage" => Dict(key => response[source]
        for (key, source) in (
                ("prompt_tokens", "prompt_eval_count"), ("completion_tokens", "eval_count"))
        if haskey(response, source)))
end
include("mcp_advisor.jl")
include("advisor_setup.jl")
end
