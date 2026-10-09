@testitem "Advisor responses preserve HTTP transfer chunks" tags=[
    :integration, :advisor_http, :advisor_http_chunks] begin
    using PerfChecker, HTTP, Sockets
    extension = Base.get_extension(PerfChecker, :HTTPAdvisorExt)

    function chunked_provider(f, parts)
        listener = listen(ip"127.0.0.1", 0)
        port = getsockname(listener)[2]
        server = @async begin
            socket = accept(listener)
            try
                headers = readuntil(socket, "\r\n\r\n")
                if occursin(r"(?i)transfer-encoding: chunked", headers)
                    while true
                        count = parse(Int, strip(readline(socket)); base = 16)
                        count == 0 && (readline(socket); break)
                        read(socket, count)
                        readline(socket)
                    end
                else
                    length_header = match(r"(?i)content-length: (\d+)", headers)
                    length_header === nothing || read(socket, parse(Int, length_header[1]))
                end
                write(socket,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
                for part in parts
                    write(socket, string(sizeof(part); base = 16), "\r\n", part, "\r\n")
                    flush(socket)
                end
                write(socket, "0\r\n\r\n")
            finally
                close(socket)
            end
        end
        try
            return f(port)
        finally
            close(listener)
            wait(server)
        end
    end

    chunked_provider(["{\"data\":[", "{\"id\":\"tiny\"}]}"]) do port
        config = AdvisorConfig(
            endpoint = "http://127.0.0.1:$port/v1/chat/completions", model = "tiny")
        result = Base.invokelatest(advisor_setup_transport, config, :probe, "")
        @test result["selected_available"]
    end
    chunked_provider([
        "{\"choices\":[", "{\"message\":{\"content\":\"complete\"}}]}"]) do port
        config = AdvisorConfig(endpoint = "http://127.0.0.1:$port/v1/chat/completions")
        result = Base.invokelatest(extension.post, config, Dict("messages" => []))
        @test result["choices"][1]["message"]["content"] == "complete"
    end
    chunked_provider([
        "{\"jsonrpc\":\"2.0\",\"id\":1,",
        "\"result\":{\"resultType\":\"complete\",\"ttlMs\":0,\"cacheScope\":\"private\",\"tools\":[]}}"]) do port
        config = AdvisorConfig(
            protocol = :mcp_http, endpoint = "http://127.0.0.1:$port/mcp", mcp_tool = "ask")
        message = Base.invokelatest(extension.mcp_request, config, "tools/list", 1, Dict())
        phases = Symbol[]
        original = PerfChecker._advisor_phase_hook[]
        PerfChecker._advisor_phase_hook[] = phase -> push!(phases, phase)
        result = try
            first(Base.invokelatest(extension.mcp_post, config, message))
        finally
            PerfChecker._advisor_phase_hook[] = original
        end
        @test isempty(result["tools"])
        @test phases == [:mcp_http_open, :mcp_stream_ready, :mcp_response_headers_wait,
            :mcp_response_body_read, :mcp_response_body_complete]
    end
end
