# The inventory writers in these two verified versions omit the .html suffix
# required by this site's routes. Keep this process-local compatibility guard
# explicit; do not change installed packages or rewrite historical inventories.
# https://github.com/LuxDL/DocumenterVitepress.jl/blob/v0.3.5/src/writer.jl#L1487
# https://github.com/LuxDL/DocumenterVitepress.jl/blob/v0.3.7/src/writer.jl#L1487
if pkgversion(DocumenterVitepress) in (v"0.3.5", v"0.3.7")
    @eval DocumenterVitepress function _get_inventory_uri(doc, page, anchor_id)
        filename = relpath(page.build, doc.user.build)
        page_url = splitext(filename)[1] * ".html"
        if Sys.iswindows()
            page_url = replace(page_url, "\\" => "/")
        end
        uri = join(map(_escapeuri, split(page_url, "/")), "/")
        if !isnothing(anchor_id)
            uri = uri * "#" * _escapeuri(anchor_id)
        end
        return uri
    end
end

# DocumenterVitepress 0.3.5 emits ordered lists starting at 2, without the
# separating blank line needed after a paragraph. Keep the workaround inside
# this documentation process; do not modify the installed package cache.
# Upstream's current writer uses one-based enumeration:
# https://github.com/LuxDL/DocumenterVitepress.jl/blob/main/src/writer.jl
# Remove this guard after upgrading and passing the rendered-list browser checks.
if pkgversion(DocumenterVitepress) == v"0.3.5"
    @eval DocumenterVitepress function render(
            output::IO, mime::MIME"text/plain", tree::Documenter.MarkdownAST.Node,
            list::MarkdownAST.List, page, document; kwargs...)
        println(output)
        for (number, child) in enumerate(tree.children)
            marker = list.type === :ordered ? string(number, ". ") : "- "
            body = sprint() do buffer
                render(buffer, mime, child, child.children, page, document;
                    prenewline = false, kwargs...)
            end
            lines = split(rstrip(body, '\n'), '\n')
            println(output, marker, first(lines))
            padding = repeat(" ", max(4, length(marker)))
            for continuation in Iterators.drop(lines, 1)
                println(output, padding, continuation)
            end
            println(output)
        end
    end
end
