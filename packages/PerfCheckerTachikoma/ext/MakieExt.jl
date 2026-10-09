module MakieExt

using PerfChecker
using PerfCheckerTachikoma
using PerfCheckerMakie
import Makie

function PerfCheckerTachikoma.plot_pixels(bundle::RunBundle, plot_id;
        size::Tuple{Int, Int} = (800, 480))
    all(>(0), size) || throw(ArgumentError("plot size must be positive"))
    figure = performance_figure(bundle, String(plot_id))
    Makie.resize!(figure, size...)
    image = Makie.colorbuffer(figure)
    height, width = Base.size(image)
    rgba = Vector{UInt8}(undef, 4 * width * height)
    offset = 0
    for y in axes(image, 1), x in axes(image, 2)
        color = image[y, x]
        for channel in (
            Makie.red(color), Makie.green(color), Makie.blue(color), Makie.alpha(color))
            offset += 1
            rgba[offset] = round(UInt8, 255 * clamp(Float64(channel), 0, 1))
        end
    end
    return (rgba = rgba, width = width, height = height)
end

end
