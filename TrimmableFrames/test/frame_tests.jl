const IntString = frametype(Int64, String)
const Full = frametype(String, Int64, Float64, Bool; allowmissing = true)

@testset "frametype" begin
    @test IntString === Frame{Union{Vector{Int64},Vector{String}},String}
    @test Full === Frame{Union{
        Vector{String},Vector{Int64},Vector{Float64},Vector{Bool},
        Vector{Union{Missing,String}},Vector{Union{Missing,Int64}},
        Vector{Union{Missing,Float64}},Vector{Union{Missing,Bool}},
    },String}
    @test frametype(Int64, Union{Missing,Int64}) === Frame{Union{Vector{Int64},Vector{Union{Missing,Int64}}},String}
end

@testset "constructors" begin
    @same DataFrame()
    @same DataFrame(a = 1:3, b = ["x", "y", "z"])
    @same DataFrame(a = [1, 2], b = 1.5, c = "s")
    @same DataFrame(a = 1, b = "s")
    @same DataFrame(:a => [1, 2], :b => [true, false])
    @same DataFrame("a" => [1, 2], "b" => [1.5, 2.5])
    @same DataFrame([:a => [1, 2], :b => ["x", "y"]])
    @same DataFrame((a = [1, 2], b = [3.0, 4.0]))
    @same DataFrame([[1, 2], ["x", "y"]], [:a, :b])
    @same DataFrame([[1, 2], ["x", "y"]], ["a", "b"])
    @same DataFrame(a = Union{Missing,Int}[1, 2], b = [missing, "x"])
    @same DataFrame(a = [1, 2], b = [1, 2, 3])
    @same DataFrame(:a => [1], :a => [2])

    @test Full(a = Any[1, 2]).a isa Vector{Int64}
    @test Full(a = Any[1, missing]).a isa Vector{Union{Missing,Int64}}

    v = [1, 2]
    @test IntString(a = v).a !== v
    @test IntString(a = v; copycols = false).a === v
end

@testset "constructor leaves the allowed types" begin
    @test_throws "Frame constructor: column :a would have element type Float32" IntString(a = Float32[1])
    @test_throws ColumnTypeError IntString(a = [1.5])
    @test_throws "column :c" IntString(:b => [1], :c => [true])
end

@testset "accessors" begin
    df = Full(a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 2.5])
    @test names(df) == ["a", "b", "c"]
    @test propertynames(df) == [:a, :b, :c]
    @test nrow(df) == 3
    @test ncol(df) == 3
    @test size(df) == (3, 3)
    @test df.a == [1, 2, 3]
    @test df[!, :b] == ["x", "y", "z"]
    @test df[!, "b"] === df.b
    @test df[:, :b] !== df.b
    @test df[:, :b] == df.b
    @test df[2, :b] == "y"
    @test isequal(df[2, :c], missing)
    @test nrow(Full()) == 0
    @test_throws "column name :nope not found" df.nope
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 2.5])
        df[[1, 3], :]
    end
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 2.5])
        df[[true, false, true], [:c, :a]]
    end
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 2.5])
        df[2:3, Not(:b)]
    end
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"])
        df[:, [:b]]
    end
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"])
        first(df, 2)
    end
    @same let df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"])
        last(df, 2)
    end
    @same let df = DataFrame(a = [1, 2, 3])
        copy(df) == df
    end
    @same isequal(DataFrame(a = [1, missing]), DataFrame(a = [1, missing]))
    @same DataFrame(a = [1, 2]) == DataFrame(a = [1.0, 2.0])
    @same DataFrame(a = [1, 2]) == DataFrame(b = [1, 2])
end

@testset "adding, replacing, deleting and moving columns" begin
    @same let df = DataFrame(a = [1, 2])
        df.b = ["x", "y"]
        df
    end
    @same let df = DataFrame(a = [1, 2])
        df[!, :b] = [1.5, 2.5]
        df
    end
    @same let df = DataFrame(a = [1, 2])
        df.a = ["x", "y"]
        df
    end
    @same let df = DataFrame(a = [1, 2])
        df.b = [1, 2, 3]
        df
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols!(df, :c => ["x", "y"])
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols!(df, 1, :c => ["x", "y"], :d => 1.5)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols!(df, :b, :c => ["x", "y"])
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols!(df, :a, :c => 1; after = true)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols!(df, :a => [5, 6])
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        insertcols(df, :c => 1)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4], c = [5, 6])
        select!(df, Not(:b))
        df
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4], c = [5, 6])
        select!(df, :c, :)
        df
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4], c = [5, 6])
        select(df, Not(:a), :a)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        rename(df, :a => :x)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        rename!(df, :a => :b)
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        rename!(df, [:x, :y])
        df
    end
    @same let df = DataFrame(a = [1, 2], b = [3, 4])
        rename(df, "a" => "x", "b" => "y")
    end

    df = IntString(a = [1, 2])
    @test_throws "setproperty!: column :b would have element type Float64" (df.b = [1.5, 2.5])
    @test_throws "insertcols!: column :c would have element type Bool" insertcols!(df, :c => true)
end

@testset "show" begin
    @test sprint(show, Full(a = [1, 2], b = ["x", missing])) == """
        2×2 Frame
         Row │ a      b
             │ Int64  String?
        ─────┼────────────────
           1 │ 1      x
           2 │ 2      missing"""
end
