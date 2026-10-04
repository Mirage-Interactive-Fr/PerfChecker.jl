module EtendueCases
using EtendueContracts, EtendueGeometry, EtendueGameIR

struct ModelSpace <: AbstractCoordinateSpace end
struct WorldSpace <: AbstractCoordinateSpace end

"The same translation and coordinate oracle exercise allocating and in-place implementations."
function translation(parameters)
    n = get(parameters, "n", 65_536)
    implementation = get(parameters, "implementation", "inplace")
    n isa Integer && 1 <= n <= 1_000_000 || error("n must be in 1:1000000")
    implementation in ("inplace", "allocating") || error("unknown implementation")
    prepare = () -> (
        transform = translation_transform(ModelSpace, WorldSpace,
            Vec3{Float32, WorldSpace}(4, 8, 16)),
        input = [Point3{Float32, ModelSpace}(i, i + 1, i + 2) for i in 1:n],
        output = Vector{Point3{Float32, WorldSpace}}(undef, n))
    operation = implementation == "inplace" ?
                state -> (batch_transform!(state.output, state.transform, state.input); state.output) :
                state -> [transform_point(state.transform, point) for point in state.input]
    verify_result = (state, result) -> length(result) == n &&
        all(result[i][axis] == state.input[i][axis] + (4, 8, 16)[axis]
        for i in eachindex(result), axis in 1:3)
    (prepare = prepare, operation = operation,
        verify = verify_result, cleanup = _ -> nothing)
end

function scene_document(n; valid = true)
    entities = Operation[op("gameplay.entity";
                             attrs = Dict(
                                 "id" => "entity-$i", "tags" => [isodd(i) ? :odd : :even],
                                 "components" => Dict("health" => Dict(
                                     "current" => i, "max" => n)))) for i in 1:n]
    valid || push!(entities, op("unregistered.invalid"))
    scene = op("gameplay.scene"; attrs = (id = "perfchecker",), children = entities)
    game = op("gameplay.game"; attrs = (id = "perfchecker",), children = [scene])
    document([game]; dialects = [DialectUse(:gameplay, 1)])
end

"Verification uses an independent validity expectation, including a deliberately invalid document."
function verification(parameters)
    n = get(parameters, "n", 10_000)
    valid = get(parameters, "valid", true)
    implementation = get(parameters, "implementation", "workspace")
    n isa Integer && 1 <= n <= 100_000 || error("n must be in 1:100000")
    valid isa Bool || error("valid must be boolean")
    implementation in ("workspace", "allocating") || error("unknown implementation")
    prepare = () -> (value = scene_document(n; valid), registry = standard_registry(),
        workspace = VerificationWorkspace())
    operation = implementation == "workspace" ?
                state -> verify!(
        state.workspace, state.value, state.registry, RejectUnknown) :
                state -> verify(state.value, state.registry; unknown = RejectUnknown)
    (prepare = prepare, operation = operation,
        verify = (_, result) -> verification_succeeded(result) == valid,
        cleanup = _ -> nothing)
end
end
