module AdvisorCases
function dynamic(p)
    (prepare = () -> Any[identity, 42],
        operation = x -> x[1](x[2]), verify = (x, r) -> r == 42)
end
function allocating(p)
    (prepare = () -> collect(1:4096), operation = copy,
        verify = (x, r) -> r == x && r !== x)
end
healthy(p) = (prepare = () -> 42, operation = identity, verify = (x, r) -> r == 42)
incorrect(p) = (prepare = () -> 42, operation = identity, verify = (x, r) -> false)
function unavailable(p)
    (prepare = () -> 42, operation = identity, verify = (x, r) -> r == 42,
        availability = () -> (
            available = false, reason = "Deliberately unavailable fixture"))
end
end
