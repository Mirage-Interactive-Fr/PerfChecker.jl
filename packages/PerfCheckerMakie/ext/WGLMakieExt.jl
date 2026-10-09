module WGLMakieExt

using Bonito
using Makie
using PerfChecker, PerfCheckerMakie
import TestItems: @testitem
using WGLMakie

const RENDER_LOCK = ReentrantLock()
const HTML_CACHE = Dict{String, String}()
const MAX_CACHE_ENTRIES = 64

function _flame_plot_html(plot::PerfChecker.PerformancePlot)
    colors = PerfCheckerMakie._flame_colors(plot)
    function css_color(color)
        "rgb($(round(Int, 255 * color.r)), $(round(Int, 255 * color.g)), $(round(Int, 255 * color.b)))"
    end
    css_colors = css_color.(colors)
    payload = Dict("model" => PerfChecker.performance_plot_dict(plot),
        "colors" => css_colors,
        "text_colors" => css_color.([PerfCheckerMakie._flame_label_color(
                                         color, Makie.RGBf(1, 1, 1)) for color in colors]),
        "status_colors" => Dict(status => css_color(color)
        for (status, color) in PerfCheckerMakie._FLAME_STATUS_COLORS),
        "collector" => PerfCheckerMakie._model_collector(plot))
    json = replace(PerfChecker._canonical_json(payload), "</" => "<\\/")
    return replace(read(joinpath(@__DIR__, "../src/assets/flame.html"), String),
        "__PERFCHECKER_FLAME_PAYLOAD__" => json)
end

"Attach recorded-row inspection to native marks, distinguishing mesh vertices from heatmap texture cells."
function _offline_point_controls(session, figure, source_plot)
    source_plot.kind in (:distribution, :version_series, :version_delta,
        :time_allocation_tradeoff, :allocation_lines, :allocation_files,
        :allocation_heatmap, :allocation_pie) || return nothing
    # Match the finite records consumed by the existing Makie recipes exactly.
    plot = PerfCheckerMakie._finite_plot(
        source_plot; include_zero_pie = source_plot.kind === :allocation_pie)
    isempty(plot.data) && return nothing
    axis = only(filter(item -> item isa Makie.Axis, figure.content))
    data = plot.data
    if plot.kind === :allocation_pie && all(item -> item["bytes"] == 0, data)
        labels = ["$(item["version"]) · $(item["label"]) · $(item["bytes"]) $(plot.options["unit"]) · no visible sector"
                  for item in data]
        selector = Bonito.DOM.input(;
            type = "number", min = 1, max = length(data), step = 1,
            value = 1, id = "point-index", var"aria-label" = "Recorded point index",
            var"data-readout-only" = "true", style = "width:7rem")
        readout = Bonito.DOM.output("Point 1: $(first(labels))"; id = "point-readout",
            var"aria-live" = "polite", var"aria-busy" = "false")
        Bonito.evaljs(session,
            js"""(() => {
  const input=$(selector), output=$(readout), labels=$(labels);
  input.addEventListener('input',()=>{
    const index=Number(input.value),valid=Number.isInteger(index)&&index>=1&&index<=labels.length;
    input.setAttribute('aria-invalid',String(!valid));
    output.textContent=valid?'Point '+index+': '+labels[index-1]:'Choose a point from 1 to '+labels.length;
  });
})();""")
        return Bonito.DOM.div(
            Bonito.DOM.label("Recorded point ", selector, " of $(length(data))"), readout;
            id = "point-controls", style = Bonito.Styles(
                "display" => "flex", "gap" => "1rem",
                "flex-wrap" => "wrap", "padding" => "0.8rem")),
        Bonito.DOM.span()
    end
    vertex_ranges = Vector{Int}[]
    sector_triangles = Vector{Int}[]
    cell_indices = Int[]
    cell_shape = Int[]
    if plot.kind === :version_delta
        positions = [Point2f(index, 100 * item["relative_delta"])
                     for (index, item) in pairs(data)]
        points = [scatter!(axis, positions; color = :white, markersize = 7,
            strokecolor = PerfCheckerMakie._PLOT_PALETTE[1], strokewidth = 1.5,
            depth_shift = -0.001)]
        labels = ["$(item["baseline_version"]) → $(item["candidate_version"]) · change: $(100 * item["relative_delta"])% · $(get(item, "status", "unknown"))"
                  for item in data]
    elseif plot.kind in (:allocation_lines, :allocation_files)
        recipe = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
        rectangles = only(filter(item -> item isa Makie.Poly, recipe.plots))[1][]
        points = filter(item -> item isa Makie.Mesh, Makie.collect_atomic_plots([recipe]))
        source = only(points)
        vertices = Makie.GeometryBasics.coordinates(source[1][])
        length(vertices) == 4length(data) == 4length(rectangles) ||
            error("Native allocation bars do not retain four vertices per recorded row")
        positions = Point2f[]
        for (index, rectangle) in pairs(rectangles)
            indices = (4index - 3):(4index)
            corners = vertices[indices]
            lower = Point2f(minimum(first, corners), minimum(last, corners))
            upper = Point2f(maximum(first, corners), maximum(last, corners))
            isapprox(lower, Point2f(minimum(rectangle))) &&
                isapprox(upper, Point2f(maximum(rectangle))) ||
                error("Native allocation mesh order differs from its recorded rectangles")
            push!(positions, (lower + upper) / 2)
            push!(vertex_ranges, collect(indices .- 1))
        end
        labels = ["$(item["version"]) · $(item["file"])$(plot.kind === :allocation_lines ? ":$(item["line"])" : "") · $(item["bytes"]) $(plot.options["unit"])"
                  for item in data]
    elseif plot.kind === :allocation_pie
        recipe = only(filter(item -> item isa Makie.Pie, axis.scene.plots))
        inspection = PerfCheckerMakie._allocation_pie_inspection(recipe, data)
        length(inspection.positions) == length(data) ||
            error("Native allocation pie sectors differ from its recorded rows")
        points = [inspection.source]
        positions, vertex_ranges, sector_triangles = inspection.positions,
        inspection.ranges, inspection.triangles
        labels = ["$(item["version"]) · $(item["label"]) · $(item["bytes"]) $(plot.options["unit"]) · $(item["percentage"])%" *
                  (isempty(sector_triangles[index]) ? " · no visible sector" : "")
                  for (index, item) in pairs(data)]
    elseif plot.kind === :allocation_heatmap
        recipe = only(filter(item -> item isa Makie.Heatmap, axis.scene.plots))
        points = [recipe]
        versions, sites = String.(plot.options["versions"]), String.(plot.options["labels"])
        version_index = Dict(version => index for (index, version) in pairs(versions))
        site_index = Dict(site => index for (index, site) in pairs(sites))
        matrix = recipe[3][]
        size(matrix) == (length(versions), length(sites)) ||
            error("Native allocation heatmap dimensions differ from its recorded axes")
        axis.xscale[] === identity && axis.yscale[] === identity ||
            error("Offline heatmap inspection requires linear native cell coordinates")
        cell_shape = collect(size(matrix))
        x, y = recipe[1][], recipe[2][]
        xs = x isa Makie.EndPoints ? LinRange(first(x), last(x), size(matrix, 1) + 1) : x
        ys = y isa Makie.EndPoints ? LinRange(first(y), last(y), size(matrix, 2) + 1) : y
        length(xs) == size(matrix, 1) + 1 && length(ys) == size(matrix, 2) + 1 ||
            error("Native allocation heatmap does not expose its cell edges")
        all(isapprox.(xs, LinRange(first(xs), last(xs), length(xs)))) &&
            all(isapprox.(ys, LinRange(first(ys), last(ys), length(ys)))) ||
            error("Offline allocation heatmap inspection requires its uniform native grid")
        positions = Point2f[]
        for item in data
            ix = version_index[String(item["version"])]
            iy = site_index[String(item["label"])]
            matrix[ix, iy] == convert(eltype(matrix), item["bytes"]) ||
                error("Native allocation texture differs from its recorded cell")
            push!(cell_indices, (ix - 1) + (iy - 1) * length(versions))
            push!(positions, Point2f((xs[ix] + xs[ix + 1]) / 2, (ys[iy] + ys[iy + 1]) / 2))
        end
        labels = ["$(item["version"]) · $(item["label"]) · $(item["bytes"]) $(plot.options["unit"])"
                  for item in data]
    elseif plot.kind === :time_allocation_tradeoff
        recipe = only(filter(item -> item isa Makie.ScatterLines, axis.scene.plots))
        points = filter(
            item -> item isa Makie.Scatter, Makie.collect_atomic_plots([recipe]))
        positions = [Point2f(item["bytes"], item["time"]) for item in data]
        time_unit, allocation_unit = PerfChecker._tradeoff_plot_units(plot.options)
        labels = ["$(item["version"]) · $(item["bytes"]) $allocation_unit · $(item["time"]) $time_unit"
                  for item in data]
    else
        points = filter(item -> item isa Makie.Scatter, axis.scene.plots)
        versions = unique(String(item["version"]) for item in data)
        positions = [Point2f(
                         findfirst(==(String(item["version"])), versions), item["value"])
                     for item in data]
        labels = ["$(item["version"]) · $(item["value"]) $(plot.options["unit"])"
                  for item in data]
    end
    isempty(points) && return nothing
    selector = Bonito.DOM.input(; type = "number", min = 1, max = length(data),
        step = 1, value = 1, id = "point-index", var"aria-label" = "Recorded point index",
        style = "width:7rem")
    highlight = scatter!(axis, [first(positions)];
        color = PerfCheckerMakie._PLOT_PALETTE[2], markersize = 14,
        strokecolor = :white, strokewidth = 1.5, inspectable = true, depth_shift = -0.002)
    readout = Bonito.DOM.output("Point 1: $(first(labels))";
        id = "point-readout", var"aria-live" = "polite")
    Bonito.evaljs(session,
        js"""
(() => {
  const input = $(selector), output = $(readout), labels = $(labels), vertexRanges = $(vertex_ranges);
  const cells = $(cell_indices), shape = $(cell_shape), triangles = $(sector_triangles);
  if (vertexRanges.length) input.dataset.sourceVertices = JSON.stringify(vertexRanges.map(vertices => Array.from(vertices)));
  if (triangles.length) input.dataset.sourceTriangles = JSON.stringify(triangles.map(vertices => Array.from(vertices)));
  if (cells.length) input.dataset.sourceCells = JSON.stringify({indices:Array.from(cells), shape:Array.from(shape)});
  let latest = 0;
  input.addEventListener('input', () => {
    const token = ++latest, index = Number(input.value);
    document.querySelectorAll('.popup.show').forEach(popup => popup.classList.remove('show'));
    delete output.dataset.error;
    const valid = Number.isInteger(index) && index >= 1 && index <= labels.length;
    input.setAttribute('aria-invalid', String(!valid));
    if (!valid) { output.setAttribute('aria-busy', 'false'); output.textContent = 'Choose a point from 1 to ' + labels.length; return; }
    output.textContent = 'Point ' + index + ': ' + labels[index - 1];
    output.setAttribute('aria-busy', 'true');
    Promise.all([$(first(points)), $(highlight)]).then(([sources, targets]) => {
      if (token !== latest) return;
      input.dataset.sourcePlot = sources[0].plot_uuid;
      input.dataset.highlightPlot = targets[0].plot_uuid;
      const source = sources[0].geometry.attributes, target = targets[0].geometry.attributes;
      const sourceKey = ['wgl_positions', 'pos', 'offset', 'positions_transformed_f32c'].find(key => source[key]);
      const targetKey = ['wgl_positions', 'pos', 'offset', 'positions_transformed_f32c'].find(key => target[key]);
      if (!sourceKey || !targetKey) throw new Error('WGLMakie point positions are unavailable');
      const positions = source[sourceKey], selected = target[targetKey];
      const vertices = vertexRanges.length ? vertexRanges[index - 1] : [index - 1];
      for (let component = 0; component < selected.itemSize; component++) {
        if (triangles.length) {
          const triangle=triangles[index-1];
          selected.array[component]=triangle.length?Array.from(triangle,vertex=>component<positions.itemSize?positions.array[vertex*positions.itemSize+component]:0).reduce((sum,value)=>sum+value,0)/3:NaN;
        } else if (cells.length) {
          let lower=Infinity, upper=-Infinity;
          for(let vertex=0;vertex<positions.count;vertex++) {
            const value=component<positions.itemSize?positions.array[vertex*positions.itemSize+component]:0;
            lower=Math.min(lower,value);upper=Math.max(upper,value);
          }
          const cell=cells[index-1],fraction=component===0?((cell%shape[0])+.5)/shape[0]:component===1?(Math.floor(cell/shape[0])+.5)/shape[1]:.5;
          selected.array[component]=lower+(upper-lower)*fraction;
        } else {
          const values = Array.from(vertices, vertex => component < positions.itemSize ? positions.array[vertex * positions.itemSize + component] : 0);
          selected.array[component] = (Math.min(...values) + Math.max(...values)) / 2;
        }
      }
      selected.needsUpdate = true;
      input.dataset.appliedIndex = String(index);
      output.setAttribute('aria-busy', 'false');
    }).catch(error => {
      if (token !== latest) return;
      output.setAttribute('aria-busy', 'false');
      output.dataset.error = String(error.message || error);
      output.textContent = 'Point inspection unavailable: ' + output.dataset.error;
    });
  });
  input.dispatchEvent(new Event('input'));
})();
""")
    callback = js"""(mesh, index) => {
        const input = $(selector);
        if (mesh.plot_uuid === input.dataset.highlightPlot) {
            if (input.getAttribute('aria-invalid') === 'true' ||
                $(readout).getAttribute('aria-busy') !== 'false' || $(readout).dataset.error) {
                return 'Select a valid point and wait for its position to finish updating.';
            }
            index = Number(input.dataset.appliedIndex) - 1;
        }
        else if ($(vertex_ranges).length) {
            index = $(vertex_ranges).findIndex(vertices => vertices.includes(index));
        }
        else if ($(cell_indices).length) {
            index = $(cell_indices).indexOf(index);
        }
        const label = $(labels)[index];
        if (label === undefined) return '';
        return 'Point ' + (index + 1) + ': ' + label;
    }"""
    tooltip = WGLMakie.ToolTip(figure, callback; plots = [points; highlight])
    controls = Bonito.DOM.div(
        Bonito.DOM.label("Recorded point ", selector, " of $(length(data))"), readout;
        id = "point-controls",
        style = Bonito.Styles("display" => "flex", "gap" => "1rem",
            "flex-wrap" => "wrap", "padding" => "0.8rem", "font-family" => "sans-serif"))
    return controls, tooltip
end

"""
    performance_plot_html(plot; asset_directory=nothing, html_directory=nothing)

Render an interactive HTML document from a recorded plot. By default, the document
contains its assets and can be saved as a standalone file.

To share WGL assets between several documents, pass both `asset_directory` (the
directory where Bonito writes assets) and `html_directory` (the directory where
the returned HTML will be saved). Links are relative to `html_directory`; deploy
or move the HTML and asset directories together, preserving their relative layout.
This function returns HTML without writing an HTML file or creating its directory.
Shared-asset exports bypass the standalone HTML cache. Normalized plots and flame
graphs already use compact standalone HTML and do not write shared assets.

Normalized measurements provide metric
visibility, selection of recorded versions, viewport zoom and pan, exact point
inspection, and SVG/CSV export. Selection preserves the original ratios.
WGL figures provide viewport zoom and pan. Series, distributions, deltas,
tradeoffs and allocation line/file/heatmap/pie views include an exact recorded-row index and
JavaScript popups on native mark clicks. Zero-byte allocation rows remain in
the index even when their bars or pie sectors have no clickable surface.
An all-zero pie provides its recorded-row readout without a fabricated sector or highlight.
Flame graphs preserve exact recorded widths and share native diagnostic colors.
Their numeric frame index, keyboard focus and pointer inspection retain complete
paths and values, including frames too thin to click. They provide viewport
zoom/pan/Fit and original-model JSON and SVG-view downloads. Julia DataInspector and
ordinary Makie axis zoom callbacks are not exported.
"""
function PerfChecker.performance_plot_html(plot::PerfChecker.PerformancePlot;
        asset_directory = nothing, html_directory = nothing)
    if (asset_directory === nothing) != (html_directory === nothing)
        throw(ArgumentError("asset_directory and html_directory must be provided together"))
    end
    shared_assets = asset_directory !== nothing
    asset_server = if shared_assets
        for (name, directory) in ((:asset_directory, asset_directory),
            (:html_directory, html_directory))
            directory isa AbstractString && !isempty(strip(directory)) ||
                throw(ArgumentError("$name must be a nonempty directory path"))
            ispath(directory) && !isdir(directory) &&
                throw(ArgumentError("$name points to a file rather than a directory"))
        end
        Bonito.AssetFolder(abspath(asset_directory), abspath(html_directory))
    else
        nothing
    end
    return lock(RENDER_LOCK) do
        key = PerfChecker._content_digest(PerfChecker.performance_plot_dict(plot))
        !shared_assets && haskey(HTML_CACHE, key) && return HTML_CACHE[key]
        if plot.kind === :normalized_metrics
            template = read(joinpath(@__DIR__, "../src/assets/normalized.html"), String)
            data = replace(
                PerfChecker._canonical_json(merge(PerfChecker.performance_plot_dict(plot),
                    Dict("collector_label" => PerfCheckerMakie._model_collector(plot),
                        "colors" => Dict(row["metric"] => PerfCheckerMakie._metric_color(row["metric"])
                        for row in plot.data)))),
                "</" => "<\\/")
            html = replace(template, "__PERFCHECKER_NORMALIZED_PLOT__" => data)
            if !shared_assets
                length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                    delete!(HTML_CACHE, first(keys(HTML_CACHE)))
                HTML_CACHE[key] = html
            end
            return html
        end
        if plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph)
            html = _flame_plot_html(plot)
            if !shared_assets
                length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                    delete!(HTML_CACHE, first(keys(HTML_CACHE)))
                HTML_CACHE[key] = html
            end
            return html
        end
        WGLMakie.activate!(; resize_to = nothing, framerate = 24)
        figure = PerfChecker.performance_figure(plot)
        width, height = size(figure.scene)
        app = Bonito.App() do session
            inspection = _offline_point_controls(session, figure, plot)
            canvas = Bonito.DOM.div(
                Bonito.DOM.div(WGLMakie.WithConfig(figure; resize_to = nothing);
                    id = "offline-figure", style = Bonito.Styles(
                        "width" => "$(width)px", "height" => "$(height)px",
                        "transform-origin" => "top left"));
                id = "offline-viewport",
                role = "img",
                var"aria-label" = "$(plot.title) · $(PerfCheckerMakie._model_collector(plot)) · Tags: $(join(string.(get(plot.options, "tags", String[])), ", "))",
                style = Bonito.Styles(
                    "width" => "100%", "height" => "$(height)px",
                    "overflow" => "hidden", "background" => "#f7f9fc"))
            inspection === nothing && return canvas
            controls, tooltip = inspection
            return Bonito.DOM.div(controls, canvas, tooltip)
        end
        io = IOBuffer()
        session = Bonito.export_static(io, app; asset_server)
        close(session)
        html = String(take!(io))
        # Controls manipulate the actual exported figure, with no Julia callbacks.
        script = read(joinpath(@__DIR__, "../src/assets/offline.js"), String)
        data = replace(
            PerfChecker._canonical_json(PerfChecker.performance_plot_dict(plot)),
            "</" => "<\\/")
        script = replace(script, "__PERFCHECKER_OFFLINE_MODEL__" => data,
            "__PERFCHECKER_OFFLINE_WIDTH__" => string(width),
            "__PERFCHECKER_OFFLINE_HEIGHT__" => string(height))
        fit_script = "<script>" * script * "</script>"
        html = replace(html, "</body>" => fit_script * "</body>")
        if !shared_assets
            length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                delete!(HTML_CACHE, first(keys(HTML_CACHE)))
            HTML_CACHE[key] = html
        end
        return html
    end
end

@testitem "Shared HTML asset directories are explicit" tags=[:unit, :plots, :wgl, :assets] begin
    using PerfChecker, PerfCheckerMakie, WGLMakie

    plot = PerfChecker.PerformancePlot("asset-paths", :cpu_flamegraph,
        "CPU samples", "Empty profile", Dict{String, Any}(), Dict{String, Any}[],
        Dict{String, Any}("selected_version" => "demo", "value_label" => "samples"))
    standalone = performance_plot_html(plot)
    mktempdir() do directory
        assets, html = joinpath(directory, "assets"), joinpath(directory, "pages")
        @test_throws ArgumentError performance_plot_html(plot; asset_directory = assets)
        @test_throws ArgumentError performance_plot_html(plot; html_directory = html)
        @test_throws ArgumentError performance_plot_html(plot;
            asset_directory = "", html_directory = html)
        @test_throws ArgumentError performance_plot_html(plot;
            asset_directory = assets, html_directory = " ")
        @test_throws ArgumentError performance_plot_html(plot;
            asset_directory = 1, html_directory = html)
        file = joinpath(directory, "file")
        write(file, "not a directory")
        @test_throws ArgumentError performance_plot_html(plot;
            asset_directory = file, html_directory = html)
        @test_throws ArgumentError performance_plot_html(plot;
            asset_directory = assets, html_directory = file)
        @test performance_plot_html(plot; asset_directory = assets,
            html_directory = html) == standalone
        @test !ispath(assets)
        @test !ispath(html)
        @test performance_plot_html(plot) == standalone
    end
end

@testitem "Interactive flame graph HTML" tags=[:unit, :plots, :wgl, :flamegraph] begin
    using PerfChecker, PerfCheckerMakie
    using WGLMakie

    data = [Dict{String, Any}(
        "label" => "tiny", "path" => ["root", "tiny"], "depth" => 2,
        "x0" => 0.0, "x1" => 0.001, "value" => 1.0, "percentage" => 0.1,
        "status" => "inference_warning", "runtime_dispatch_value" => 0.0,
        "runtime_dispatch_percentage" => 0.0, "gc_event_value" => 0.0,
        "gc_event_percentage" => 0.0, "inference_status" => ["union"],
        "inferred_return_type" => ["Union{Int, String}"])]
    plot = PerfChecker.PerformancePlot("flame-test", :cpu_flamegraph,
        "CPU flame graph", "interactive flame graph", Dict{String, Any}(), data,
        Dict{String, Any}("selected_version" => "dev@1.0.0",
            "value_label" => "CPU samples"))
    html = performance_plot_html(plot)
    @test occursin("<svg id=\"flame\"", html)
    @test occursin("flame-frame", html)
    @test occursin("pointermove", html)
    @test occursin("Runtime dispatch", html)
    @test occursin("@code_warntype or Cthulhu", html)
    @test !occursin("<canvas", lowercase(html))
    payload = PerfChecker.JSON.parse(match(r"const PAYLOAD=(.*),MODEL=PAYLOAD.model,DATA=MODEL.data;", html).captures[1])
    @test payload["model"] == performance_plot_dict(plot)
    @test only(payload["colors"]) == payload["status_colors"]["inference_warning"]
    @test occursin("Recorded frame index", html)
    @test occursin("Download plot model JSON", html)
    @test occursin("Export SVG", html)
end

end
