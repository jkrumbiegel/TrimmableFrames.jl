using Test
using TrimmableFrames

include("differential.jl")

@testset "TrimmableFrames" begin
    include("frame_tests.jl")
    include("select_tests.jl")
end
