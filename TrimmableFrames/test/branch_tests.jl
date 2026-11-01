using Test, TrimmableFrames
using TrimmableFrames: branch_count, WholeFrame, MAX_BRANCHES

float_plus(args...) = +(args...)
two_kinds_plus(a, b) = a + b
missing_plus(a, b) = a + b
float_above(a, b) = a > b
total_of(x) = sum(x)

TrimmableFrames.expected_types(::ByRow{typeof(float_plus)}, ::Val{2}) = ((Float64, Float64),)
TrimmableFrames.expected_types(::ByRow{typeof(two_kinds_plus)}, ::Val{2}) = ((Float64, Float64), (Int64, Int64))
TrimmableFrames.expected_types(::ByRow{typeof(missing_plus)}, ::Val{2}) = ((Union{Missing,Float64}, Union{Missing,Float64}),)
TrimmableFrames.expected_types(::ByRow{typeof(float_above)}, ::Val{2}) = ((Float64, Float64),)
TrimmableFrames.expected_types(::typeof(total_of), ::Val{1}) = ((AbstractVector{Float64},),)

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

    @testset "expected_types" begin
        restricted(f, n) = TrimmableFrames.restrict(f, Val(n))
        numbers = DF(x = [1.5, 2.5], y = [0.5, 1.0], n = [1, 2], m = Union{Missing,Float64}[1.0, missing])

        @test branch_count(restricted(ByRow(float_plus), 2), WholeFrame, C, Val(2)) == 4
        @test branch_count(restricted(ByRow(two_kinds_plus), 2), WholeFrame, C, Val(2)) == 8
        @test branch_count(restricted(ByRow(missing_plus), 2), WholeFrame, C, Val(2)) == 25
        @test branch_count(restricted(total_of, 1), WholeFrame, C, Val(1)) == 1
        @test branch_count(restricted(ByRow(float_plus), 3), WholeFrame, C, Val(3)) == 343

        @test TrimmableFrames.accepts(ByRow(float_plus), Val(2))
        @test !TrimmableFrames.accepts(ByRow(float_plus), Val(3))
        @test TrimmableFrames.accepts(ByRow(+), Val(3))

        @test select(numbers, [:x, :y] => ByRow(float_plus) => :z).z == [2.0, 3.5]
        @test select(numbers, (:n, :n) => ByRow(two_kinds_plus) => :z).z == [2, 4]
        @test isequal(select(numbers, [:x, :m] => ByRow(missing_plus) => :z).z, Union{Missing,Float64}[2.5, missing])
        @test select(numbers, :x => total_of => :s).s == [4.0, 4.0]
        @test propertynames(select(numbers, [:x, :y] => ByRow(float_plus))) == [:x_y_float_plus]
        @test subset(numbers, [:x, :y] => ByRow(float_above)).n == [1, 2]
        @test select(numbers, (:x, :y, :n) => ByRow(float_plus) => :z).z == [3.0, 5.5]

        @test_throws "float_plus is restricted to Tuple{Float64, Float64}" select(numbers, [:x, :n] => ByRow(float_plus) => :z)
        @test_throws "float_plus is restricted to Tuple{Float64, Float64}" select(numbers, [:x, :m] => ByRow(float_plus) => :z)
        @test_throws "has no method for 3 columns" select(numbers, [:x, :y, :m] => ByRow(float_plus) => :z)
    end
end
