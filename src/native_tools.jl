"""
    native_tool_plan(tool, script; project=dirname(Base.active_project()),
                     output="native-profile", julia=first(Base.julia_cmd().exec),
                     suppressions=nothing)

Prepare shell-free arguments for optional native profilers. No process is started
and no software is installed. Linux tools can be planned on Windows for execution
inside Linux/WSL with Linux paths. The plan reports local availability separately
from qualification. Capture the workload's oracle and dependency inventory alongside
the resulting artifact; a profiler exit code does not prove workload correctness.

Supported tools are `:memcheck`, `:callgrind`, `:massif`, `:cachegrind`,
`:heaptrack`, `:perf` and `:vtune`; unknown tools or empty script/output strings
raise `ArgumentError`. Return `perfchecker-native-tool-plan/1` with executable,
argument vector, intended platform/artifact paths, availability and limitations.
`suppressions` adds a Valgrind suppressions-file argument only. Paths are passed
as supplied, so callers planning a WSL/Linux run must supply paths valid there.
No output directories, suppression files or profiler artifacts are created.
"""
function native_tool_plan(tool::Symbol, script::AbstractString;
        project = dirname(Base.active_project()), output::AbstractString = "native-profile",
        julia::AbstractString = first(Base.julia_cmd().exec), suppressions = nothing)
    isempty(script) && throw(ArgumentError("script is required"))
    isempty(output) && throw(ArgumentError("output is required"))
    invocation = [
        String(julia), "--startup-file=no", "--project=$(project)", String(script)]
    executable, platform, args, artifacts = if tool in (
        :memcheck, :callgrind, :massif, :cachegrind)
        arguments = ["--tool=$tool", "--smc-check=all-non-file", "--trace-children=yes"]
        suppressions === nothing || push!(arguments, "--suppressions=$suppressions")
        artifact = "$output.%p"
        if tool == :memcheck
            append!(arguments,
                ["--leak-check=full", "--show-leak-kinds=definite",
                    "--error-exitcode=97", "--xml=yes", "--xml-file=$artifact.xml"])
            artifact *= ".xml"
        else
            push!(arguments, "--$tool-out-file=$artifact")
        end
        ("valgrind", "Linux", [arguments; invocation], [artifact])
    elseif tool == :heaptrack
        ("heaptrack", "Linux", ["-o", String(output), invocation...], [String(output)])
    elseif tool == :perf
        ("perf",
            "Linux",
            ["record", "-g", "--call-graph", "dwarf",
                "-o", String(output), "--", invocation...],
            [String(output)])
    elseif tool == :vtune
        ("vtune", string(Sys.KERNEL),
            ["-collect", "hotspots", "-result-dir", String(output), "--", invocation...],
            [String(output)])
    else
        throw(ArgumentError("supported tools: memcheck, callgrind, massif, cachegrind, heaptrack, perf, vtune"))
    end
    supported = tool == :vtune ? (Sys.islinux() || Sys.iswindows()) : Sys.islinux()
    available = supported && Sys.which(executable) !== nothing
    Dict{String, Any}("schema_version" => "perfchecker-native-tool-plan/1",
        "tool" => string(tool), "executable" => executable, "arguments" => args,
        "platform" => platform, "artifacts" => artifacts, "executed" => false,
        "availability" => !supported ? "unsupported_platform" :
                          available ? "executable_found" : "not_installed",
        "qualification" => "not_tested", "scope" => "whole_process_including_startup",
        "limitations" => ["Profiler overhead is not native workload timing.",
            "JIT/native symbol attribution depends on runtime build and debug symbols.",
            "Child process capture and native allocations require independent qualification."])
end
