module SalesCases

"One validated sales record, after parsing and input validation."
struct Sale
    quantity::Int
    unit_price::Float64
    discount::Float64
end

"Compute net revenue without changing the input records."
function net_revenue(rows)
    total = 0.0
    for row in rows
        total += row.quantity * row.unit_price * (1.0 - row.discount)
    end
    return total
end

function records(n)
    n > 0 && n % 8 == 0 || error("Use a positive multiple of eight records")
    return [Sale(1 + i % 4, Float64(10 + i % 8), iseven(i) ? 0.25 : 0.0)
            for i in 1:n]
end

"The original ingestion path retained an untyped collection."
function dynamic(parameters)
    n = Int(parameters["rows"])
    return (
        prepare = () -> Any[records(n)...],
        operation = net_revenue,
        verify = (rows, result) -> length(rows) == n && result == 253.0 * (n ÷ 8)
    )
end

"Keep the validated record type when constructing the collection."
function typed(parameters)
    n = Int(parameters["rows"])
    return (
        prepare = () -> records(n),
        operation = net_revenue,
        verify = (rows, result) -> length(rows) == n && result == 253.0 * (n ÷ 8)
    )
end

end
