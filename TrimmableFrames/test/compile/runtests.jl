using Test

@testset "compile" begin
    include("wasm.jl")
    include("juliac.jl")
end
