macro samegd(ex, keys = :(:k))
    wrapped = :(let df = $df_expr, gd = groupby(df, $keys)
        $ex
    end)
    quoted = QuoteNode(wrapped)
    return quote
        @test isequal(outcome(DFSide, $quoted), outcome(TFSide, $quoted))
    end
end

@testset "groupby" begin
    @samedf length(groupby(df, :k))
    @samedf length(groupby(df, [:k, :s]))
    @samedf groupby(df, :k)[1]
    @samedf groupby(df, :s)[2]
    @samedf groupby(df, :y)[1]
    @samedf groupby(df, :nope)
    @samedf [nrow(g) for g in groupby(df, :s)]
    @samedf string.(groupcols(groupby(df, [:k, :s])))
    @samedf groupindices(groupby(df, :s))
    @samedf parent(groupby(df, :k)) == df
end

@testset "group order" begin
    @same combine(groupby(DataFrame(k = ["b", "a", "b", "c"]), :k), nrow)
    @same combine(groupby(DataFrame(k = ["b", "a", "b", "c"]), :k; sort = true), nrow)
    @same combine(groupby(DataFrame(k = ["b", "a", "b", "c"]), :k; sort = false), nrow)
    @same combine(groupby(DataFrame(k = [3, 1, 3, 2]), :k), nrow)
    @same combine(groupby(DataFrame(k = [3, 1, 3, 2]), :k; sort = false), nrow)
    @same combine(groupby(DataFrame(k = [1000, 1, 1000, 500]), :k), nrow)
    @same combine(groupby(DataFrame(k = [3, missing, 1, 3]), :k), nrow)
    @same combine(groupby(DataFrame(k = [3, missing, 1, 3]), :k; sort = true), nrow)
    @same combine(groupby(DataFrame(k = [3, missing, 1, 3]), :k; skipmissing = true), nrow)
    @same combine(groupby(DataFrame(k = [true, false, true]), :k), nrow)
    @same combine(groupby(DataFrame(k = [2.0, 1.0, 2.0]), :k), nrow)
    @same combine(groupby(DataFrame(k = [2.5, 1.0, 2.5]), :k), nrow)
    @same combine(groupby(DataFrame(k = [0.0, -0.0, 0.0]), :k), nrow)
    @same combine(groupby(DataFrame(k = [NaN, 1.0, NaN]), :k), nrow)
    @same combine(groupby(DataFrame(k = ["x", missing, "a", missing]), :k), nrow)
    @same combine(groupby(DataFrame(k = ["x", missing, "a", missing]), :k; sort = true), nrow)
    @same combine(groupby(DataFrame(k = ["x", missing, "a", missing]), :k; skipmissing = true), nrow)
    @same combine(groupby(DataFrame(a = [2, 1, 2, 1], b = ["y", "x", "x", "y"]), [:a, :b]), nrow)
    @same combine(groupby(DataFrame(a = [2, 1, 2, 1], b = ["y", "x", "x", "y"]), [:a, :b]; sort = true), nrow)
    @same combine(groupby(DataFrame(a = [2, 1, 2, 1], b = [4, 3, 3, 4]), [:b, :a]), nrow)
    @same combine(groupby(DataFrame(a = [missing, 1, missing], b = [1, missing, 1]), [:a, :b]; skipmissing = true), nrow)
    @same combine(groupby(DataFrame(a = Int[]), :a), nrow)
    @same combine(groupby(DataFrame(a = [1, 2]), []), nrow)
end

@testset "combine" begin
    @samegd combine(gd, :x => sum)
    @samegd combine(gd, :x => sum => :total)
    @samegd combine(gd, "x" => sum => "total")
    @samegd combine(gd, :x => sum, :y => first)
    @samegd combine(gd, :x => sum, :y => (a -> sum(skipmissing(a))))
    @samegd combine(gd, :x => mean)
    @samegd combine(gd, :x => (a -> [1, 2]), :y => first)
    @samegd combine(gd, :x => (a -> [1, 2]), :y => (a -> [1]))
    @samegd combine(gd, :x => (a -> [1, 2]), :y => (a -> [1, 2, 3]))
    @samegd combine(gd, :x => identity => :z)
    @samegd combine(gd, :k)
    @samegd combine(gd, :x)
    @samegd combine(gd, [:x, :y])
    @samegd combine(gd, :)
    @samegd combine(gd, Not(:k))
    @samegd combine(gd, :k => :k2)
    @samegd combine(gd, :x => sum => :k)
    @samegd combine(gd, :x, :y => first)
    @samegd combine(gd, :x => sum; keepkeys = false)
    @samegd combine(gd, :x => sum; renamecols = false)
    @samegd combine(gd, nrow)
    @samegd combine(gd, nrow => :n)
    @samegd combine(gd, proprow)
    @samegd combine(gd, proprow => :p)
    @samegd combine(gd, nrow, :x => sum, nrow => :n, proprow)
    @samegd combine(gd, [:x, :y] => ((a, b) -> sum(a) + length(b)))
    @samegd combine(gd, [:x, :y] => (+))
    @samegd combine(gd, [:x, :k] => ByRow(+))
    @samegd combine(gd, :x => ByRow(a -> a * 2))
    @samegd combine(gd, :y => ByRow(a -> a * 2) => :z)
    @samegd combine(gd, :x => (a -> a .+ 1))
    @samegd combine(gd, :y => (a -> a .+ 1))
    @samegd combine(gd, [:x, :k] .=> sum)
    @samegd combine(gd, [:x, :k] .=> sum .=> [:p, :q])
    @samegd combine(gd, :x => (a -> (p = sum(a), q = 1)) => AsTable)
    @samegd combine(gd, :x => (a -> (p = [sum(a)], q = [1])) => AsTable)
    @samegd combine(gd, :x => ByRow(a -> (p = a, q = 1)) => AsTable)
    @samegd combine(gd, :x => ByRow(a -> (a, 1)) => [:p, :q])
    @samegd combine(gd, :x => (a -> [(1, 2)]) => [:u, :v])
    @samegd combine(gd, :y => ByRow(a -> (p = a,)) => AsTable)
    @samegd combine(sdf -> sum(sdf.x), gd)
    @samegd combine(gd, sdf -> sum(sdf.x))
    @samegd combine(gd, sdf -> (a = sum(sdf.x), b = 1))
    @samegd combine(gd, sdf -> sdf[1:1, [:x]])
    @samegd combine(sdf -> nrow(sdf), gd)
    @samegd combine(gd) do sdf
        (m = maximum(sdf.x), n = nrow(sdf))
    end
    @samegd combine(gd, :s => first, :y => last, :x => maximum => :m) [:k, :s]
    @samegd combine(gd, :x => sum) [:y]
    @samegd combine(gd, :y => (a -> iseven(length(a)) ? 1 : missing))
    @samegd combine(gd, :x => (a -> a[1] > 1 ? 1 : missing) => :z)
    @samegd combine(gd, :x => (a -> a[1] > 1 ? "a" : missing) => :z)
end

@testset "select and transform on groups" begin
    @samegd select(gd, :x)
    @samegd select(gd, :x => sum)
    @samegd select(gd, :x => sum; keepkeys = false)
    @samegd select(gd, :x => sum, :k)
    @samegd select(gd, :x => cumsum => :c, :y)
    @samegd select(gd, :x => (a -> [1]))
    @samegd select(gd, nrow)
    @samegd select(gd, [:x, :y] => ByRow((a, b) -> a * b) => :z)
    @samegd transform(gd, :x => sum)
    @samegd transform(gd, :x => cumsum)
    @samegd transform(gd, :x => cumsum => :x)
    @samegd transform(gd, nrow)
    @samegd transform(gd, nrow => :n, :x => maximum => :m)
    @samegd transform(gd, :k => (a -> a .+ 1) => :k)
    @samegd transform(gd, :k => (a -> a .+ 1) => :j)
    @samegd transform(gd, :k => (a -> a .+ 1) => :k; keepkeys = false)
    @samegd transform(gd, :x => sum) [:s, :k]
    @samegd (transform!(gd, :x => sum => :t); df)
    @samegd (select!(gd, :x => sum => :t); df)
    @same let df = DataFrame(k = [1, missing, 1], x = [1, 2, 3])
        transform(groupby(df, :k; skipmissing = true), :x => sum)
    end
    @same let df = DataFrame(k = [1, missing, 1], x = [1, 2, 3])
        select(groupby(df, :k; skipmissing = true), :x)
    end
end

@testset "subset" begin
    @samedf subset(df, :x => a -> a .> 1)
    @samedf subset(df, :x => (a -> a .> 1), :k => (a -> a .== 2))
    @samedf subset(df, :x => ByRow(>(2)))
    @samedf subset(df, :y => ByRow(>(2.0)))
    @samedf subset(df, :y => ByRow(>(2.0)); skipmissing = true)
    @samedf subset(df, :x => a -> true)
    @samedf subset(df, :x => a -> 1)
    @samedf subset(df, :x => a -> a)
    @samedf subset(df, [:x, :k] => ByRow(==))
    @samedf subset(df, [:x, :k] => ((a, b) -> a .> b))
    @samedf subset(df)
    @samedf subset(df, :nope => ByRow(identity))
    @samedf subset(df, :x => (a -> [true]))
    @samedf (subset!(df, :x => ByRow(>(2))); df)
    @samegd subset(gd, :x => a -> a .== maximum(a))
    @samegd subset(gd, :x => a -> true)
    @samegd subset(gd, :x => a -> sum(a) > 4)
    @samegd subset(gd, :y => ByRow(>(2.0)); skipmissing = true)
    @samegd subset(gd, :y => ByRow(>(2.0)))
    @samegd (subset!(gd, :x => a -> a .== maximum(a)); df)
    @same let df = DataFrame(k = [1, missing, 1], x = [1, 2, 3])
        subset(groupby(df, :k; skipmissing = true), :x => a -> a .> 0)
    end

    Mini = frametype(Int64, String)
    df = Mini(a = [1, 2, 3])
    @test subset(df, :a => ByRow(>(1))).a == [2, 3]
    @test_throws "view=true is not supported" subset(df, :a => ByRow(>(1)); view = true)
end

@testset "vcat" begin
    @same vcat(DataFrame(a = [1]), DataFrame(a = [1.5]))
    @same vcat(DataFrame(a = [true]), DataFrame(a = [1]))
    @same vcat(DataFrame(a = Union{Int,Missing}[1]), DataFrame(a = [1.5]))
    @same vcat(DataFrame(a = [1, 2], b = ["x", "y"]), DataFrame(a = [3], b = ["z"]))
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1], a = [3]))
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1]))
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1]); cols = :union)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1]); cols = :intersect)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1], c = [1]); cols = :orderequal)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1], a = [1]); cols = :orderequal)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(b = [1], a = [1]); cols = [:b])
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(a = [1], b = [1]); source = :src)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(a = [1], b = [1]); source = :src => ["x", "y"])
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame(a = [1], b = [1]); source = :a)
    @same vcat(DataFrame(a = [1], b = [2]), DataFrame())
    @same vcat(DataFrame())
    @same vcat(DataFrame(a = [1]), DataFrame(a = [2.5]), DataFrame(a = [missing]))
    @same vcat(DataFrame(a = ["x"]), DataFrame(a = [missing]))
    @same reduce(vcat, [DataFrame(a = [1]), DataFrame(a = [2]), DataFrame(a = [3.5])])

    @test_throws "vcat: column :a combines element types Int64 and String into Any" vcat(Full(a = [1]), Full(a = ["x"]))
    Exact = frametype(Int64, String)
    @test vcat(Exact(a = [1], b = ["x"]), Exact(a = [2], b = ["y"])).a == [1, 2]
    @test_throws ColumnTypeError vcat(Exact(a = [1]), Exact(a = ["x"]))
    @test_throws "vcat: column :a needs element type Union{Missing, Int64}" vcat(Exact(a = [1], b = [2]), Exact(b = [3]); cols = :union)
    all_missing = vcat(Full(v = Union{Missing,String}[missing]), Full(v = Union{Missing,Int64}[missing]))
    @test all_missing.v isa Vector{Union{Missing,String}}
    @test isequal(all_missing.v, [missing, missing])
    IntsAndFloats = frametype(Int64, Float64)
    @test vcat(IntsAndFloats(a = [1]), IntsAndFloats(a = [1.5])).a == [1.0, 1.5]
end

@testset "integer keys" begin
    @test TrimmableFrames.slot_width(1, 1000, 1, 1_000_000) == 1001
    @test TrimmableFrames.slot_width(1, 1000, 1998, 1_000_000) == 1001
    @test TrimmableFrames.slot_width(1, 1000, 1999, 1_000_000) == 0
    @test TrimmableFrames.slot_width(1, 10^9, 1, 1000) == 0
    @test TrimmableFrames.slot_width(typemin(Int), typemax(Int), 1, 1000) == 0
    @test TrimmableFrames.slot_width(typemax(UInt64), typemax(UInt64), 1, 1000) == 0
    @test TrimmableFrames.slot_width(1, 0, 1, 1000) == 0

    @same combine(groupby(DataFrame(k = [3, 1, 3, 2, 1]), :k), nrow)
    @same combine(groupby(DataFrame(k = [-2, 5, -2, 0]), :k), nrow)
    @same combine(groupby(DataFrame(k = [3, missing, 1, missing, 3]), :k), nrow)
    @same combine(groupby(DataFrame(k = [3, missing, 1, missing, 3]), :k; skipmissing = true), nrow)
    @same combine(groupby(DataFrame(k = Union{Missing,Int}[missing, missing]), :k), nrow)
    @same combine(groupby(DataFrame(k = [typemax(Int), typemin(Int), typemax(Int)]), :k), nrow)
    @same combine(groupby(DataFrame(k = [typemax(Int), typemax(Int) - 1, typemax(Int)]), :k), nrow)
    @same combine(groupby(DataFrame(k = [typemin(Int), typemin(Int) + 1, typemin(Int)]), :k), nrow)
    @same combine(groupby(DataFrame(k = [true, false, true]), :k), nrow)
    @same combine(groupby(DataFrame(a = [1, 2, 1, 2], b = [1, 1, 2, 2], c = [1, 1, 1, 2]), [:a, :b, :c]), nrow)
    @same combine(groupby(DataFrame(a = [1, 1, 2], b = [20, 10, 20]), [:a, :b]; sort = false), nrow)
    @same combine(groupby(DataFrame(s = ["x", "y", "x", "y"], k = [1, 1, 2, missing]), [:s, :k]), nrow)
    @same combine(groupby(DataFrame(a = [1, missing, 1, 2], b = [missing, 1, missing, 2]), [:a, :b]; skipmissing = true), nrow)
    @same combine(groupby(DataFrame(k = Int[]), :k), nrow)
end
