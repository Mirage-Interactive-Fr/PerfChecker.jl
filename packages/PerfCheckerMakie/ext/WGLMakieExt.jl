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
    data_json = replace(PerfChecker._canonical_json(plot.data), "</" => "<\\/")
    title_json = replace(
        PerfChecker._canonical_json(
            "$(plot.title) · $(plot.options["selected_version"]) · $(PerfCheckerMakie._model_collector(plot))"),
        "</" => "<\\/")
    tags = get(plot.options, "tags", String[])
    tags_json = replace(
        PerfChecker._canonical_json("Tags: " *
                                    (isempty(tags) ? "none" : join(string.(tags), ", "))),
        "</" => "<\\/")
    value_label_json = PerfChecker._canonical_json(String(plot.options["value_label"]))
    allocation_json = plot.kind === :allocation_flamegraph ? "true" : "false"
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{color-scheme:light;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#111827;background:#f7f9fc}
*{box-sizing:border-box}body{margin:0;background:#f7f9fc;display:flex;flex-direction:column;height:100vh}.flame-scroll{width:100%;flex:1;min-height:0;overflow:auto;padding:.5rem}
#flame{display:block;height:auto;background:white;border:1px solid #d8dee9;border-radius:.35rem}
.flame-controls{display:flex;align-items:center;flex-wrap:wrap;gap:.5rem;padding:.5rem;font-size:13px}.flame-controls button{padding:.35rem .7rem;border:1px solid #aab6c7;border-radius:.3rem;background:white;color:#111827;font:inherit;cursor:pointer}.flame-controls button:focus-visible{outline:2px solid #2459b3;outline-offset:2px}
.flame-frame{stroke:white;stroke-width:.8;cursor:help;outline:none}.flame-frame:hover,.flame-frame:focus{stroke:#111827;stroke-width:2}
.frame-label{font-size:11px;fill:#111827;pointer-events:none}.axis-label{font-size:12px;fill:#374151}.title{font-size:17px;font-weight:700;fill:#111827}.tick{font-size:10px;fill:#4b5563}.grid{stroke:#d1d5db;stroke-opacity:.5;stroke-width:1}.legend-title{font-size:13px;font-weight:700;fill:#111827}.legend-label,.note{font-size:11px;fill:#374151}
#tooltip{position:fixed;z-index:20;display:none;max-width:min(42rem,calc(100vw - 2rem));padding:.65rem .75rem;border-radius:.4rem;background:rgba(17,24,39,.96);color:white;font-size:12px;line-height:1.45;white-space:normal;overflow-wrap:anywhere;pointer-events:none;box-shadow:0 8px 28px rgba(0,0,0,.24)}
</style></head><body><div class="flame-controls" role="group" aria-label="Graph zoom"><button id="flame-fit">Fit graph</button><button id="flame-zoom-in" aria-label="Zoom in">+</button><button id="flame-zoom-out" aria-label="Zoom out">−</button><output id="flame-zoom-level" aria-live="polite">Fit</output></div><div class="flame-scroll"><svg id="flame" role="group"></svg></div><div id="tooltip" role="tooltip"></div>
<script>
const DATA=$data_json;
const TITLE=$title_json;
const TAGS=$tags_json;
const VALUE_LABEL=$value_label_json;
const ALLOCATION_ONLY=$allocation_json;
const NS="http://www.w3.org/2000/svg";
const svg=document.getElementById("flame"),tip=document.getElementById("tooltip");
const maximumDepth=Math.max(1,...DATA.map(item=>Number(item.depth)||1));
const rowHeight=18,marginLeft=82,marginRight=310,marginTop=54,marginBottom=62,svgWidth=1400;
const svgHeight=Math.max(620,marginTop+marginBottom+(maximumDepth+1)*rowHeight);
const plotWidth=svgWidth-marginLeft-marginRight;
svg.setAttribute("viewBox","0 0 "+svgWidth+" "+svgHeight);
svg.setAttribute("aria-label",TITLE+". Hover or focus a frame for its complete path and diagnostics.");
const viewport=document.querySelector(".flame-scroll");let zoom=1;
function resizeGraph(){const width=Math.max(1,Math.min(viewport.clientWidth-16,(viewport.clientHeight-16)*svgWidth/svgHeight));svg.style.width=(width*zoom)+"px";svg.style.height=(width*zoom*svgHeight/svgWidth)+"px";document.getElementById("flame-zoom-level").textContent=zoom===1?"Fit":Math.round(zoom*100)+"% of fit";tip.style.display="none"}
document.getElementById("flame-fit").addEventListener("click",()=>{zoom=1;viewport.scrollTo(0,0);resizeGraph()});
document.getElementById("flame-zoom-in").addEventListener("click",()=>{zoom=Math.min(8,zoom*1.5);resizeGraph()});
document.getElementById("flame-zoom-out").addEventListener("click",()=>{zoom=Math.max(1,zoom/1.5);resizeGraph()});
new ResizeObserver(resizeGraph).observe(viewport);resizeGraph();
function element(name,attrs,text){const node=document.createElementNS(NS,name);for(const [key,value] of Object.entries(attrs||{}))node.setAttribute(key,String(value));if(text!==undefined)node.textContent=text;return node}
function hashColor(label){let hash=0;for(let i=0;i<label.length;i++)hash=(hash*31+label.charCodeAt(i))|0;return "hsl("+(Math.abs(hash)%360)+" 55% 68%)"}
const diagnosticColors={runtime_dispatch:"#c71431",inference_warning:"#7533b8",gc_event:"#f27f0c"};
function frameColor(item){return diagnosticColors[item.status]||hashColor(String(item.label))}
function number(value,digits=3){return Number(value||0).toLocaleString(undefined,{maximumFractionDigits:digits})}
function tooltipText(item){const lines=["<strong>"+escapeHtml(item.label)+"</strong>","Path: "+escapeHtml((item.path||[]).join(" → ")),"Share: "+number(item.percentage)+"%","Weight: "+number(item.value,6)+" "+escapeHtml(VALUE_LABEL)];if(Number(item.runtime_dispatch_value)>0)lines.push("Runtime dispatch: "+number(item.runtime_dispatch_percentage,2)+"% ("+number(item.runtime_dispatch_value,6)+" "+escapeHtml(VALUE_LABEL)+")");if(Number(item.gc_event_value)>0)lines.push("Garbage collection: "+number(item.gc_event_percentage,2)+"% ("+number(item.gc_event_value,6)+" "+escapeHtml(VALUE_LABEL)+")");if((item.inference_status||[]).length)lines.push("Julia inference: "+escapeHtml(item.inference_status.join(", ")));if((item.inferred_return_type||[]).length)lines.push("Inferred return: "+escapeHtml(item.inferred_return_type.join(" | ")));if((item.inference_status||[]).some(status=>["any","union","abstract"].includes(status)))lines.push("Inspect with @code_warntype or Cthulhu");return lines.join("<br>")}
function escapeHtml(value){return String(value).replace(/[&<>\"']/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;",'\"':"&quot;","'":"&#39;"}[char]))}
function showTip(item,event){tip.innerHTML=tooltipText(item);tip.style.display="block";const x=Math.min(event.clientX+14,window.innerWidth-tip.offsetWidth-10);const y=Math.min(event.clientY+14,window.innerHeight-tip.offsetHeight-10);tip.style.left=Math.max(8,x)+"px";tip.style.top=Math.max(8,y)+"px"}
svg.append(element("text",{x:svgWidth/2,y:29,"text-anchor":"middle",class:"title"},TITLE));
svg.append(element("text",{x:svgWidth/2,y:48,"text-anchor":"middle",class:"note"},TAGS));
for(let tick=0;tick<=100;tick+=10){const x=marginLeft+plotWidth*tick/100;svg.append(element("line",{x1:x,x2:x,y1:marginTop,y2:svgHeight-marginBottom,class:"grid"}));svg.append(element("text",{x:x,y:svgHeight-marginBottom+19,"text-anchor":"middle",class:"tick"},tick))}
svg.append(element("text",{x:marginLeft+plotWidth/2,y:svgHeight-18,"text-anchor":"middle",class:"axis-label"},"share of captured "+VALUE_LABEL.toLowerCase()+" (%)"));
const yLabelPosition=marginTop+(svgHeight-marginTop-marginBottom)/2;const yLabel=element("text",{x:20,y:yLabelPosition,"text-anchor":"middle",class:"axis-label",transform:"rotate(-90 20 "+yLabelPosition+")"},"call stack depth");svg.append(yLabel);
DATA.forEach((item,index)=>{const x=marginLeft+plotWidth*Number(item.x0);const rectWidth=Math.max(.8,plotWidth*(Number(item.x1)-Number(item.x0)));const y=marginTop+(maximumDepth-Number(item.depth))*rowHeight;const rect=element("rect",{x,y,width:rectWidth,height:rowHeight-1,fill:frameColor(item),class:"flame-frame",tabindex:"0","data-index":index,"aria-label":String(item.label)+", "+number(item.percentage)+" percent"});rect.append(element("title",{},String(item.label)+"\\n"+(item.path||[]).join(" → ")));rect.addEventListener("pointermove",event=>showTip(item,event));rect.addEventListener("pointerleave",()=>tip.style.display="none");rect.addEventListener("focus",event=>{const box=rect.getBoundingClientRect();showTip(item,{clientX:box.left+box.width/2,clientY:box.top+box.height/2})});rect.addEventListener("blur",()=>tip.style.display="none");svg.append(rect);if(rectWidth>=52){svg.append(element("text",{x:x+rectWidth/2,y:y+12,"text-anchor":"middle",class:"frame-label"},String(item.label)))}});
const legendX=marginLeft+plotWidth+28,legendY=marginTop+18;
svg.append(element("text",{x:legendX,y:legendY-15,class:"legend-title"},"frame diagnostics"));
const legend=ALLOCATION_ONLY?[["#39a9b7","sampled allocation frame"]]:[["#39a9b7","sampled Julia frame"],[diagnosticColors.runtime_dispatch,"runtime dispatch"],[diagnosticColors.inference_warning,"non-concrete inferred return"],[diagnosticColors.gc_event,"garbage collection"]];
legend.forEach((entry,index)=>{const y=legendY+index*25;svg.append(element("rect",{x:legendX,y,width:18,height:18,fill:entry[0]}));svg.append(element("text",{x:legendX+26,y:y+13,class:"legend-label"},entry[1]))});
const notes=ALLOCATION_ONLY?["Width = share of allocated bytes.","Hover or focus every frame for its full path."]:["Red = observed dynamic dispatch.","Purple = cached non-concrete return inference.","Orange = garbage collection.","Hover or focus every frame for full diagnostics."];
notes.forEach((line,index)=>svg.append(element("text",{x:legendX,y:legendY+legend.length*25+22+index*17,class:"note"},line)));
</script></body></html>"""
end

function _offline_point_controls(session, figure, source_plot)
    source_plot.kind in (:distribution, :version_series, :version_delta,
        :time_allocation_tradeoff) || return nothing
    # Match the finite records consumed by the existing Makie recipes exactly.
    plot = PerfCheckerMakie._finite_plot(source_plot)
    isempty(plot.data) && return nothing
    axis = only(filter(item -> item isa Makie.Axis, figure.content))
    data = plot.data
    if plot.kind === :version_delta
        positions = [Point2f(index, 100 * item["relative_delta"])
                     for (index, item) in pairs(data)]
        points = [scatter!(axis, positions; color = :white, markersize = 7,
            strokecolor = PerfCheckerMakie._PLOT_PALETTE[1], strokewidth = 1.5,
            depth_shift = -0.001)]
        labels = ["$(item["baseline_version"]) → $(item["candidate_version"]) · change: $(100 * item["relative_delta"])% · $(get(item, "status", "unknown"))"
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
  const input = $(selector), output = $(readout), labels = $(labels);
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
      const key = ['wgl_positions', 'pos', 'offset'].find(key => source[key] && target[key]);
      if (!key) throw new Error('WGLMakie point positions are unavailable');
      const positions = source[key], selected = target[key];
      for (let component = 0; component < selected.itemSize; component++) {
        selected.array[component] = positions.array[(index - 1) * positions.itemSize + component];
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
Render a self-contained HTML document. Normalized measurements provide metric
visibility, selection of recorded versions, viewport zoom and pan, exact point
inspection, and SVG/CSV export. Selection preserves the original ratios.
WGL figures provide viewport zoom and pan. Series, distributions, deltas and
tradeoffs include an exact point index and JavaScript popups on point clicks.
Flame graphs have keyboard and pointer inspection. Julia DataInspector and
ordinary Makie axis zoom callbacks are not exported.
"""
function PerfChecker.performance_plot_html(plot::PerfChecker.PerformancePlot)
    return lock(RENDER_LOCK) do
        key = PerfChecker._content_digest(PerfChecker.performance_plot_dict(plot))
        haskey(HTML_CACHE, key) && return HTML_CACHE[key]
        if plot.kind === :normalized_metrics
            template = read(joinpath(@__DIR__, "../src/assets/normalized.html"), String)
            data = replace(
                PerfChecker._canonical_json(merge(PerfChecker.performance_plot_dict(plot),
                    Dict("collector_label" => PerfCheckerMakie._model_collector(plot),
                        "colors" => Dict(row["metric"] => PerfCheckerMakie._metric_color(row["metric"])
                        for row in plot.data)))),
                "</" => "<\\/")
            html = replace(template, "__PERFCHECKER_NORMALIZED_PLOT__" => data)
            length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                delete!(HTML_CACHE, first(keys(HTML_CACHE)))
            HTML_CACHE[key] = html
            return html
        end
        if plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph)
            html = _flame_plot_html(plot)
            length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                delete!(HTML_CACHE, first(keys(HTML_CACHE)))
            HTML_CACHE[key] = html
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
        session = Bonito.export_static(io, app)
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
        length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
            delete!(HTML_CACHE, first(keys(HTML_CACHE)))
        HTML_CACHE[key] = html
        return html
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
end

end
