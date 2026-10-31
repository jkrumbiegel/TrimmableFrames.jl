using Test, TrimmableFrames
using TrimmableFrames: branch_count, WholeFrame, MAX_BRANCHES

@testset "branch limit" begin
    DF = frametype(String, Int64, Float64, Bool; allowmissing = true)
    C = columnunion(DF)
    df = DF(q = [1, 2], f = [true, false], p = Union{Missing,Float64}[1.5, missing])

    plain_row(a, b) = b ? a : -a
    any_types(a, b) = 1
    typed_row(a::Int64, b::Bool) = b ? a : -a
    typed_vectors(a::Vector{Int64}, b::Vector{Bool}) = a .+ b
    three(a::Int64, b::Bool, c::Union{Missing,Float64}) = b ? Float64(a) : c

    @test MAX_BRANCHES == 30

    @test branch_count(ByRow(any_types), WholeFrame, C, Val(2)) == 64
    @test branch_count(ByRow(plain_row), WholeFrame, C, Val(2)) == 16
    @test branch_count(ByRow(typed_row), WholeFrame, C, Val(2)) == 4
    @test branch_count(ByRow(three), WholeFrame, C, Val(3)) == 20
    @test branch_count(typed_vectors, WholeFrame, C, Val(2)) == 1
    @test branch_count(sum, WholeFrame, C, Val(1)) == 8
    @test branch_count(() -> 1, WholeFrame, C, Val(0)) == 1

    @test select(df, (:q, :f) => ByRow(typed_row) => :z).z == [1, -2]
    @test select(df, (:q, :f) => ByRow(any_types) => :z).z == [1, 1]
    @test subset(df, (:q, :f) => ByRow((a, b) -> true)).q == [1, 2]
    @test isequal(select(df, (:q, :f, :p) => ByRow(three) => :z).z, Union{Missing,Float64}[1.0, missing])
    @test combine(groupby(df, :f), (:q, :q) => ((a::AbstractVector{Int64}, b::AbstractVector{Int64}) -> sum(a)) => :s).s == [2, 1]
    @test_throws "no method matching" select(df, (:f, :q) => ByRow(typed_row) => :z)
end
