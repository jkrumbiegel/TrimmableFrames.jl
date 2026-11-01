const df_expr = :(DataFrame(k = [2, 1, 2, 1], s = ["a", "b", "a", "b"], x = [1, 2, 3, 4], y = [1.5, missing, 2.5, 3.5]))

macro samedf(ex)
    wrapped = Expr(:let, :(df = $df_expr), ex)
    quoted = QuoteNode(wrapped)
    return quote
        @test isequal(outcome(DFSide, $quoted), outcome(TFSide, $quoted))
    end
end

@testset "selectors" begin
    @samedf select(df, :x)
    @samedf select(df, "x")
    @samedf select(df, 3)
    @samedf select(df, :x, :k)
    @samedf select(df, [:x, :k])
    @samedf select(df, ["x", "k"])
    @samedf select(df, [1, 2])
    @samedf select(df, 1:2)
    @samedf select(df, :)
    @samedf select(df, All())
    @samedf select(df, Not(:x))
    @samedf select(df, Not([:x, :k]))
    @samedf select(df, Not(:x, :k))
    @samedf select(df, Between(:s, :y))
    @samedf select(df, Cols(:x, :k))
    @samedf select(df, Cols(:x, Not(:k)))
    @samedf select(df, :x, :, :k)
    @samedf select(df, :nope)
    @samedf select(df, :x, :x)
end

@testset "select and transform" begin
    @samedf select(df, :x => :z)
    @samedf select(df, :x => :z, :x => :w)
    @samedf select(df, :x => identity => :z)
    @samedf select(df, :x => (a -> a .+ 1) => :z)
    @samedf select(df, :x => (a -> a .+ 1))
    @samedf select(df, :x => sum)
    @samedf select(df, :s => sum)
    @samedf select(df, :x => prod)
    @samedf select(df, :x => sum => :s, :y)
    @samedf select(df, :y, :x => sum)
    @samedf select(df, :x => ByRow(a -> a + 1))
    @samedf select(df, :x => ByRow(a -> a + 1) => :z)
    @samedf select(df, :y => ByRow(a -> a * 2))
    @samedf select(df, :y => ByRow(a -> a * 2) => :z)
    @samedf select(df, :s => ByRow(uppercase) => :u)
    @samedf select(df, :y => ByRow(a -> ismissing(a) ? 0.0 : a) => :z)
    @samedf select(df, :y => ByRow(a -> a === missing ? "no" : "yes"))
    @samedf select(df, [:x, :k] => ((a, b) -> a .+ b) => :z)
    @samedf select(df, [:x, :k] => (+) => :z)
    @samedf select(df, [:x, :k] => ByRow(+))
    @samedf select(df, [:x, :y] => ByRow((a, b) -> a * b) => :z)
    @samedf select(df, [:k, :x, :y] => ByRow((a, b, c) -> a + b + c))
    @samedf select(df, Not(:s, :y) => ByRow(+) => :z)
    @samedf select(df, :x => (a -> [1, 2]))
    @samedf select(df, :x => (a -> 1), :k)
    @samedf select(df, :x => identity => :z, :x => identity => :z)
    @samedf select(df, :x, :x => (a -> a .+ 1) => :x)
    @samedf select(df, :, :x => (a -> a .* 2.0) => :x)
    @samedf select(df, :x => (a -> a .* 2) => :z, :)
    @samedf select(df, :x => sum; renamecols = false)
    @samedf select(df, [:x, :k] => ByRow(+); renamecols = false)
    @samedf select(df, :x => ByRow(a -> (p = a, q = "s")) => AsTable)
    @samedf select(df, :x => ByRow(a -> (a, "s")) => [:p, :q])
    @samedf select(df, :x => (a -> (p = a, q = a .* 2.0)) => AsTable)
    @samedf select(df, nrow)
    @samedf select(df, nrow => :n, :k)
    @samedf select(df, [:x, :k] .=> sum)
    @samedf select(df, [:x, :k] .=> sum .=> [:p, :q])
    @samedf select(df, [:x, :k] .=> [:p, :q])

    @samedf transform(df, :x => sum)
    @samedf transform(df, :x => (a -> a .+ 1) => :x)
    @samedf transform(df, :x => ByRow(string) => :x)
    @samedf transform(df, :x => (a -> a .* 2) => :x2, :y => (a -> a .+ 1.0) => :y2)
    @samedf transform(df, :x => :z)
    @samedf transform(df, :x => :y => :z)
    @samedf transform!(df, :x => (a -> a .+ 1) => :z)
    @samedf (transform!(df, :x => (a -> a .+ 1) => :x); df)
    @samedf (select!(df, :x => (a -> a .+ 1) => :z, :k); df)

    @samedf combine(df, :x => sum)
    @samedf combine(df, :x => sum, :y)
    @samedf combine(df, :x => sum, :k => maximum => :m)
    @samedf combine(df, :x => (a -> [1, 2]), :k => (a -> [1, 2, 3]))
    @samedf combine(df, :x => (a -> [1, 2]), :k => sum)
    @samedf combine(df, nrow)
    @samedf combine(df, :x => (a -> (p = sum(a), q = 1)) => AsTable)
end

@testset "select results do not alias their sources" begin
    df = Full(a = [1, 2])
    @test select(df, :a).a !== df.a
    @test select(df, :a => identity => :b).b !== df.a
    @test select(df, :a => (x -> x) => :b).b !== df.a
    @test select(df, :a; copycols = false).a === df.a
    @test transform(df, :a => :b).a !== df.a
end

@testset "AsTable with compile-time names" begin
    df = Full(k = [1, 1, 2], x = [1, 2, 3], y = [1.5, 2.5, 3.5])
    @test select(df, AsTable(Val((:x, :y))) => ByRow(t -> t.x + t.y) => :z).z == [2.5, 4.5, 6.5]
    @test select(df, AsTable(Val((:x, :y))) => (t -> t.x .+ t.y) => :z).z == [2.5, 4.5, 6.5]
    @test propertynames(select(df, AsTable(Val((:x, :y))) => (t -> t.x))) == [:x_y_function]
    @test_throws "AsTable([:x, :y])" select(df, AsTable([:x, :y]) => (t -> t.x))
end

@testset "tuple sources" begin
    df = Full(a = [1, 2], b = [10, 20], c = [100, 200], d = [1000, 2000])
    @test select(df, (:a, :b) => ((x, y) -> x .+ y) => :z).z == [11, 22]
    @test select(df, (:a, :b, :c, :d) => ByRow((p, q, r, s) -> p + q + r + s) => :z).z == [1111, 2222]
    @test propertynames(select(df, (:a, :b) => ByRow(+))) == [Symbol("a_b_+")]
    @test_throws "at most 3 columns" select(df, [:a, :b, :c, :d] => ((p, q, r, s) -> p) => :z)
end

@testset "transformations leaving the allowed types" begin
    df = IntString(a = [1, 2])
    @test_throws "transform: column :b would have element type Float32" transform(df, :a => ByRow(Float32) => :b)
    @test_throws "select: column :a_sqrt would have element type Float64" select(df, :a => ByRow(sqrt))
    @test_throws ColumnTypeError combine(df, :a => (x -> 1.5) => :b)
    @test_throws "combine: column :b would have element type Tuple{Int64, Int64}" combine(df, :a => (x -> (1, 2)) => :b)
    @test_throws "select: column :n would have element type" select(df, :a => ByRow(x -> (p = x,)) => :n)
end

@testset "all-missing results use a missing-capable column" begin
    df = Full(a = [1, 2])
    @test isequal(select(df, :a => ByRow(x -> missing) => :b).b, [missing, missing])
    @test eltype(select(df, :a => ByRow(x -> x == 0 ? 1 : missing) => :b).b) == Union{Missing,Int}
end

@testset "custom column sets" begin
    Small = frametype(Float64)
    df = Small(a = [1.0, 2.0])
    @test select(df, :a => ByRow(x -> x + 1) => :b).b == [2.0, 3.0]
    @test_throws "select: column :b would have element type Int64" select(df, :a => ByRow(x -> 1) => :b)
end
