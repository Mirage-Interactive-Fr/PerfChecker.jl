using TestItems

@testitem "Deque build" tags=[:perf_only, :containers, :deque] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Deque", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Deque drain" tags=[:perf_only, :containers, :deque] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Deque", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Queue build" tags=[:perf_only, :containers, :queue] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Queue", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Queue drain" tags=[:perf_only, :containers, :queue] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Queue", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Stack build" tags=[:perf_only, :containers, :stack] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Stack", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Stack drain" tags=[:perf_only, :containers, :stack] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Stack", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "CircularDeque build" tags=[:perf_only, :containers, :circulardeque] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("CircularDeque", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "CircularDeque drain" tags=[:perf_only, :containers, :circulardeque] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("CircularDeque", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "CircularBuffer build" tags=[:perf_only, :containers, :circularbuffer] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("CircularBuffer", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "CircularBuffer drain" tags=[:perf_only, :containers, :circularbuffer] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("CircularBuffer", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "LinkedList build" tags=[:perf_only, :containers, :linkedlist] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("LinkedList", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "LinkedList traverse" tags=[:perf_only, :containers, :linkedlist] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("LinkedList", "traverse"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableLinkedList build" tags=[:perf_only, :containers, :mutablelinkedlist] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableLinkedList", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableLinkedList drain" tags=[:perf_only, :containers, :mutablelinkedlist] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableLinkedList", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMinHeap build" tags=[:perf_only, :containers, :binaryminheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMinHeap", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMinHeap drain" tags=[:perf_only, :containers, :binaryminheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMinHeap", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMaxHeap build" tags=[:perf_only, :containers, :binarymaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMaxHeap", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMaxHeap drain" tags=[:perf_only, :containers, :binarymaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMaxHeap", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableBinaryMinHeap build" tags=[:perf_only, :containers, :mutablebinaryminheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableBinaryMinHeap", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableBinaryMinHeap drain" tags=[:perf_only, :containers, :mutablebinaryminheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableBinaryMinHeap", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableBinaryMaxHeap build" tags=[:perf_only, :containers, :mutablebinarymaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableBinaryMaxHeap", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MutableBinaryMaxHeap drain" tags=[:perf_only, :containers, :mutablebinarymaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MutableBinaryMaxHeap", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMinMaxHeap build" tags=[:perf_only, :containers, :binaryminmaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMinMaxHeap", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "BinaryMinMaxHeap drain" tags=[:perf_only, :containers, :binaryminmaxheap] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("BinaryMinMaxHeap", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "PriorityQueue build" tags=[:perf_only, :containers, :priorityqueue] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("PriorityQueue", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "PriorityQueue drain" tags=[:perf_only, :containers, :priorityqueue] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("PriorityQueue", "drain"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedDict build" tags=[:perf_only, :containers, :ordereddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedDict lookup" tags=[:perf_only, :containers, :ordereddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "LittleDict build" tags=[:perf_only, :containers, :littledict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("LittleDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "LittleDict lookup" tags=[:perf_only, :containers, :littledict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("LittleDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DefaultDict build" tags=[:perf_only, :containers, :defaultdict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DefaultDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DefaultDict lookup" tags=[:perf_only, :containers, :defaultdict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DefaultDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DefaultOrderedDict build" tags=[:perf_only, :containers, :defaultordereddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DefaultOrderedDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DefaultOrderedDict lookup" tags=[:perf_only, :containers, :defaultordereddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DefaultOrderedDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "RobinDict build" tags=[:perf_only, :containers, :robindict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("RobinDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "RobinDict lookup" tags=[:perf_only, :containers, :robindict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("RobinDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedRobinDict build" tags=[:perf_only, :containers, :orderedrobindict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedRobinDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedRobinDict lookup" tags=[:perf_only, :containers, :orderedrobindict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedRobinDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SwissDict build" tags=[:perf_only, :containers, :swissdict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SwissDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SwissDict lookup" tags=[:perf_only, :containers, :swissdict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SwissDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedDict build" tags=[:perf_only, :containers, :sorteddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedDict lookup" tags=[:perf_only, :containers, :sorteddict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedDict", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedMultiDict build" tags=[:perf_only, :containers, :sortedmultidict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedMultiDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedMultiDict traverse" tags=[:perf_only, :containers, :sortedmultidict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedMultiDict", "traverse"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MultiDict build" tags=[:perf_only, :containers, :multidict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MultiDict", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "MultiDict traverse" tags=[:perf_only, :containers, :multidict] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("MultiDict", "traverse"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedSet build" tags=[:perf_only, :containers, :orderedset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedSet", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "OrderedSet lookup" tags=[:perf_only, :containers, :orderedset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("OrderedSet", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedSet build" tags=[:perf_only, :containers, :sortedset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedSet", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SortedSet lookup" tags=[:perf_only, :containers, :sortedset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SortedSet", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SparseIntSet build" tags=[:perf_only, :containers, :sparseintset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SparseIntSet", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SparseIntSet lookup" tags=[:perf_only, :containers, :sparseintset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SparseIntSet", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Accumulator build" tags=[:perf_only, :containers, :accumulator] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Accumulator", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Accumulator traverse" tags=[:perf_only, :containers, :accumulator] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Accumulator", "traverse"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Trie build" tags=[:perf_only, :containers, :trie] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Trie", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "Trie lookup" tags=[:perf_only, :containers, :trie] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("Trie", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "IntDisjointSet build" tags=[:perf_only, :containers, :intdisjointset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("IntDisjointSet", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "IntDisjointSet connectivity" tags=[:perf_only, :containers, :intdisjointset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("IntDisjointSet", "connectivity"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DisjointSet build" tags=[:perf_only, :containers, :disjointset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DisjointSet", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DisjointSet connectivity" tags=[:perf_only, :containers, :disjointset] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DisjointSet", "connectivity"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "FenwickTree build" tags=[:perf_only, :containers, :fenwicktree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("FenwickTree", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "FenwickTree prefixsum" tags=[:perf_only, :containers, :fenwicktree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("FenwickTree", "prefixsum"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DiBitVector build" tags=[:perf_only, :containers, :dibitvector] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DiBitVector", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "DiBitVector traverse" tags=[:perf_only, :containers, :dibitvector] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("DiBitVector", "traverse"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "AVLTree build" tags=[:perf_only, :containers, :avltree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("AVLTree", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "AVLTree lookup" tags=[:perf_only, :containers, :avltree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("AVLTree", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "RBTree build" tags=[:perf_only, :containers, :rbtree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("RBTree", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "RBTree lookup" tags=[:perf_only, :containers, :rbtree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("RBTree", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SplayTree build" tags=[:perf_only, :containers, :splaytree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SplayTree", "build"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "SplayTree lookup" tags=[:perf_only, :containers, :splaytree] begin
    include(joinpath(@__DIR__, "../src/containers.jl"))
    case = ContainerCases.container_case("SplayTree", "lookup"; n = 512)
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end
