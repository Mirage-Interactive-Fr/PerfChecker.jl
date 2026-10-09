using Test
using PerfChecker
using PerfCheckerTachikoma
import Tachikoma as T

const MEASURED_EVIDENCE = Ref{RunBundle}()

function draw_model(model, width = 80, height = 24)
    backend = T.TestBackend(width, height)
    frame = T.Frame(backend.buf, T.Rect(1, 1, width, height),
        T.GraphicsRegion[], T.PixelSnapshot[])
    T.view(model, frame)
    return backend
end

function await_model(model; timeout = 180)
    @test timedwait(
        () -> begin
            refresh!(model)
            model.job === nothing && model.plot_task === nothing
        end, timeout) == :ok
    return model
end

@testset "Terminal selection and real owned suite jobs" begin
    mktempdir() do directory
        source = joinpath(directory, "TerminalFixture")
        environment = joinpath(directory, "environment")
        mkpath(environment)
        write(joinpath(environment, "Project.toml"), "[deps]\n")
        mkpath(joinpath(source, "src"))
        write(joinpath(source, "Project.toml"), """
name = "TerminalFixture"
uuid = "2b08fe8e-1688-4f73-9a90-c3d52cf113fd"
version = "0.1.0"
""")
        module_file = joinpath(source, "src", "TerminalFixture.jl")
        write(module_file, """
__precompile__(false)
module TerminalFixture
const sink = Ref{Vector{Int}}()
Base.@noinline allocate() = (sink[] = copy(collect(1:17)))
end
""")
        preserved = module_file * ".987654321.mem"
        original = "pre-existing allocation evidence\r\n"
        write(preserved, original)
        journal = joinpath(directory, "workers")
        marker = joinpath(directory, "measuring")
        fast = joinpath(source, "fast.jl")
        slow = joinpath(source, "slow.jl")
        setup = """
using TerminalFixture
function perf_setup()
    if Sys.islinux()
        actual = strip(only(filter(line -> startswith(line, "Cpus_allowed_list:"),
            readlines("/proc/self/status"))))
        @assert actual == d[:expected_affinity]
    end
    open(d[:journal], "a") do io
        println(io, getpid(), '\t', dirname(Base.active_project()))
    end
    return nothing
end
"""
        write(fast, setup * "perf_workload(_) = TerminalFixture.allocate()\n")
        write(slow, setup * """
function perf_workload(_)
    TerminalFixture.allocate()
    write(d[:marker], string(getpid()))
    sleep(120)
end
""")
        options = Dict{Symbol, Any}(:repeat => true, :quiet => true,
            :targets => ["TerminalFixture"], :journal => journal, :marker => marker)
        if Sys.islinux()
            options[:expected_affinity] = strip(only(filter(
                line -> startswith(line, "Cpus_allowed_list:"), readlines("/proc/self/status"))))
        end
        features = [FeatureSpec(:allocate; backend = :alloc, entrypoint = fast, options),
            FeatureSpec(:waiting; backend = :alloc, entrypoint = slow,
                options = merge(options, Dict(:repeat => false)))]
        package = PackageSuite("TerminalFixture"; source,
            worker_environment = environment, versions = VersionNumber[], features)
        plan = plan_suite(SoftwareSuite(:terminal_fixture, [package]))
        model = tui_model(plan)
        @test model.job === nothing
        @test !isfile(journal)
        @test length(model.rows) == 2
        @test model.selected == [true, true]
        @test T.find_text(draw_model(model), "TerminalFixture") !== nothing
        @test T.find_text(draw_model(model, 40, 12), "PerfChecker") !== nothing
        T.update!(model, T.KeyEvent(:down))
        T.update!(model, T.KeyEvent(' '))
        @test model.selected == [true, false]
        @test model.cursor == 2
        @test T.find_text(draw_model(model), "[ ] TerminalFixture / waiting") !== nothing
        try
            T.update!(model, T.KeyEvent('r'))
            job = model.job
            @test job isa SuiteJob
            @test planned_run_id(only(job.plan.runs)) == planned_run_id(plan.runs[1])
            T.update!(model, T.KeyEvent('r'))
            @test model.job === job
            await_model(model)
            @test model.result isa SoftwareSuiteResult
            @assert only(model.result.runs).status===:pass only(model.result.runs).message
            @test suite_passed(model.result)
            @test length(model.result.runs) == 1
            @test model.pane === :results
            @test T.find_text(draw_model(model), "pass") !== nothing
            workers = split.(readlines(journal), '\t')
            @test length(workers) == 1
            @test !ispath(only(workers)[2])
            Sys.islinux() && @test !ispath("/proc/" * only(workers)[1])
            @test read(preserved, String) == original
            @test sort(PerfChecker.find_malloc_files([source])) == [preserved]
            @test !isempty(model.catalog)
            MEASURED_EVIDENCE[] = model.bundle
            saved = tui_model(model.bundle)
            T.update!(saved, T.KeyEvent('r'))
            @test saved.job === nothing
            T.update!(saved, T.KeyEvent('p'))
            await_model(saved)
            @test !isempty(saved.plot_text)
            @test saved.pixels === nothing
            @test saved.pane === :plots
            canonical = performance_plot(saved.bundle, first(saved.catalog)["id"])
            @test canonical.encoding["y"] == "bytes"
            @test canonical.options["unit"] == "By"
            @test saved.plot_label == "Allocated bytes (By)"
            @test T.find_text(draw_model(saved), "PerfChecker") !== nothing
            for (width, height) in ((40, 12), (80, 24))
                draw_model(saved, width, height)
                T.pre_render!(saved)
                await_model(saved)
                backend = draw_model(saved, width, height)
                lines = split(saved.plot_text, '\n')
                @test saved.plotted_viewport == (width, height)
                @test saved.pan[1] == max(0, maximum(textwidth.(lines)) - width)
                @test length(lines) <= height - 5
                # Compare every rendered graph row, including its axes, with
                # the complete UnicodePlots output: no wrap or lost bottom.
                for (index, line) in enumerate(lines)
                    chars = collect(line)
                    @test all(char -> textwidth(char) == 1, chars)
                    visible = join(chars[min(saved.pan[1] + 1, length(chars) + 1):end])
                    @test rstrip(T.row_text(backend, index + 2)) == rstrip(visible)
                end
                @test any(
                    row -> occursin('┐', row), T.row_text.(Ref(backend), 3:(height - 3)))
                @test any(
                    row -> occursin('┘', row), T.row_text.(Ref(backend), 3:(height - 3)))
                @test T.find_text(backend, "0:reset") !== nothing
                @test T.find_text(backend, "Q") !== nothing
                @test T.row_text(backend, height - 2) == rpad("Allocated bytes (By)", width)
                if haskey(ENV, "PERFCHECKER_TACHIKOMA_CAPTURES")
                    captures = ENV["PERFCHECKER_TACHIKOMA_CAPTURES"]
                    @assert isabspath(captures) &&
                            startswith(captures, tempdir() * Base.Filesystem.path_separator)
                    mkpath(captures)
                    T.export_svg(
                        joinpath(captures, "plot-$width-$height.svg"), width, height,
                        [copy(backend.buf.content)], [0.0])
                end
            end
            # Unusually long labels can still be inspected by panning without
            # remeasurement or wrapping the graph itself.
            saved.plot_text = "long label " * "x"^100 * "\n" * join(string.(1:40), '\n')
            T.update!(saved, T.KeyEvent('l'))
            T.update!(saved, T.KeyEvent(:down))
            @test saved.pan == (2, 1)
            T.update!(saved, T.KeyEvent('0'))
            @test saved.pan == (0, 0)
            @test saved.job === nothing
            close!(saved)

            T.update!(model, T.KeyEvent(:tab))
            T.update!(model, T.KeyEvent(:up))
            T.update!(model, T.KeyEvent(' '))
            T.update!(model, T.KeyEvent(:down))
            T.update!(model, T.KeyEvent(' '))
            @test model.selected == [false, true]
            T.update!(model, T.KeyEvent('r'))
            @test timedwait(() -> isfile(marker) || istaskdone(model.job.task), 180) == :ok
            @test isfile(marker)
            cancelled = model.job
            pid = parse(Int, read(marker, String))
            @test suite_job_status(cancelled) === :running
            @test T.find_text(draw_model(model), "running") !== nothing
            T.update!(model, T.KeyEvent('c'))
            @test !T.should_quit(model)
            T.update!(model, T.KeyEvent('q'))
            @test !T.should_quit(model)
            await_model(model; timeout = 45)
            @test suite_job_status(cancelled) === :cancelled
            @test T.should_quit(model)
            @test occursin("cleanup finished", model.message)
            workers = split.(readlines(journal), '\t')
            @test length(workers) == 2
            @test all(row -> !ispath(row[2]), workers)
            Sys.islinux() && @test !ispath("/proc/$pid")
            @test read(preserved, String) == original
            @test sort(PerfChecker.find_malloc_files([source])) == [preserved]
            close!(model)
            close!(model)

            output = IOBuffer()
            isolated = tui_model(plan)
            tui(isolated; io = output, input = IOBuffer("q"),
                tty_size = (rows = 12, cols = 40),
                default_bindings = false, fps = 10)
            stream = String(take!(output))
            @test occursin("\e[?1049h", stream)
            @test occursin("\e[?1049l", stream)
            @test isolated.job === nothing
            @test T.should_quit(isolated)
        finally
            close!(model)
        end
    end
end

@testset "Canonical metric labels preserve units and unknowns" begin
    plot(options; encoding = Dict{String, Any}()) = PerfChecker.PerformancePlot(
        "label-test", :distribution, "Misleading allocations title", "",
        encoding, Dict{String, Any}[], options)
    label = PerfCheckerTachikoma._plot_measurement
    @test label(plot(Dict{String, Any}("metric" => "julia.wall.time", "unit" => "ns"))) ==
          "julia.wall.time (ns)"
    @test label(plot(Dict{String, Any}(
        "metric" => "julia.alloc.count", "unit" => "count"))) ==
          "julia.alloc.count (count)"
    @test label(plot(Dict{String, Any}())) == "Unknown measure (unknown unit)"
    @test label(plot(Dict{String, Any}("unit" => ""))) == "Unknown measure (unknown unit)"
    @test label(plot(Dict{String, Any}("unit" => "");
        encoding = Dict{String, Any}("x" => "bytes", "y" => "time"))) ==
          "Allocated bytes / time (unknown unit)"
    @test label(plot(Dict{String, Any}("unit" => "By");
        encoding = Dict{String, Any}("y" => "bytes"))) == "Allocated bytes (By)"
end

if get(ENV, "PERFCHECKER_TACHIKOMA_TEST_PIXELS", "0") == "1"
    using CairoMakie, PerfCheckerMakie
    CairoMakie.activate!(px_per_unit = 1)
    @testset "Actual Makie evidence raster and Tachikoma Kitty encoding" begin
        bundle = MEASURED_EVIDENCE[]
        entry = first(plot_catalog(bundle))
        pixels = plot_pixels(bundle, entry["id"]; size = (360, 220))
        @test (pixels.width, pixels.height) == (360, 220)
        @test length(pixels.rgba) == 4 * 360 * 220
        @test length(unique(eachcol(reshape(pixels.rgba, 4, :)))) > 16
        @test all(==(255), pixels.rgba[4:4:end])
        @test_throws ArgumentError plot_pixels(bundle, entry["id"]; size = (0, 220))
        model = tui_model(bundle)
        model.pixel_capable = true
        T.update!(model, T.KeyEvent('p'))
        await_model(model)
        @test model.pixels !== nothing
        @test model.plot_task === nothing
        @test model.job === nothing
        protocol = T.GRAPHICS_PROTOCOL[]
        shared_memory = T._KITTY_SHM_AVAILABLE[]
        try
            # Exercise the real Kitty encoder in a virtual frame, not a claim
            # that this test process has a Kitty-compatible physical terminal.
            T.GRAPHICS_PROTOCOL[] = T.gfx_kitty
            T._KITTY_SHM_AVAILABLE[] = false
            backend = T.TestBackend(80, 24)
            frame = T.Frame(backend.buf, T.Rect(1, 1, 80, 24),
                T.GraphicsRegion[], T.PixelSnapshot[])
            T.view(model, frame)
            @test !isempty(frame.gfx_regions)
            @test any(region -> occursin("\e_G", String(region.data)), frame.gfx_regions)
            @test T.find_text(backend, "PerfChecker") !== nothing
        finally
            T.GRAPHICS_PROTOCOL[] = protocol
            T._KITTY_SHM_AVAILABLE[] = shared_memory
            close!(model)
        end
    end
end
