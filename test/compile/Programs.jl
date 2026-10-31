module Programs

using TrimmableFrames

const DF = frametype(String, Int64, Float64, Bool; allowmissing = true)

source_frame() = DF(
    city = ["ber", "ham", "ber", "muc", "ham", "ber"],
    kind = Union{Missing,String}["a", "a", missing, "b", "a", "a"],
    qty = [1, 2, 3, 4, 5, 6],
    price = Union{Missing,Float64}[1.5, missing, 2.5, 4.0, 0.5, 2.0],
    flag = [true, false, true, true, false, false],
)

function render(df::Frame)
    io = IOBuffer()
    show(io, df)
    println(Core.stdout, String(take!(io)))
    return nrow(df) * 100 + ncol(df)
end

function total(x)
    s = zero(nonmissingtype(eltype(x)))
    for v in x
        v === missing || (s += v)
    end
    return s
end

size_of(x) = length(x)
average(x) = total(x) / length(x)

p_construct() = render(DF(:a => [1, 2], "b" => ["x", "y"], :c => 1.5))
p_construct_kw() = render(DF(a = 1:3, b = "s", c = [true, false, true]))
p_construct_runtime() = render(DF(columnunion(DF)[[1, 2], ["x", "y"]], Symbol[Symbol("n", i) for i in 1:2]))
p_construct_error() = catching(() -> render(frametype(Int64)(a = [1.5])))

function p_columns()
    df = source_frame()
    df.total = [1, 2, 3, 4, 5, 6]
    df[!, :label] = ["a", "b", "c", "d", "e", "f"]
    insertcols!(df, 1, :first_col => 1.5)
    insertcols!(df, :qty, :before_qty => true; after = false)
    select!(df, Not(:price))
    select!(df, :label, :)
    rename!(df, :city => :town)
    return render(df)
end

p_select() = render(select(source_frame(), :qty, :city => :town, Not(:city, :qty, :kind)))
p_select_function() = render(select(source_frame(), :qty => (x -> x .+ 1) => :next, :price => ByRow(x -> x * 2.0), :city => ByRow(uppercase) => :u))
p_select_scalar() = render(select(source_frame(), :qty => sum, :city))
p_select_multi() = render(select(source_frame(), [:qty, :price] => ByRow((a::Int64, b::Union{Missing,Float64}) -> a * b) => :value, (:qty, :flag) => ((a::Vector{Int64}, b::Vector{Bool}) -> a .+ b) => :sum))
p_select_table() = render(select(source_frame(), :qty => ByRow(x -> (double = x * 2, half = x / 2)) => AsTable))
p_select_astable() = render(select(source_frame(), AsTable(Val((:qty, :flag))) => ByRow(t -> t.flag ? t.qty : 0) => :picked))
p_transform() = render(transform(source_frame(), :qty => (x -> x .* 2) => :qty, :price => ByRow(x -> x === missing ? 0.0 : x) => :clean))
p_transform_vector_pairs() = render(transform(source_frame(), [:qty, :price] .=> total .=> [:q, :p]))

p_groupby() = length(groupby(source_frame(), [:city, :kind]))
p_groupby_sorted() = render(combine(groupby(source_frame(), [:kind, :city]; sort = true), nrow))
p_groupby_integer() = render(combine(groupby(DF(k = [3, 1, 3, 2]), :k), nrow))
p_groupby_skipmissing() = render(combine(groupby(source_frame(), :kind; skipmissing = true), nrow))
p_groupby_runtime_key(i::Int) = render(combine(groupby(source_frame(), propertynames(source_frame())[1 + mod(i, 5)]), nrow => :n))

p_combine() = render(combine(groupby(source_frame(), :city), :qty => total => :q, :price => total, :city => size_of => :n, nrow, proprow))
p_combine_vector() = render(combine(groupby(source_frame(), :city), :qty => (x -> x .+ 1), :price => first))
p_combine_byrow() = render(combine(groupby(source_frame(), :city), [:qty, :flag] => ByRow((q, f) -> f ? q : -q) => :signed))
p_combine_frame_function() = render(combine(sdf -> nrow(sdf), groupby(source_frame(), :city)))
p_combine_table() = render(combine(groupby(source_frame(), :city), :qty => (x -> (n = length(x), twice = 2 * length(x))) => AsTable))
p_combine_ungrouped() = render(combine(source_frame(), :qty => total, :price => average))

p_group_transform() = render(transform(groupby(source_frame(), :city), :qty => cumsum => :running, :qty => sum => :all, nrow))
p_group_select() = render(select(groupby(source_frame(), :city), :qty => total => :all, :flag))

p_subset() = render(subset(source_frame(), :qty => x -> x .> 2, :flag => ByRow(identity)))
p_subset_missing() = render(subset(source_frame(), :price => ByRow(x -> x > 1.0); skipmissing = true))
p_subset_group() = render(subset(groupby(source_frame(), :city), :qty => x -> x .== maximum(x)))

p_vcat() = render(vcat(DF(a = [1], b = ["x"]), DF(a = [2.5], b = ["y"])))
p_vcat_union() = render(vcat(DF(a = [1], b = ["x"]), DF(a = Union{Missing,Int64}[2], c = [true]); cols = :union))
p_vcat_source() = render(vcat(DF(a = [1]), DF(a = [2]); source = :from => ["l", "r"]))

add_flags(a::Int64, flags::Bool...) = a + count(flags)

p_vector_source_vararg() = render(select(source_frame(), [:qty, :flag] => ByRow(add_flags) => :z))
p_tuple_source() = render(select(source_frame(), (:qty, :flag, :price) => ByRow((a::Int64, b::Bool, c::Union{Missing,Float64}) -> b ? Float64(a) : c) => :z))

p_too_many_branches() = render(select(source_frame(), (:qty, :flag) => ByRow((a, b) -> 1) => :z))

const SmallFrame = frametype(Int64, Float64, String, Union{Missing,Float64})

small_frame() = SmallFrame(k = ["a", "b", "a"], v = [1, 2, 3], w = Union{Missing,Float64}[1.5, missing, 2.5])

p_small_set() = render(combine(groupby(small_frame(), :k), :v => sum, :w => total => :w_total, nrow))
p_small_set_vcat() = render(vcat(small_frame(), select(small_frame(), :k, :v, :v => ByRow(float) => :w)))

const AGGREGATES = (total, size_of, average)

pick_aggregate(::Tuple{}, ::Int, gd, source) = error("unknown aggregate")
pick_aggregate(fs::Tuple, i::Int, gd, source) =
    i == 1 ? combine(gd, source => first(fs) => :result) : pick_aggregate(Base.tail(fs), i - 1, gd, source)

p_runtime_function(i::Int) = render(pick_aggregate(AGGREGATES, 1 + mod(i, 3), groupby(source_frame(), :city), :qty))

function catching(f::F) where {F}
    try
        return f()
    catch e
        if e isa ColumnTypeError
            println(Core.stdout, "ColumnTypeError: ", e.msg)
        elseif e isa ArgumentError
            println(Core.stdout, "ArgumentError: ", e.msg::String)
        else
            println(Core.stdout, "other error")
        end
        return -1
    end
end

narrow_frame() = frametype(Int64, String)(a = [1, 2], s = ["x", "y"])

p_error_vcat() = catching(() -> render(vcat(DF(a = [1]), DF(a = ["x"]))))
p_error_vcat_missing() = catching(() -> render(vcat(narrow_frame(), frametype(Int64, String)(a = [3]); cols = :union)))
p_error_transform() = catching(() -> render(transform(narrow_frame(), :a => ByRow(x -> x / 2) => :half)))
p_error_combine() = catching(() -> render(combine(groupby(narrow_frame(), :s), :a => (x -> 1.5) => :v)))
p_error_outside_all() = catching(() -> render(select(source_frame(), :qty => ByRow(Float32) => :q)))
p_error_missing_column() = catching(() -> render(select(source_frame(), :nope)))
p_error_duplicate() = catching(() -> render(select(source_frame(), :qty => :q, :city => :q)))
p_error_length() = catching(() -> render(select(source_frame(), :qty => (x -> [1, 2]) => :q)))
p_error_subset() = catching(() -> render(subset(source_frame(), :price => ByRow(x -> x > 1.0))))
p_error_vector_source() = catching(() -> render(select(source_frame(), [:qty, :price, :flag, :city] => ((a, b, c, d) -> a) => :q)))

const ENTRY_POINTS = (
    (p_construct, ()), (p_construct_kw, ()), (p_construct_runtime, ()), (p_construct_error, ()),
    (p_columns, ()),
    (p_select, ()), (p_select_function, ()), (p_select_scalar, ()), (p_select_multi, ()),
    (p_select_table, ()), (p_select_astable, ()),
    (p_transform, ()), (p_transform_vector_pairs, ()),
    (p_groupby, ()), (p_groupby_sorted, ()), (p_groupby_integer, ()), (p_groupby_skipmissing, ()),
    (p_groupby_runtime_key, (0, 1, 3)),
    (p_combine, ()), (p_combine_vector, ()), (p_combine_byrow, ()), (p_combine_frame_function, ()),
    (p_combine_table, ()), (p_combine_ungrouped, ()),
    (p_group_transform, ()), (p_group_select, ()),
    (p_subset, ()), (p_subset_missing, ()), (p_subset_group, ()),
    (p_vcat, ()), (p_vcat_union, ()), (p_vcat_source, ()),
    (p_vector_source_vararg, ()), (p_tuple_source, ()), (p_small_set, ()), (p_small_set_vcat, ()),
    (p_runtime_function, (0, 1, 2)),
    (p_error_vcat, ()), (p_error_vcat_missing, ()), (p_error_transform, ()), (p_error_combine, ()),
    (p_error_outside_all, ()), (p_error_missing_column, ()), (p_error_duplicate, ()),
    (p_error_length, ()), (p_error_subset, ()), (p_error_vector_source, ()),
)

end
