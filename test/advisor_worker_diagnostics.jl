@testitem "Advisor failure diagnostics expose only bounded phase markers" tags=[
    :unit, :advisor_chat] begin
    using PerfChecker
    mktemp() do path, io
        write(io, "PERFCHECKER_ADVISOR_PHASE dependencies_loading 0.0\n")
        write(io, repeat("PRIVATE_PATH PRIVATE_PROMPT Authorization: SECRET\n", 400))
        write(io, "PERFCHECKER_ADVISOR_PHASE mcp_tools_call 12.5\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE SECRET 13.0\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE failed PRIVATE_PROMPT\n")
        write(io, UInt8[0xff, 0xfe, 0x0a])
        flush(io)
        result = PerfChecker._advisor_worker_diagnostics(path)
        @test result["worker_phase"] == "mcp_tools_call"
        @test result["worker_log_excerpt"] ==
              "PERFCHECKER_ADVISOR_PHASE mcp_tools_call 12.5"
        @test sizeof(result["worker_log_excerpt"]) <= 8192
        @test !occursin("PRIVATE", result["worker_log_excerpt"])
        @test !occursin("SECRET", result["worker_log_excerpt"])
        write(io, "PERFCHECKER_ADVISOR_PHASE mcp_http_open 14.0\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE mcp_stream_ready 14.1\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE mcp_response_headers_wait 14.2\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE mcp_response_body_read 15.0\n")
        write(io, "PRIVATE_URL Authorization: SECRET PRIVATE_RESPONSE\n")
        write(io, "PERFCHECKER_ADVISOR_PHASE failed 16.0\n")
        flush(io)
        network = PerfChecker._advisor_worker_diagnostics(path)
        @test network["worker_phase"] == "mcp_response_body_read"
        @test occursin("PERFCHECKER_ADVISOR_PHASE mcp_response_headers_wait 14.2",
            network["worker_log_excerpt"])
        @test occursin("PERFCHECKER_ADVISOR_PHASE mcp_response_body_read 15.0",
            network["worker_log_excerpt"])
        @test !occursin("PRIVATE", network["worker_log_excerpt"])
        @test !occursin("SECRET", network["worker_log_excerpt"])
        @test sizeof(network["worker_log_excerpt"]) <= 8192
        truncate(io, 0)
        flush(io)
        @test PerfChecker._advisor_worker_diagnostics(path)["worker_phase"] ==
              "process_start"
    end
end
