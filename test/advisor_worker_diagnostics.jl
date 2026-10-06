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
        truncate(io, 0)
        flush(io)
        @test PerfChecker._advisor_worker_diagnostics(path)["worker_phase"] ==
              "process_start"
    end
end
