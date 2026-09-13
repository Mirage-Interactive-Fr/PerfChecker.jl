"""
Independent container workloads for the DataStructures 0.19 release series.

Construction and use are different cases: lookup/drain samples receive a freshly
built container in `prepare`, outside the timed region. All inputs are fixed and
all answers are compared with Base arrays/dictionaries, outside measurement.
"""
module ContainerCases
using DataStructures, Random

const FAMILIES = ["Deque", "Queue", "Stack", "CircularDeque", "CircularBuffer",
    "LinkedList", "MutableLinkedList", "BinaryMinHeap", "BinaryMaxHeap",
    "MutableBinaryMinHeap", "MutableBinaryMaxHeap", "BinaryMinMaxHeap",
    "PriorityQueue", "OrderedDict", "LittleDict", "DefaultDict", "DefaultOrderedDict",
    "RobinDict", "OrderedRobinDict", "SwissDict", "SortedDict", "SortedMultiDict",
    "MultiDict", "OrderedSet", "SortedSet", "SparseIntSet", "Accumulator", "Trie",
    "IntDisjointSet", "DisjointSet", "FenwickTree", "DiBitVector", "AVLTree", "RBTree", "SplayTree"]

const DICTS = ["OrderedDict", "LittleDict", "DefaultDict", "DefaultOrderedDict",
    "RobinDict", "OrderedRobinDict", "SwissDict", "SortedDict"]
const SETS = ["OrderedSet", "SortedSet", "SparseIntSet"]
const TREES = ["AVLTree", "RBTree", "SplayTree"]
const HEAPS = ["BinaryMinHeap", "BinaryMaxHeap", "MutableBinaryMinHeap", "MutableBinaryMaxHeap", "BinaryMinMaxHeap"]

"Construct a container by inserting a fixed permutation of unique integer keys."
function construct(family, input)
    n = length(input)
    T = getfield(DataStructures, Symbol(family))
    if family in DICTS
        c = family in ("DefaultDict", "DefaultOrderedDict") ? T{Int,Int}(0) : T{Int,Int}()
        for k in input; c[k] = 3k; end
    elseif family in SETS || family in TREES
        c = family == "SparseIntSet" ? T() : T{Int}()
        for k in input; push!(c, k); end
    elseif family == "Accumulator"
        c = counter(mod(k, 16) for k in input)
    elseif family == "Trie"
        c = Trie{Char,Int}()
        for k in input; c[string(k)] = 3k; end
    elseif family in ("IntDisjointSet", "DisjointSet")
        c = family == "IntDisjointSet" ? IntDisjointSet(n) : DisjointSet(collect(1:n))
        for k in 2:2:n; union!(c, k - 1, k); end
    elseif family == "FenwickTree"
        c = FenwickTree(input)
    elseif family == "DiBitVector"
        c = DiBitVector(n)
        for k in eachindex(input); c[k] = mod(input[k], 4); end
    elseif family == "LinkedList"
        c = nil(Int)
        for k in reverse(input); c = cons(k, c); end
    elseif family == "MultiDict"
        c = MultiDict{Int,Int}()
        for k in input; insert!(c, mod(k, 16), k); end
    elseif family == "SortedMultiDict"
        c = SortedMultiDict{Int,Int}()
        for k in input; push!(c, k => 3k); end
    elseif family == "PriorityQueue"
        c = PriorityQueue{Int,Int}()
        for k in input; c[k] = k; end
    else
        c = family in ("CircularDeque", "CircularBuffer") ? T{Int}(max(n, 1)) : T{Int}()
        for k in input; push!(c, k); end
    end
    return c
end

"An untimed representation used to check construction against an independent answer."
function canonical(family, c, input)
    n = length(input)
    if family in DICTS || family == "SortedMultiDict"
        return sort!(collect(c); by = first)
    elseif family in SETS
        return sort!(collect(c))
    elseif family in TREES
        return [haskey(c, k) for k in 1:n]
    elseif family == "Trie"
        return [c[string(k)] for k in 1:n]
    elseif family == "Accumulator"
        return Dict(c)
    elseif family == "MultiDict"
        return Dict(k => sort(v) for (k,v) in c)
    elseif family in ("DisjointSet", "IntDisjointSet")
        return (num_groups(c), [in_same_set(c, k - 1, k) for k in 2:2:n])
    elseif family == "FenwickTree"
        return [prefixsum(c, k) for k in 1:n]
    elseif family == "PriorityQueue"
        return sort!(collect(c); by = first)
    elseif family in HEAPS
        return sort!([pop!(c) for _ in 1:n])
    else
        return collect(c)
    end
end

function expected_construction(family, input)
    n = length(input)
    family in DICTS || family in ("SortedMultiDict", "PriorityQueue") ?
        [k => (family == "PriorityQueue" ? k : 3k) for k in 1:n] :
    family in SETS ? collect(1:n) :
    family in TREES ? fill(true, n) :
    family == "Trie" ? 3 .* collect(1:n) :
    family == "Accumulator" ? Dict(k => count(x -> mod(x,16) == k, input) for k in unique(mod.(input,16))) :
    family == "MultiDict" ? Dict(k => sort(filter(x -> mod(x,16) == k, input)) for k in unique(mod.(input,16))) :
    family in ("DisjointSet", "IntDisjointSet") ? (n - fld(n,2), fill(true, fld(n,2))) :
    family == "FenwickTree" ? cumsum(input) :
    family == "DiBitVector" ? mod.(input,4) :
    family in HEAPS ? sort(input) :
    family == "Stack" ? reverse(input) : copy(input)
end

"The second operation isolates access, draining, traversal or prefix queries."
function use_container(family, c, input)
    if family in DICTS
        return [c[k] for k in input]
    elseif family in TREES
        return [haskey(c, k) for k in input]
    elseif family in SETS
        return [k in c for k in input]
    elseif family == "Trie"
        return [c[string(k)] for k in input]
    elseif family in ("Deque", "Queue", "CircularDeque", "CircularBuffer", "MutableLinkedList", "PriorityQueue")
        return [popfirst!(c) for _ in input]
    elseif family in HEAPS || family == "Stack"
        return [pop!(c) for _ in input]
    else
        return canonical(family, c, input)
    end
end

operation_name(family) = family in DICTS || family in SETS || family in TREES || family == "Trie" ? "lookup" :
    family in HEAPS || family in ("Deque", "Queue", "Stack", "CircularDeque", "CircularBuffer", "MutableLinkedList", "PriorityQueue") ? "drain" :
    family == "FenwickTree" ? "prefixsum" : family in ("DisjointSet", "IntDisjointSet") ? "connectivity" : "traverse"

"Return an oracle-bearing case; no measurement or package installation happens here."
function container_case(family::AbstractString, operation::AbstractString = "build"; n::Int = 512, seed::Int = 42)
    family in FAMILIES || throw(ArgumentError("Unknown container: $family"))
    n >= 0 || throw(ArgumentError("n must be nonnegative"))
    input = randperm(Random.Xoshiro(seed), n)
    expected = expected_construction(family, input)
    if operation == "build"
        return (prepare = () -> copy(input), operation = x -> construct(family, x),
            verify = (state, result) -> state == input && canonical(family, result, input) == expected)
    end
    operation == operation_name(family) || throw(ArgumentError("Invalid operation for $family"))
    answer = if family in DICTS || family == "Trie"
        3 .* input
    elseif family in SETS || family in TREES
        fill(true, n)
    elseif family == "PriorityQueue"
        [k => k for k in 1:n]
    elseif family in HEAPS
        sort(input; rev = family in ("BinaryMaxHeap", "MutableBinaryMaxHeap"))
    else
        expected
    end
    return (prepare = () -> construct(family, input), operation = c -> use_container(family, c, input),
        verify = (_, result) -> result == answer)
end
end
