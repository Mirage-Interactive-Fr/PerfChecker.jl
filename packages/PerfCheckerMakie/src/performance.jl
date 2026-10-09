function _performance_figure(title::AbstractString; size = (1100, 620), figure_kwargs = (;))
    figure = _figure(; figure_kwargs, size, backgroundcolor = RGBf(0.96, 0.97, 0.99))
    axis = Axis(figure[1, 1]; title = String(title), backgroundcolor = :white,
        titlealign = :left, titlesize = 20, subtitlesize = 12,
        xlabelsize = 14, ylabelsize = 14, xticklabelsize = 12, yticklabelsize = 12,
        xgridcolor = (:gray, 0.08), ygridcolor = (:gray, 0.14),
        topspinevisible = false, rightspinevisible = false)
    return figure, axis
end

function _empty_performance_figure(
        plot::PerfChecker.PerformancePlot; figure_kwargs = (;), plot_kwargs = (;),
        message = "No evidence available")
    figure = _figure(;
        figure_kwargs, size = (900, 480), backgroundcolor = RGBf(0.96, 0.97, 0.99))
    axis = Axis(figure[1, 1]; title = plot.title, xticklabelrotation = pi / 2)
    hidedecorations!(axis)
    hidespines!(axis)
    Label(figure[1, 1], message;
        fontsize = 24, color = RGBf(0.32, 0.38, 0.45))
    return figure
end

function _finite_plot(plot; include_zero_pie::Bool = false)
    fields = plot.kind in (:version_series, :distribution) ? ("value",) :
             plot.kind === :version_delta ? ("relative_delta",) :
             plot.kind === :time_allocation_tradeoff ? ("bytes", "time") :
             plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph) ?
             ("value", "x0", "x1", "depth") :
             startswith(string(plot.kind), "allocation_") ? ("bytes",) : ()
    data = filter(plot.data) do item
        all(field -> get(item, field, nothing) isa Real && isfinite(item[field]), fields)
    end
    if plot.kind === :allocation_pie
        data = filter(
            item -> item["bytes"] > 0 || (include_zero_pie && item["bytes"] == 0), data)
    elseif plot.kind === :normalized_metrics
        data = filter(
            item -> isnothing(get(item, "ratio", nothing)) ||
                (item["ratio"] isa Real && isfinite(item["ratio"])),
            data)
        any(item -> !isnothing(get(item, "ratio", nothing)), data) || empty!(data)
    end
    return PerfChecker.PerformancePlot(plot.id, plot.kind, plot.title, plot.description,
        plot.encoding, data, plot.options)
end

function _version_labels(data, field = "version")
    labels = unique!(String[String(item[field]) for item in data])
    return labels, Dict(label => index for (index, label) in pairs(labels))
end

function _add_inspector(figure)
    try
        DataInspector(figure)
    catch error
        @debug "Makie DataInspector is unavailable for this backend" exception=(
            error, catch_backtrace())
    end
    return figure
end

function _has_positive_range(values)
    !isempty(values) && all(>=(0), values) &&
        maximum(values) > minimum(values)
end

function _version_series_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs)
    labels, index = _version_labels(plot.data)
    xs = [index[String(item["version"])] for item in plot.data]
    ys = Float64[item["value"] for item in plot.data]
    colors = [item["target_kind"] == "dev" ? RGBf(0.93, 0.43, 0.18) :
              item["target_kind"] == "candidate" ? RGBf(0.56, 0.31, 0.82) :
              RGBf(0.04, 0.52, 0.57) for item in plot.data]
    _recipe!(
        lines!, axis, xs, ys; plot_kwargs, color = RGBf(0.04, 0.52, 0.57), linewidth = 3)
    scatter!(axis, xs, ys; color = colors, markersize = 15, strokewidth = 2,
        strokecolor = :white, inspector_label = (self,
        index,
        position) -> "$(labels[index])\n$(round(position[2]; sigdigits = 5)) $(plot.options["unit"])")
    axis.xticks = (collect(eachindex(labels)), labels)
    xlims!(axis, 0.5, length(labels) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "package version"
    axis.ylabel = "$(plot.options["metric"]) ($(plot.options["unit"]))"
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

function _normalized_metrics_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs)
    versions = plot.options["versions"]
    index = Dict(version => i for (i, version) in pairs(versions))
    metrics = unique(String[row["metric"] for row in plot.data])
    colors = Makie.to_color.(_metric_color.(metrics))
    legend = GridLayout(figure[1, 2]; tellheight = false)
    Label(legend[1, 1:2], "Measurements"; fontsize = 14, halign = :left)
    for (i, metric) in pairs(metrics)
        rows = filter(row -> row["metric"] == metric, plot.data)
        xs = [index[row["version"]] for row in rows]
        ys = [isnothing(row["ratio"]) ? NaN : Float64(row["ratio"]) for row in rows]
        label = replace(metric, "julia." => "")
        any(row -> row["normalization_status"] == "both_zero", rows) &&
            (label *= " (0/0: unchanged)")
        curve = _recipe!(scatterlines!, axis, xs, ys; plot_kwargs,
            label, color = colors[i], linewidth = 2,
            markersize = 10, inspector_label = (self, sample, position) -> begin
                row = rows[sample]
                "$(row["version"]) · $metric\n$(row["value"]) $(row["unit"])\nratio: $(row["ratio"]) · $(row["normalization_status"])"
            end)
        legend_color = get(_attributes(plot_kwargs), :color, colors[i])
        legend_color isa AbstractVector && (legend_color = first(legend_color))
        toggle = Toggle(legend[i + 1, 1]; active = curve.visible[],
            framecolor_active = legend_color, width = 34)
        Label(legend[i + 1, 2], label; color = legend_color, halign = :left,
            fontsize = 12)
        on(toggle.active) do visible
            curve.visible[] = visible
        end
    end
    hlines!(axis, [1.0]; color = (:gray, 0.6), linestyle = :dash)
    axis.xticks = (collect(eachindex(versions)), _version_tick_label.(versions))
    xlims!(axis, 0.5, length(versions) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "package version"
    axis.ylabel = "ratio to $(plot.options["reference_version"]) (reference = 1)"
    Label(figure[2, 1:2],
        "$(plot.options["zero_reference_policy"]). Gaps indicate unavailable ratios.";
        fontsize = 12, tellwidth = false)
    return _add_inspector(figure)
end

function _distribution_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs)
    labels, index = _version_labels(plot.data)
    xs = [index[String(item["version"])] for item in plot.data]
    ys = Float64[item["value"] for item in plot.data]
    _recipe!(boxplot!, axis, xs, ys; plot_kwargs, color = (RGBf(0.04, 0.52, 0.57), 0.68),
        strokecolor = RGBf(0.02, 0.31, 0.35), show_outliers = true)
    scatter!(axis, xs, ys; color = (RGBf(0.08, 0.14, 0.24), 0.28), markersize = 6,
        inspector_label = (self,
        sample,
        position) -> "$(labels[Int(round(position[1]))])\n$(round(position[2]; sigdigits = 6)) $(plot.options["unit"])\nsample $(sample)")
    axis.xticks = (collect(eachindex(labels)), labels)
    xlims!(axis, 0.5, length(labels) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "package version"
    axis.ylabel = "$(plot.options["metric"]) ($(plot.options["unit"]))"
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

function _delta_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    records = [item
               for item in plot.data if get(item, "relative_delta", nothing) isa Number]
    isempty(records) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs)
    labels = ["$(item["baseline_version"]) → $(item["candidate_version"])"
              for item in records]
    values = Float64[item["relative_delta"] * 100 for item in records]
    colors = [value > 0 ? RGBf(0.77, 0.16, 0.13) :
              value < 0 ?
              RGBf(0.05, 0.49, 0.25) : RGBf(0.36, 0.42, 0.50) for value in values]
    _recipe!(barplot!, axis, eachindex(values), values;
        plot_kwargs, color = colors, strokecolor = :white,
        strokewidth = 1, inspector_label = (self, index, position) -> begin
            item = records[index]
            delta = round(100 * Float64(item["relative_delta"]); digits = 3)
            "$(labels[index])\nchange: $(delta)%\nstatus: $(get(item, "status", "unknown"))"
        end)
    hlines!(axis, [0.0]; color = RGBf(0.08, 0.14, 0.24), linewidth = 2)
    axis.xticks = (collect(eachindex(labels)), labels)
    xlims!(axis, 0.5, length(labels) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "comparison"
    axis.ylabel = "relative change (%)"
    return _add_inspector(figure)
end

function _allocation_files_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs, size = (1200, 650))
    versions, version_index = _version_labels(plot.data)
    files = sort!(unique!(String[String(item["file"]) for item in plot.data]))
    file_index = Dict(file => index for (index, file) in pairs(files))
    xs = [version_index[String(item["version"])] for item in plot.data]
    ys = Float64[item["bytes"] for item in plot.data]
    stacks = [file_index[String(item["file"])] for item in plot.data]
    colors = make_colors(length(files))
    _recipe!(barplot!, axis, xs, ys; plot_kwargs, stack = stacks, color = colors[stacks],
        inspector_label = (self, index, position) -> begin
            item = plot.data[index]
            "$(item["version"])\n$(item["file"])\n$(round(Float64(item["bytes"]); sigdigits = 6)) bytes"
        end)
    axis.xticks = (collect(eachindex(versions)), versions)
    xlims!(axis, 0.5, length(versions) + 0.5)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "package version"
    axis.ylabel = "allocated bytes by source file"
    # Stacked segment heights must remain proportional to their recorded bytes.
    ylims!(axis, 0, nothing)
    custom_color = get(_attributes(plot_kwargs), :color, nothing)
    legend_colors, legend_labels = custom_color isa AbstractVector ?
                                   (
        custom_color, ["$(item["file"]) · $(item["version"])" for item in plot.data]) :
                                   (_legend_colors(colors, plot_kwargs), files)
    Legend(figure[1, 2], [PolyElement(color = color) for color in legend_colors],
        legend_labels;
        title = "source file", tellheight = false)
    return _add_inspector(figure)
end

"""
Map recorded pie rows to the strictly positive sectors present in the native mesh.
The inspection position is the triangle's centroid, inside the rendered sector.
Zero rows have no native sector: retain an empty vertex range and triangle with
a NaN position, without inventing a clickable surface. Reject a mismatch between
the positive recorded rows and native sectors.
"""
function _allocation_pie_inspection(recipe::Makie.Pie, data)
    poly = only(filter(item -> item isa Makie.Poly, recipe.plots))
    pieces = poly.meshes[]
    length(pieces) == count(item -> item["bytes"] > 0, data) ||
        error("Native allocation pie sectors differ from its positive recorded rows")
    weights = recipe[3][]
    weights == Float64[row["bytes"] for row in data if row["bytes"] > 0] ||
        error("Native allocation pie weights differ from its recorded row order")
    source = only(filter(item -> item isa Makie.Mesh, Makie.collect_atomic_plots([recipe])))
    vertices = Makie.GeometryBasics.coordinates(source[1][])
    length(vertices) ==
    sum(piece -> length(Makie.GeometryBasics.coordinates(piece)), pieces) ||
        error("Native allocation pie does not retain its sector vertices")
    positions, ranges, triangles = Point2f[], Vector{Int}[], Vector{Int}[]
    offset = 0
    for piece in pieces
        coordinates = Makie.GeometryBasics.coordinates(piece)
        indices = offset .+ collect(eachindex(coordinates))
        all(isapprox.(vertices[indices], coordinates)) ||
            error("Native allocation pie mesh order differs from its sectors")
        selected, largest_area = Int[], 0.0
        for face in Makie.GeometryBasics.faces(piece)
            # GeometryBasics GL faces store offset integers; use their Julia indices.
            corners = coordinates[Base.to_index.(face)]
            a, b, c = corners
            area = abs((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]))
            if area > largest_area
                largest_area = area
                selected = offset .+ Base.to_index.(collect(face))
            end
        end
        push!(positions,
            isempty(selected) ? Point2f(NaN, NaN) : Point2f(sum(vertices[selected]) / 3))
        push!(ranges, indices .- 1)
        push!(triangles, selected .- 1)
        offset += length(coordinates)
    end
    positive = 0
    row_positions, row_ranges, row_triangles = Point2f[], Vector{Int}[], Vector{Int}[]
    for row in data
        if row["bytes"] == 0
            push!(row_positions, Point2f(NaN, NaN))
            push!(row_ranges, Int[])
            push!(row_triangles, Int[])
        else
            positive += 1
            push!(row_positions, positions[positive])
            push!(row_ranges, ranges[positive])
            push!(row_triangles, triangles[positive])
        end
    end
    return (;
        source, positions = row_positions, ranges = row_ranges, triangles = row_triangles)
end

function _allocation_pie_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    data = filter(item -> item["bytes"] > 0, plot.data)
    isempty(data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs,
        message = "No positive allocation weight")
    figure = _figure(;
        figure_kwargs, size = (1100, 650), backgroundcolor = RGBf(0.96, 0.97, 0.99))
    axis = Axis(figure[1, 1];
        title = "$(plot.title) · $(plot.options["selected_version"])",
        aspect = DataAspect(), backgroundcolor = :white)
    labels = String[String(item["label"]) for item in data]
    values = Float64[item["bytes"] for item in data]
    percentages = Float64[item["percentage"] for item in data]
    colors = make_colors(length(labels))
    _recipe!(pie!, axis, values; plot_kwargs, color = colors,
        strokecolor = :white, strokewidth = 2,
        inspector_label = (self,
        index,
        position) -> "$(labels[index])\n$(round(values[index]; sigdigits = 6)) bytes\n$(round(percentages[index]; digits = 3))%")
    hidedecorations!(axis)
    hidespines!(axis)
    legend_labels = ["$(labels[index]) · $(round(percentages[index]; digits = 1))%"
                     for index in eachindex(labels)]
    Legend(figure[1, 2],
        [PolyElement(color = color) for color in _legend_colors(colors, plot_kwargs)],
        legend_labels;
        title = "allocation share", tellheight = false)
    return _add_inspector(figure)
end

function _allocation_lines_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    width = max(1100, 34 * length(plot.data))
    figure, axis = _performance_figure(
        "$(plot.title) · $(plot.options["selected_version"])"; figure_kwargs, size = (
            width, 650))
    labels = String[String(item["label"]) for item in plot.data]
    values = Float64[item["bytes"] for item in plot.data]
    files = String[String(item["file"]) for item in plot.data]
    unique_files = sort!(unique(files))
    palette = make_colors(length(unique_files))
    color_index = Dict(file => index for (index, file) in pairs(unique_files))
    colors = [palette[color_index[file]] for file in files]
    _recipe!(barplot!, axis, eachindex(values), values; plot_kwargs, color = colors,
        inspector_label = (self, index, position) -> begin
            item = plot.data[index]
            "$(item["file"]):$(item["line"])\n$(round(Float64(item["bytes"]); sigdigits = 6)) bytes"
        end)
    axis.xticks = (collect(eachindex(labels)), labels)
    xlims!(axis, 0.5, length(labels) + 0.5)
    axis.xticklabelrotation = pi / 2.7
    axis.xlabel = "source file and line"
    axis.ylabel = "allocated bytes"
    _has_positive_range(values) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

"Render observed allocation cells; leave missing cells transparent and reject ambiguous duplicates."
function _allocation_heatmap_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    versions = String.(plot.options["versions"])
    labels = String.(plot.options["labels"])
    version_index = Dict(version => index for (index, version) in pairs(versions))
    label_index = Dict(label => index for (index, label) in pairs(labels))
    matrix = fill(NaN, length(versions), length(labels))
    occupied = Set{Tuple{Int, Int}}()
    for item in plot.data
        cell = (version_index[String(item["version"])], label_index[String(item["label"])])
        cell in occupied &&
            throw(ArgumentError("allocation heatmap contains a duplicate version/site cell"))
        push!(occupied, cell)
        matrix[cell...] = Float64(item["bytes"])
    end
    height = max(650, 20 * length(labels))
    figure, axis = _performance_figure(plot.title; figure_kwargs, size = (1250, height))
    heat = _recipe!(
        heatmap!, axis, eachindex(versions), eachindex(labels), matrix; plot_kwargs,
        colorscale = Makie.pseudolog10, colormap = :thermal, nan_color = :transparent,
        inspector_label = (self, index, position) -> begin
            x = clamp(Int(round(position[1])), 1, length(versions))
            y = clamp(Int(round(position[2])), 1, length(labels))
            value = isnan(matrix[x, y]) ? "No recorded allocation observation" :
                    "$(round(matrix[x, y]; sigdigits = 6)) bytes"
            "$(versions[x])\n$(labels[y])\n$value"
        end)
    axis.xticks = (collect(eachindex(versions)), versions)
    axis.yticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 2
    axis.xlabel = "package version"
    axis.ylabel = "source file and line"
    Colorbar(figure[1, 2], heat; label = "allocated bytes")
    return _add_inspector(figure)
end

const _FLAME_STATUS_COLORS = Dict(
    "runtime_dispatch" => RGBf(0.78, 0.08, 0.19),
    "inference_warning" => RGBf(0.46, 0.20, 0.72),
    "gc_event" => RGBf(0.95, 0.50, 0.08))

function _flame_tooltip(item, plot)
    value_label = String(plot.options["value_label"])
    lines = String[
        "Frame: $(item["label"])",
        "Path: $(join(item["path"], " → "))",
        "Share: $(round(Float64(item["percentage"]); digits = 3))%",
        "Weight: $(round(Float64(item["value"]); sigdigits = 6)) $value_label"]
    dispatch_value = Float64(get(item, "runtime_dispatch_value", 0.0))
    dispatch_percentage = Float64(get(item, "runtime_dispatch_percentage", 0.0))
    dispatch_value > 0 && push!(lines,
        "Runtime dispatch: $(round(dispatch_percentage; digits = 2))% ($(round(dispatch_value; sigdigits = 6)) $value_label)")
    gc_value = Float64(get(item, "gc_event_value", 0.0))
    gc_percentage = Float64(get(item, "gc_event_percentage", 0.0))
    gc_value > 0 && push!(lines,
        "Garbage collection: $(round(gc_percentage; digits = 2))% ($(round(gc_value; sigdigits = 6)) $value_label)")
    inference_status = String.(get(item, "inference_status", String[]))
    return_types = String.(get(item, "inferred_return_type", String[]))
    isempty(inference_status) || push!(lines,
        "Julia inference: $(join(inference_status, ", "))")
    isempty(return_types) || push!(lines,
        "Inferred return: $(join(return_types, " | "))")
    any(status -> status in ("any", "union", "abstract"), inference_status) &&
        push!(lines, "Inspect with @code_warntype or Cthulhu")
    return join(lines, '\n')
end

function _flame_legend!(figure, allocation_only; custom_colors = false)
    if custom_colors
        Label(figure[1, 2],
            "Custom frame colors.\nColors do not encode diagnostics.\nHover any frame for full diagnostics.";
            tellwidth = false, justification = :left, halign = :left,
            color = RGBf(0.30, 0.35, 0.42), fontsize = 12)
        return figure
    end
    normal_color = RGBf(0.22, 0.66, 0.72)
    if allocation_only
        elements = [PolyElement(color = normal_color)]
        labels = ["sampled allocation frame"]
        note = "Width = share of allocated bytes.\nHover any frame for its full path."
    else
        statuses = ("normal", "runtime_dispatch", "inference_warning", "gc_event")
        colors = [normal_color;
                  [_FLAME_STATUS_COLORS[status] for status in statuses[2:end]]]
        elements = [PolyElement(color = color) for color in colors]
        labels = [
            "sampled Julia frame", "runtime dispatch", "non-concrete inferred return",
            "garbage collection"]
        note = "Red = observed dynamic dispatch.\nPurple = non-concrete inferred return.\nOrange = garbage collection.\nHover any frame for full diagnostics."
    end
    legend_grid = figure[1, 2] = GridLayout()
    Legend(legend_grid[1, 1], elements, labels;
        title = "frame diagnostics", tellheight = false)
    Label(legend_grid[2, 1], note;
        tellwidth = false, justification = :left, halign = :left,
        color = RGBf(0.30, 0.35, 0.42), fontsize = 12)
    return figure
end

function _flamegraph_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    maximum_depth = maximum(item -> Int(item["depth"]), plot.data)
    figure, axis = _performance_figure(
        "$(plot.title) · $(plot.options["selected_version"])";
        figure_kwargs, size = (1400, 620))
    labels = sort!(unique!(String[String(item["label"]) for item in plot.data]))
    palette = make_colors(length(labels))
    label_colors = Dict(label => palette[index] for (index, label) in pairs(labels))
    allocation_only = plot.kind === :allocation_flamegraph
    depths = Float64[Int(item["depth"]) for item in plot.data]
    starts = Float64[100 * Float64(item["x0"]) for item in plot.data]
    stops = Float64[100 * Float64(item["x1"]) for item in plot.data]
    rectangle_colors = [get(_FLAME_STATUS_COLORS, String(get(item, "status", "normal")),
                            label_colors[String(item["label"])])
                        for item in plot.data]
    _recipe!(barplot!, axis, depths, stops; plot_kwargs, fillto = starts, direction = :x,
        width = 0.84, gap = 0, color = rectangle_colors, strokecolor = :white,
        strokewidth = 0.8, inspectable = true,
        inspector_label = (self, index, position) -> _flame_tooltip(plot.data[index], plot))
    for item in plot.data
        x0 = 100 * Float64(item["x0"])
        width = 100 * (Float64(item["x1"]) - Float64(item["x0"]))
        width >= 7 || continue
        text!(axis, x0 + width / 2, Int(item["depth"]);
            text = String(item["label"]), align = (:center, :center), fontsize = 11,
            color = RGBf(0.04, 0.08, 0.13))
    end
    xlims!(axis, 0, 100)
    ylims!(axis, 0.4, maximum_depth + 0.6)
    axis.xlabel = "share of captured $(lowercase(String(plot.options["value_label"]))) (%)"
    axis.ylabel = "call stack depth"
    axis.xticks = 0:10:100
    _flame_legend!(
        figure, allocation_only; custom_colors = haskey(_attributes(plot_kwargs), :color))
    return _add_inspector(figure)
end

function _tradeoff_figure(plot; figure_kwargs = (;), plot_kwargs = (;))
    isempty(plot.data) && return _empty_performance_figure(plot; figure_kwargs, plot_kwargs)
    figure, axis = _performance_figure(plot.title; figure_kwargs)
    xs = Float64[item["bytes"] for item in plot.data]
    ys = Float64[item["time"] for item in plot.data]
    time_unit, allocation_unit = PerfChecker._tradeoff_plot_units(plot.options)
    colors = 1:length(plot.data)
    _recipe!(scatterlines!, axis, xs, ys; plot_kwargs, color = colors, colormap = :viridis,
        markersize = 16, linewidth = 2,
        inspector_label = (self, index, position) -> begin
            item = plot.data[index]
            "$(item["version"])\n$(round(Float64(item["bytes"]); sigdigits = 6)) $allocation_unit\n$(round(Float64(item["time"]); sigdigits = 6)) $time_unit"
        end)
    annotations = Dict{Tuple{Float64, Float64}, Vector{String}}()
    for (index, item) in pairs(plot.data)
        push!(get!(annotations, (xs[index], ys[index]), String[]), String(item["version"]))
    end
    positions = unique(collect(zip(xs, ys)))
    labels = map(positions) do position
        distinct_versions = unique(annotations[position])
        return length(distinct_versions) == 1 ?
               _version_tick_label(only(distinct_versions)) :
               "$(length(distinct_versions)) versions"
    end
    annotation!(axis, first.(positions), last.(positions); text = labels,
        fontsize = 12, style = Makie.Ann.Styles.Line(), color = (:gray, 0.65),
        textcolor = :black, linewidth = 0.8)
    axis.xlabel = "allocation ($allocation_unit)"
    axis.ylabel = "wall time ($time_unit)"
    _has_positive_range(xs) && (axis.xscale = Makie.pseudolog10)
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

"""
    performance_figure(plot; figure_kwargs=(;), axis_kwargs=(;), plot_kwargs=(;), tags=nothing, tool=nothing)

Render saved evidence with the active Makie backend. Attribute bundles are
NamedTuples or Symbol-keyed dictionaries: figure attributes go to Figure,
axis attributes customize the completed Axis, and plot attributes override the
primary recipe (lines, scatterlines, boxplot, barplot, pie or heatmap).
Inspection overlays and reference lines keep their own settings. Attributes
are presentation only; no workload is run or measurement changed. Unknown
Makie attributes raise Makie's normal error. Collector and tags appear in the
subtitle; pass tool explicitly for manually built models
whose collector identity is absent. Collector names and tag lists are appended
to customized subtitles while titles are preserved. Empty evidence returns a labeled figure.
Allocation pies draw strictly positive weights; an all-zero recorded model returns
a "No positive allocation weight" figure without dividing by a zero total.
"""
function PerfChecker.performance_figure(plot::PerfChecker.PerformancePlot;
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;), tags = get(
            plot.options, "tags", nothing),
        tool = nothing)
    renderers = Dict(:normalized_metrics => _normalized_metrics_figure,
        :version_series => _version_series_figure, :distribution => _distribution_figure,
        :version_delta => _delta_figure, :allocation_pie => _allocation_pie_figure,
        :allocation_files => _allocation_files_figure, :allocation_lines => _allocation_lines_figure,
        :allocation_heatmap => _allocation_heatmap_figure,
        :allocation_flamegraph => _flamegraph_figure, :cpu_flamegraph => _flamegraph_figure,
        :wall_flamegraph => _flamegraph_figure, :time_allocation_tradeoff => _tradeoff_figure)
    haskey(renderers, plot.kind) ||
        throw(ArgumentError("Makie does not support performance plot kind $(plot.kind)"))
    _attributes(axis_kwargs)
    _attributes(plot_kwargs)
    figure = renderers[plot.kind](
        _finite_plot(plot; include_zero_pie = plot.kind === :allocation_pie);
        figure_kwargs, plot_kwargs)
    label = isnothing(tool) ? _model_collector(plot) : String(tool)
    return _decorate!(figure; tool = label, tags, axis_kwargs)
end

function _bundle_collector(bundle, id)
    entry = PerfChecker._catalog_entry(bundle, id)
    haskey(entry, "collector") && return _collector_label(entry["collector"])
    if haskey(entry, "series_id")
        return _collector_label(PerfChecker._series_by_id(bundle, entry["series_id"])["measurement_definition"])
    end
    haskey(entry, "definition") && return _collector_label(entry["definition"])
    definitions = unique([get(item, "measurement_definition", "")
                          for item in bundle.observations
                          if get(item, "case_id", "") == get(entry, "case_id", nothing)])
    return isempty(definitions) ? "Collector: unspecified" :
           join(unique(_collector_label.(definitions)), " + ")
end

function PerfChecker.performance_figure(bundle::PerfChecker.RunBundle; figure_kwargs = (;),
        axis_kwargs = (;), plot_kwargs = (;), tags = get(bundle.manifest, "tags", nothing), kwargs...)
    plot = PerfChecker.performance_plot(bundle; kwargs...)
    return PerfChecker.performance_figure(
        plot; figure_kwargs, axis_kwargs, plot_kwargs, tags,
        tool = _bundle_collector(bundle, plot.id))
end

function PerfChecker.performance_figure(bundle::PerfChecker.RunBundle, id::AbstractString;
        figure_kwargs = (;), axis_kwargs = (;), plot_kwargs = (;),
        tags = get(bundle.manifest, "tags", nothing), kwargs...)
    return PerfChecker.performance_figure(
        PerfChecker.performance_plot(bundle, id; kwargs...);
        figure_kwargs, axis_kwargs, plot_kwargs, tags, tool = _bundle_collector(bundle, id))
end
