@testitem "Worker failure diagnostics never invoke private exception printers" tags=[:unit, :worker_privacy] default_imports=false begin
    using Test, TOML
    include(joinpath(@__DIR__, "..", "src", "worker_privacy.jl"))
    const Privacy = PerfCheckerWorkerPrivacy
    const printed = Ref(0)
    struct PrivateWorkerFailure{PrivateParameter} <: Exception
        payload::Any
    end
    Base.showerror(io::IO, error::PrivateWorkerFailure) =
        (printed[] += 1; throw(ErrorException("exception printer must not run")))
    canary = "PRIVATE_CANARY_DSN_PASSWORD_COOKIE_TOKEN"
    failure, trace = try
        throw(PrivateWorkerFailure{Symbol(canary)}(Cmd(["private-command", canary]; env = ["TOKEN=" * canary])))
    catch error
        (error, catch_backtrace())
    end
    for phase in (:prepare, :operation, :synchronize, :verify, :cleanup)
        result = Privacy.failure_result(failure, trace; status = "invalid",
            stage = :scenario_execution, callback_phase = phase, callback_cause = failure)
        @test result["status"] == "invalid"
        @test result["failure"]["exception_type"] == "PrivateWorkerFailure"
        @test result["failure"]["cause_type"] == "PrivateWorkerFailure"
        @test result["failure"]["callback_phase"] == string(phase)
        @test !isempty(result["failure"]["source_frames"])
        @test all(Set(keys(frame)) == Set(["function", "file", "line"])
            for frame in result["failure"]["source_frames"])
        io = IOBuffer(); TOML.print(io, result)
        @test !occursin(canary, String(take!(io)))
    end
    unknown = Privacy.failure_diagnostic(failure, trace;
        stage = Symbol(canary), callback_phase = Symbol(canary), callback_cause = failure)
    @test unknown["stage"] == "worker_transport"
    @test !haskey(unknown, "callback_phase") && !haskey(unknown, "cause_type")
    @test printed[] == 0
    mktempdir() do directory
        path = joinpath(directory, "response.toml")
        Privacy.write_response(path, Dict("status" => "error", "failure" => unknown))
        @test TOML.parsefile(path)["failure"] == unknown
        Sys.isunix() && @test stat(path).mode & 0o077 == 0
    end
end

@testitem "Provenance failures omit inherited environments and malformed manifest contents" tags=[:unit, :worker_privacy] default_imports=false begin
    using Test, TOML
    owner = Module(gensym(:PrivateProvenance))
    Core.eval(owner, :(using TOML, SHA))
    Base.include(owner, joinpath(@__DIR__, "..", "src", "worker_privacy.jl"))
    source = joinpath(@__DIR__, "..", "src", "qualification.jl")
    unwrap(expr) = expr isa Expr && expr.head == :macrocall ? unwrap(last(expr.args)) : expr
    selected = Set([:_sha256_file, :_environment_provenance, :_git_output, :_git_provenance])
    found = Set{Symbol}()
    for raw in Meta.parseall(read(source, String); filename = source).args
        expr = unwrap(raw)
        expr isa Expr && expr.head == :function || continue
        signature = first(expr.args)
        signature isa Expr && signature.head == :call || continue
        name = first(signature.args)
        name in selected || continue
        Core.eval(owner, expr)
        push!(found, name)
    end
    @test found == selected
    canary = "PRIVATE_CANARY_DSN_PASSWORD_COOKIE_TOKEN"
    mktempdir() do directory
        for missing_executable in (false, true)
            failure = withenv("PRIVATE_PROVENANCE_CANARY" => canary,
                    "PATH" => missing_executable ? directory : get(ENV, "PATH", "")) do
                Base.invokelatest(getfield(owner, :_git_provenance), directory)
            end
            @test !failure["captured"]
            @test failure["capture_failure"]["stage"] == "provenance_capture"
            @test failure["capture_failure"]["exception_type"] in
                ("ProcessFailedException", "IOError")
            io = IOBuffer()
            TOML.print(io, Dict(k => v for (k, v) in failure if v !== nothing))
            @test !occursin(canary, String(take!(io)))
        end
        manifest = joinpath(directory, "Manifest.toml")
        write(manifest, "private_value = [" * canary)
        failure = Base.invokelatest(getfield(owner, :_environment_provenance), directory)
        @test failure["development_capture_failure"]["stage"] == "provenance_capture"
        io = IOBuffer()
        TOML.print(io, Dict(k => v for (k, v) in failure if v !== nothing))
        @test !occursin(canary, String(take!(io)))
    end
end

@testitem "Scenario transport omits private logs and neutralizes launch and parse errors" tags=[:unit, :worker_privacy] default_imports=false begin
    using Test, TOML
    # Compile the production owner functions without importing controller
    # dependencies or starting a Julia, application or SQL worker.
    owner = Module(gensym(:PrivateTransport))
    Core.eval(owner, :(using TOML))
    Base.include(owner, joinpath(@__DIR__, "..", "src", "worker_privacy.jl"))
    source = joinpath(@__DIR__, "..", "src", "scenarios.jl")
    unwrap(expr) = expr isa Expr && expr.head == :macrocall ? unwrap(last(expr.args)) : expr
    found = Set{Symbol}()
    for raw in Meta.parseall(read(source, String); filename = source).args
        expr = unwrap(raw)
        expr isa Expr || continue
        selected = expr.head == :struct && expr.args[2] == :CancellationToken
        if expr.head in (:function, :(=)) && first(expr.args) isa Expr
            signature = first(expr.args)
            if signature.head == :call
                name = first(signature.args)
                selected |= name in (:CancellationToken, :_scenario_process,
                    :_stop_scenario_worker, :_advisor_worker_diagnostics)
                selected && push!(found, name)
            end
        end
        selected && Core.eval(owner, expr)
    end
    @test :_scenario_process in found && :CancellationToken in found
    runner = getfield(owner, :_scenario_process)
    token() = Base.invokelatest(getfield(owner, :CancellationToken))
    canary = "PRIVATE_CANARY_DSN_PASSWORD_COOKIE_TOKEN"
    launch = (command, log) -> begin
        @test any(value == "PRIVATE_WORKER_CANARY=" * canary for value in command.env)
        @test stat(last(command.exec, 2)[1]).mode & 0o077 == 0
        throw(ErrorException(canary))
    end
    result = withenv("PRIVATE_WORKER_CANARY" => canary) do
        Base.invokelatest(runner, Dict("private_fixture" => canary);
            project = dirname(@__DIR__), timeout = 1, cancellation = token(), _launch_worker = launch)
    end
    @test result["status"] == "error"
    @test result["failure"]["stage"] == "worker_launch"
    io = IOBuffer(); TOML.print(io, result)
    @test !occursin(canary, String(take!(io)))
    if Sys.isunix()
        sh = Sys.which("sh")
        @test sh !== nothing
        for (mode, diagnostic) in ((:failed, false), (:failed, true), (:complete, true), (:parse, true))
            private_directory = Ref("")
            launcher = (command, log) -> begin
                input, output = last(command.exec, 2)
                private_directory[] = dirname(input)
                @test stat(dirname(input)).mode & 0o077 == 0
                @test stat(input).mode & 0o077 == 0
                @test stat(joinpath(dirname(input), "worker.log")).mode & 0o077 == 0
                if mode == :complete
                    getfield(owner, :PerfCheckerWorkerPrivacy).write_response(output,
                        Dict("status" => "complete", "correctness" => "passed"))
                elseif mode == :parse
                    write(output, "invalid = [" * canary)
                    chmod(output, 0o600)
                end
                command = Cmd([sh, "-c", "printf '%s' '" * canary * "' >&2; exit " *
                    (mode == :failed ? "17" : "0")]; detach = true)
                run(pipeline(command; stdout = log, stderr = log); wait = false)
            end
            result = Base.invokelatest(runner, Dict(); project = dirname(@__DIR__),
                timeout = 5, cancellation = token(), diagnostic, _launch_worker = launcher)
            @test result["status"] == (mode == :complete ? "complete" : "error")
            @test !haskey(result, "log_excerpt") && !haskey(result, "worker_log_excerpt")
            io = IOBuffer(); TOML.print(io, result)
            @test !occursin(canary, String(take!(io)))
            @test !ispath(private_directory[])
        end
    end
    Core.eval(owner, :(struct PrivateCleanupProcess end))
    Core.eval(owner, :(Base.process_running(::PrivateCleanupProcess) = true))
    Core.eval(owner, :(_stop_scenario_worker(::PrivateCleanupProcess) =
        error("PRIVATE_CLEANUP_CANARY")))
    cancellation = token()
    fake = Base.invokelatest(getfield(owner, :PrivateCleanupProcess))
    result = Base.invokelatest(runner, Dict(); project = dirname(@__DIR__),
        timeout = 0.001, cancellation, _launch_worker = (command, log) -> fake)
    @test result["failure"]["stage"] == "worker_cleanup"
    @test cancellation.requested[]
    io = IOBuffer(); TOML.print(io, result)
    @test !occursin("PRIVATE_CLEANUP_CANARY", String(take!(io)))
end

@testitem "Measurement and diagnostic entry points serialize typed callback failures" tags=[:unit, :worker_privacy] default_imports=false begin
    using Test, TOML
    canary = "PRIVATE_CANARY_DSN_PASSWORD_COOKIE_TOKEN"
    mktempdir() do directory
        source = joinpath(directory, "cases.jl")
        write(source, """
module PrivateCases
function make_case(p)
    failure() = error($(repr(canary)))
    (prepare=()->(p["phase"]=="prepare" ? failure() : 1),
     operation=s->(p["phase"]=="operation" ? failure() : s),
     synchronize=(s,r)->(p["phase"]=="synchronize" ? failure() : nothing),
     verify=(s,r)->(p["phase"]=="verify" ? failure() : true),
     cleanup=s->(p["phase"]=="cleanup" ? failure() : nothing))
end
end
""")
        for entry in ("scenario_worker.jl", "diagnostic_worker.jl"),
                phase in ("prepare", "operation", "synchronize", "verify", "cleanup")
            spec = Dict("source" => source, "factory" => "PrivateCases.make_case",
                "requirements" => String[], "parameters" => Dict("phase" => phase))
            request = Dict{String, Any}("scenario" => spec, "collector" => "profile",
                "samples" => 1, "tool" => "memory", "options" => Dict("diagnostic_samples" => 1))
            input, output = joinpath(directory, "request.toml"), joinpath(directory, "response.toml")
            open(io -> TOML.print(io, request), input, "w")
            owner = Module(gensym(:PrivateWorkerEntry))
            Core.eval(owner, :(include(path) = Base.include(@__MODULE__, path)))
            Core.eval(owner, :(const ARGS = [$input, $output]))
            Base.include(owner, joinpath(@__DIR__, "..", "src", entry))
            result = TOML.parsefile(output)
            @test result["status"] == "invalid"
            @test result["failure"]["callback_phase"] == phase
            @test result["failure"]["cause_type"] == "ErrorException"
            @test result["correctness"] == (phase in ("operation", "synchronize", "verify") ? "failed" : "not_checked")
            @test !occursin(canary, read(output, String))
            Sys.isunix() && @test stat(output).mode & 0o077 == 0
        end
    end
end
