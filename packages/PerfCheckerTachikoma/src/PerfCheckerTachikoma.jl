"""
An optional terminal interface for existing PerfChecker suite jobs and evidence.
Load `PerfCheckerTachikoma` explicitly; it does not add a terminal dependency to
PerfChecker itself. Constructing a model starts no measurement or terminal.
"""
module PerfCheckerTachikoma

using PerfChecker
using UnicodePlots
import Tachikoma as T

export SuiteTUI, tui_model, tui, refresh!, close!, plot_pixels

"""
    plot_pixels(bundle::RunBundle, plot_id; size=(800, 480))

Return `(rgba, width, height)` for a plot of saved evidence, without rerunning a
workload. Load `PerfCheckerMakie` and a Makie backend such as `CairoMakie` to
enable this optional method. RGBA bytes are in Tachikoma's row-major order.
The terminal interface uses UnicodePlots when pixel graphics are unavailable.
`size` is the Makie scene size; returned dimensions include the active backend's
pixel scale and always describe the actual RGBA buffer.

```julia
using PerfChecker, PerfCheckerTachikoma, PerfCheckerMakie, CairoMakie
bundle = read_run_bundle("reports/run")
entry = first(plot_catalog(bundle))
pixels = plot_pixels(bundle, entry["id"])
```
"""
function plot_pixels end

"""
    SuiteTUI

Tachikoma model returned by [`tui_model`](@ref). Selection contains canonical
planned-run identities, and the single active job remains owned until cleanup
finishes. Use `Tachikoma.update!` for events, [`refresh!`](@ref) for nonblocking
polling and [`close!`](@ref) to cancel and await a job outside an app loop.
"""
mutable struct SuiteTUI <: T.Model
    plan::Union{Nothing, SuitePlan}
    rows::Vector{Dict{String, Any}}
    selected::BitVector
    cursor::Int
    pane::Symbol
    job::Union{Nothing, SuiteJob}
    overrides::Dict{Symbol, Any}
    result::Union{Nothing, SoftwareSuiteResult}
    bundle::Union{Nothing, RunBundle}
    catalog::Vector{Dict{String, Any}}
    progress::Dict{String, Any}
    message::String
    quit_requested::Bool
    plot_index::Int
    plot_task::Union{Nothing, Task}
    plot_text::String
    plot_label::String
    pixels::Any
    pixel_capable::Bool
    viewport::Tuple{Int, Int}
    plotted_viewport::Tuple{Int, Int}
    pan::Tuple{Int, Int}
end

"""
    tui_model(plan::SuitePlan; overrides=Dict{Symbol,Any}())
    tui_model(suite::SoftwareSuite; profile=:quick, overrides=Dict{Symbol,Any}())
    tui_model(result::SoftwareSuiteResult)
    tui_model(bundle::RunBundle)

Prepare a terminal model without opening the terminal or starting workers.
Plan rows start selected in their declared order; Space toggles the current row
and R launches only the selected IDs using `launch_suite`. Result/bundle models
are read-only and cannot launch a new measurement. Only completed evidence can
be plotted. No report file is written automatically.

```julia
using PerfChecker, PerfCheckerTachikoma
suite = load_software_suite("perf/suite.jl")
model = tui_model(plan_suite(suite))
saved = tui_model(read_run_bundle("reports/run"))
```
"""
function tui_model(plan::SuitePlan; overrides::AbstractDict = Dict{Symbol, Any}())
    rows = Dict{String, Any}.(suite_plan_dict(plan)["runs"])
    return SuiteTUI(plan, rows, trues(length(rows)), 1, :selection, nothing,
        Dict{Symbol, Any}(overrides), nothing, nothing, Dict{String, Any}[],
        Dict{String, Any}(), "Space selects; R runs the selection", false,
        1, nothing, "", "Unknown measure (unknown unit)",
        nothing, false, (80, 24), (0, 0), (0, 0))
end

function tui_model(suite::SoftwareSuite; profile::Symbol = :quick, kwargs...)
    tui_model(plan_suite(suite; profile); kwargs...)
end

function _evidence_model(bundle::RunBundle, result = nothing)
    model = SuiteTUI(nothing, Dict{String, Any}[], BitVector(), 1, :results, nothing,
        Dict{Symbol, Any}(), result, bundle, Dict{String, Any}.(plot_catalog(bundle)),
        Dict{String, Any}(), "Saved evidence; no measurement launched", false,
        1, nothing, "", "Unknown measure (unknown unit)",
        nothing, false, (80, 24), (0, 0), (0, 0))
    return model
end

tui_model(bundle::RunBundle) = _evidence_model(bundle)
# Same in-memory conversion used by the Makie companion; it writes no reports.
function tui_model(result::SoftwareSuiteResult)
    _evidence_model(PerfChecker._suite_run_bundle(result), result)
end

function _active(model)
    model.job !== nothing &&
        suite_job_status(model.job) in (:queued, :running, :cancelling)
end

"""
    refresh!(model::SuiteTUI)

Poll the existing job and pending plot without waiting. Completed jobs are read
with `wait_suite(strict=false)` only after their controller task has finished;
feature failures remain visible. Rendering never starts or waits for a worker.
"""
function refresh!(model::SuiteTUI)
    job = model.job
    if job !== nothing
        model.progress = suite_job_progress(job)
        if istaskdone(job.task)
            try
                result = wait_suite(job; strict = false)
                model.result = result
                model.bundle = PerfChecker._suite_run_bundle(result)
                model.catalog = Dict{String, Any}.(plot_catalog(model.bundle))
                model.plot_index = 1
                model.message = "Finished: $(suite_verdict(result))"
                model.pane = :results
            catch error
                model.message = error isa InterruptException ?
                                "Cancelled; cleanup finished" :
                                "Failed: $(sprint(showerror, error))"
            end
            model.job = nothing
        end
    end
    if model.plot_task !== nothing && istaskdone(model.plot_task)
        try
            rendered = fetch(model.plot_task)
            model.plot_text, model.pixels = rendered.text, rendered.pixels
            model.plot_label = rendered.label
            model.pan = (
                max(0,
                    maximum(textwidth.(split(model.plot_text, '\n'))) -
                    model.viewport[1]),
                0)
            model.message = rendered.message
        catch error
            model.message = "Plot failed: $(sprint(showerror, error))"
        end
        model.plot_task = nothing
    end
    return model
end

function _run!(model)
    _active(model) && return
    model.plot_task === nothing || return
    model.plan === nothing && return
    ids = [planned_run_id(model.plan.runs[i])
           for i in eachindex(model.selected)
           if model.selected[i]]
    if isempty(ids)
        model.message = "Select at least one run with Space"
        return
    end
    model.result = nothing
    model.bundle = nothing
    empty!(model.catalog)
    model.plot_index = 1
    model.plot_text = ""
    model.pixels = nothing
    model.job = launch_suite(
        select_suite_plan(model.plan, ids); overrides = model.overrides)
    model.message = "Running selection; C cancels"
end

function _plot_measurement(plot::PerfChecker.PerformancePlot)
    # These fields and units come from the canonical model, never its title.
    # Percentage views follow terminal_plot's documented rendering semantics.
    get(plot.encoding, "y", "") == "relative_delta" && return "Relative change (%)"
    get(plot.encoding, "label", "") == "percentage" && return "Allocation share (%)"
    get(plot.encoding, "x", "") == "percentage" && return "Inclusive share (%)"
    unit = string(get(plot.options, "unit", ""))
    isempty(unit) && (unit = "unknown unit")
    if get(plot.encoding, "x", "") == "bytes" && get(plot.encoding, "y", "") == "time"
        return "Allocated bytes / time ($unit)"
    end
    measure = get(plot.options, "metric", get(plot.options, "value_label", ""))
    if any(value -> value == "bytes", values(plot.encoding))
        measure = "Allocated bytes"
    elseif get(plot.encoding, "y", "") == "ratio"
        measure = "Relative to " * string(get(plot.options, "reference_version", "unknown"))
    end
    isempty(string(measure)) && (measure = "Unknown measure")
    return "$measure ($unit)"
end

function _terminal_text(model::PerfChecker.PerformancePlot, viewport)
    available_width, available_height = viewport[1], max(1, viewport[2] - 5)
    width, height = max(1, available_width - 20), max(1, available_height - 5)
    text = ""
    for _ in 1:8
        plot = terminal_plot(model; width, height)
        # The full evidence title is shown separately, so it does not expand
        # the graph beyond the terminal's plotting area.
        UnicodePlots.title!(plot, "")
        text = rstrip(sprint(show, MIME"text/plain"(), plot;
            context = (
                :color => false, :displaysize => (available_height, available_width))))
        lines = split(text, '\n')
        excess_width = max(0, maximum(textwidth.(lines)) - available_width)
        excess_height = max(0, length(lines) - available_height)
        excess_width == 0 && excess_height == 0 && break
        smaller = (max(1, width - excess_width), max(1, height - excess_height))
        smaller == (width, height) && break
        width, height = smaller
    end
    return text
end

function _plot!(model)
    model.bundle === nothing && return
    isempty(model.catalog) && (model.message = "No plottable evidence"; return)
    model.plot_task === nothing || return
    model.pane = :plots
    bundle, entry = model.bundle, model.catalog[model.plot_index]
    pixel_capable = model.pixel_capable
    viewport = model.viewport
    model.plotted_viewport = viewport
    model.pan = (0, 0)
    model.plot_text = "Preparing plot from saved evidence…"
    model.pixels = nothing
    model.plot_task = Threads.@spawn begin
        canonical = performance_plot(bundle, entry["id"])
        text = _terminal_text(canonical, viewport)
        pixels, message = nothing, "$(entry["title"]) — saved evidence"
        if pixel_capable && applicable(plot_pixels, bundle, entry["id"])
            try
                pixels = plot_pixels(bundle, entry["id"])
            catch error
                message *= "; pixel renderer unavailable: $(sprint(showerror, error))"
            end
        end
        (text = text, pixels = pixels, message = message,
            label = _plot_measurement(canonical))
    end
end

function T.update!(model::SuiteTUI, event::T.KeyEvent)
    refresh!(model)
    key, char = event.key, event.char
    if key in (:escape, :ctrl_c) || (key === :char && char === 'q')
        model.quit_requested = true
        _active(model) && cancel_suite!(model.job)
        model.message = _active(model) ? "Closing after worker cleanup…" : "Closing"
    elseif key === :char && char === 'c'
        if _active(model)
            cancel_suite!(model.job)
            model.message = "Cancelling; waiting for worker cleanup…"
        end
    elseif key === :tab
        model.pane = model.pane === :selection ? :results : :selection
    elseif key === :char && char === 'r'
        _run!(model)
    elseif key === :char && char === 'p'
        _plot!(model)
    elseif model.pane === :plots && (key in (:up, :down) ||
            (key === :char && char in ('h', 'l', '0')))
        lines = split(model.plot_text, '\n')
        max_x = max(0, maximum(textwidth.(lines)) - model.viewport[1])
        max_y = max(0, length(lines) - max(1, model.viewport[2] - 5))
        x, y = model.pan
        key === :up && (y = max(0, y - 1))
        key === :down && (y = min(max_y, y + 1))
        char === 'h' && (x = max(0, x - 2))
        char === 'l' && (x = min(max_x, x + 2))
        char === '0' && ((x, y) = (0, 0))
        model.pan = (x, y)
    elseif model.pane === :plots && key in (:left, :right) && !isempty(model.catalog) &&
           model.plot_task === nothing
        model.plot_index = mod1(
            model.plot_index + (key === :right ? 1 : -1), length(model.catalog))
        _plot!(model)
    elseif model.pane === :selection && !_active(model)
        key === :up && (model.cursor = max(1, model.cursor - 1))
        key === :down && (model.cursor = min(length(model.rows), model.cursor + 1))
        if key === :char && char === ' ' && !isempty(model.selected)
            model.selected[model.cursor] = !model.selected[model.cursor]
        end
    end
    return nothing
end

function T.pre_render!(model::SuiteTUI)
    refresh!(model)
    if model.pane === :plots && model.plot_task === nothing &&
       model.plotted_viewport != model.viewport && !model.quit_requested
        _plot!(model)
    end
    return nothing
end
function T.should_quit(model::SuiteTUI)
    model.quit_requested && !_active(model) &&
        (model.plot_task === nothing || istaskdone(model.plot_task))
end
function T.init!(model::SuiteTUI, terminal::T.Terminal)
    model.pixel_capable = terminal.graphics_protocol !== T.gfx_none
    model.viewport = (terminal.size.width, terminal.size.height)
    return nothing
end

function _plot_lines(model, area)
    lines = split(model.plot_text, '\n')
    x, y = model.pan
    visible = String[]
    for line in lines[min(y + 1, length(lines)):min(y + area.height, length(lines))]
        column, text = 0, IOBuffer()
        for char in line
            next = column + textwidth(char)
            column >= x && next <= x + area.width && print(text, char)
            column = next
        end
        push!(visible, String(take!(text)))
    end
    return visible
end

function _selection_lines(model, height)
    isempty(model.rows) && return ["No execution plan (read-only evidence)"]
    first_row = max(1, model.cursor - max(height - 2, 0))
    return [string(i == model.cursor ? "> " : "  ", model.selected[i] ? "[x] " : "[ ] ",
                get(model.rows[i], "package", ""), " / ", get(model.rows[i], "feature", ""),
                " / ", get(model.rows[i], "backend", ""), " / ",
                get(model.rows[i], "version", ""))
            for i in first_row:min(length(model.rows), first_row + max(height - 1, 0))]
end

function _result_lines(model)
    if model.result !== nothing
        return [string(run.status, "  ", run.planned.package_suite.package, " / ",
                    run.planned.feature.id, " / ", run.planned.target.label,
                    isempty(run.message) ? "" : " — " * run.message)
                for run in model.result.runs]
    elseif model.bundle !== nothing
        return ["Evidence state: $(get(model.bundle.manifest, "state", "unknown"))",
            "Observations: $(length(model.bundle.observations))",
            "Diagnostics: $(length(model.bundle.diagnostics))",
            "Plots: $(length(model.catalog))", "P displays saved evidence; arrows change plot"]
    end
    return ["No completed evidence yet"]
end

function T.view(model::SuiteTUI, frame::T.Frame)
    area, buffer = frame.area, frame.buffer
    area.width > 0 && area.height > 0 || return
    rows = T.split_layout(T.Layout(T.Vertical, [T.Fixed(2), T.Fill(), T.Fixed(3)]), area)
    # Remember geometry only. Resize plotting is scheduled by pre_render!,
    # outside this render callback and without launching a measurement.
    model.viewport = (area.width, area.height)
    state = _active(model) ? string(suite_job_status(model.job)) : "idle"
    selected_count = count(identity, model.selected)
    progress = isempty(model.progress) ? "" :
               " $(get(model.progress, "completed", 0))/$(get(model.progress, "total", 0))"
    T.render(
        T.Paragraph("PerfChecker | $(model.pane) | $state$progress | $selected_count selected"),
        rows[1],
        buffer)
    if model.pane === :plots && !(model.pixel_capable && model.pixels !== nothing)
        graph = split(model.plot_text, '\n')
        dimensions = (maximum(textwidth.(graph)), length(graph))
        T.render(
            T.Paragraph("pan $(model.pan[1]),$(model.pan[2]) | $(dimensions[1])×$(dimensions[2]) cells"),
            T.Rect(area.x, area.y + 1, area.width, min(1, area.height - 1)), buffer)
    end
    content = model.pane === :selection ? _selection_lines(model, rows[2].height) :
              model.pane === :plots ?
              (model.pixel_capable && model.pixels !== nothing ?
               String[] : _plot_lines(model, rows[2])) : _result_lines(model)
    T.render(
        T.Paragraph(join(content, '\n');
            wrap = model.pane === :plots ? T.no_wrap : T.word_wrap),
        rows[2],
        buffer)
    if model.pane === :plots && model.pixel_capable && model.pixels !== nothing
        image = model.pixels
        T.render_rgba!(frame, image.rgba, image.width, image.height, rows[2])
    end
    controls = model.pane === :plots ? "↑↓/h l:pan ←→:plot 0:reset Tab Q" :
               "↑↓ Space R:run C:cancel Tab P Q"
    footer = rows[3]
    label_rows = model.pane === :plots ? min(1, max(0, footer.height - 1)) : 0
    if label_rows > 0
        T.render(T.Paragraph(model.plot_label),
            T.Rect(footer.x, footer.y, footer.width, label_rows), buffer)
    end
    T.render(T.Paragraph(model.message; wrap = T.word_wrap),
        T.Rect(footer.x, footer.y + label_rows, footer.width,
            max(0, footer.height - 1 - label_rows)), buffer)
    T.render(T.Paragraph(controls),
        T.Rect(footer.x, footer.y + max(0, footer.height - 1), footer.width,
            min(1, footer.height)), buffer)
    return nothing
end

"""
    close!(model::SuiteTUI)

Request cancellation and wait for the owned measurement job and pending plot.
Only `InterruptException` (successful cancellation) is suppressed; cleanup or
orchestration failures propagate. Repeated closes are safe. Call this from
`finally` when embedding a model outside the terminal application.

```julia
model = tui_model(plan)
try
    Tachikoma.update!(model, Tachikoma.KeyEvent('r'))
    refresh!(model)
finally
    close!(model)
end
```
"""
function close!(model::SuiteTUI)
    job = model.job
    if job !== nothing
        _active(model) && cancel_suite!(job)
        try
            wait_suite(job; strict = false)
        catch error
            error isa InterruptException || rethrow()
        finally
            model.job = nothing
        end
    end
    model.plot_task === nothing || wait(model.plot_task)
    model.plot_task = nothing
    model.quit_requested = true
    return model
end

T.cleanup!(model::SuiteTUI) = close!(model)

"""
    tui(input; fps=20, kwargs...)

Open Tachikoma for a `SuiteTUI`, suite, plan or saved evidence. R starts the
selected suite; C cancels; Q/Escape waits for owned worker cleanup before exit.
Pass app keywords such as `io`, `input` and `tty_size` to embed the app in an
isolated terminal. Model construction options belong to `tui_model`.

```julia
using PerfChecker, PerfCheckerTachikoma
model = tui_model(plan_suite(load_software_suite("perf/suite.jl")))
tui(model)                         # explicit interactive terminal session
tui(read_run_bundle("reports/run")) # consult evidence without measuring
```
"""
function tui(input; fps::Real = 20, kwargs...)
    model = input isa SuiteTUI ? input : tui_model(input)
    try
        T.app(model; fps, kwargs...)
    finally
        close!(model)
    end
    return model
end

end
