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

number_frame() = DF(x = [1.5, 2.5], y = [0.5, 1.0], n = [1, 2], m = Union{Missing,Float64}[1.0, missing])

TrimmableFrames.expected_types(::ByRow{typeof(+)}, ::Val{2}) = ((Float64, Float64), (Int64, Int64))
TrimmableFrames.expected_types(::ByRow{typeof(>)}, ::Val{2}) = ((Float64, Float64),)

missing_sum(a, b) = a + b
TrimmableFrames.expected_types(::ByRow{typeof(missing_sum)}, ::Val{2}) = ((Union{Missing,Float64}, Union{Missing,Float64}),)

float_total(x) = sum(x)
TrimmableFrames.expected_types(::typeof(float_total), ::Val{1}) = ((AbstractVector{Float64},),)

p_expected() = render(select(number_frame(), [:x, :y] => ByRow(+) => :z))
p_expected_second() = render(select(number_frame(), (:n, :n) => ByRow(+) => :z))
p_expected_missing() = render(select(number_frame(), [:x, :m] => ByRow(missing_sum) => :z))
p_expected_column() = render(combine(groupby(number_frame(), :n), :x => float_total => :s))
p_expected_subset() = render(subset(number_frame(), [:x, :y] => ByRow(>)))

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
p_error_expected() = catching(() -> render(select(number_frame(), [:x, :n] => ByRow(+) => :z)))
p_error_vector_source() = catching(() -> render(select(source_frame(), [:qty, :price, :flag, :city] => ((a, b, c, d) -> a) => :q)))

join_people() = DF(
    id = [1, 2, 2, 4],
    name = ["a", "b", "c", "d"],
    score = Union{Missing,Float64}[1.5, missing, 2.5, 3.5],
)
join_jobs() = DF(id = [2, 2, 3, 1], job = ["x", "y", "z", "w"])
join_missing_keys() = DF(id = Union{Missing,Int64}[1, missing, 2], name = ["p", "q", "r"])

p_innerjoin() = render(innerjoin(join_people(), join_jobs(); on = :id))
p_leftjoin() = render(leftjoin(join_people(), join_jobs(); on = :id, order = :left))
p_rightjoin() = render(rightjoin(join_people(), join_jobs(); on = :id, order = :right))
p_outerjoin() = render(outerjoin(join_people(), join_jobs(); on = :id, source = :from))
p_semijoin() = render(semijoin(join_people(), join_jobs(); on = :id))
p_antijoin() = render(antijoin(join_people(), join_jobs(); on = :id))
p_crossjoin() = render(crossjoin(join_people(), join_jobs(); makeunique = true))
p_join_keys() = render(innerjoin(join_people(), join_jobs(); on = [:id, :name => :job], validate = (true, true)))
p_join_vector_key() = render(innerjoin(join_people(), join_jobs(); on = [:id]))
p_join_renamed() = render(leftjoin(join_people(), join_jobs(); on = :id => :id, renamecols = "_l" => uppercase))
p_join_several() = render(outerjoin(join_people(), join_jobs(), DF(id = [4], extra = [true]); on = :id))
p_join_missing() = render(outerjoin(join_missing_keys(), join_people(); on = :id, matchmissing = :equal, makeunique = true))
p_join_notequal() = render(innerjoin(join_missing_keys(), join_people(); on = :id, matchmissing = :notequal, makeunique = true))
function p_join_runtime_key(i)
    key = i == 0 ? :id : :name
    return render(innerjoin(join_people(), join_missing_keys(); on = key, matchmissing = :equal, makeunique = true))
end

p_error_join_key() = catching(() -> render(innerjoin(join_people(), join_jobs(); on = :id => :job)))
p_error_join_missing() = catching(() -> render(innerjoin(join_missing_keys(), join_people(); on = :id)))
p_error_join_validate() = catching(() -> render(innerjoin(join_people(), join_jobs(); on = :id, validate = (true, false))))
p_error_join_allowed() = catching(() -> render(leftjoin(narrow_frame(), frametype(Int64, String)(a = [2], t = ["z"]); on = :a)))

const Annotated = frametype(String, Int64, Float64, Bool; allowmissing = true, metadata = (String, Int64, Float64))

function annotated()
    df = Annotated(id = [1, 2, 2], k = ["a", "a", "b"], x = [1.0, 2.0, 3.0])
    metadata!(df, "study", "s1")
    metadata!(df, "version", 2)
    colmetadata!(df, :id, "label", "Identifier")
    colmetadata!(df, :id, "length", 8)
    colmetadata!(df, :x, "scale", 1.5)
    return df
end

function other()
    df = Annotated(id = [2, 3], z = [true, false])
    metadata!(df, "study", "s1")
    colmetadata!(df, :id, "label", "Identifier")
    colmetadata!(df, :z, "label", "Flag")
    return df
end

metadata_text(value) = value isa String ? value : value isa Int64 ? string(value) : string(value::Float64)

function render_metadata(df::Frame)
    for key in metadatakeys(df)
        println(Core.stdout, key, " = ", metadata_text(metadata(df, key)))
    end
    for (name, keys) in colmetadatakeys(df)
        for key in keys
            println(Core.stdout, name, ".", key, " = ", metadata_text(colmetadata(df, name, key)))
        end
    end
    return render(df)
end

p_metadata_verbs() = render_metadata(transform(select(annotated(), :x => :weight, :id), :id => ByRow(float) => :id))
p_metadata_groups() = render_metadata(combine(groupby(annotated(), :k), :x => sum => :x, :id => first => :first_id))
p_metadata_rename() = render_metadata(rename(subset(annotated(), :x => ByRow(>(1.0))), :x => :y))
p_metadata_vcat() = render_metadata(vcat(annotated(), annotated()))
p_metadata_join() = render_metadata(outerjoin(annotated(), other(); on = :id))
p_metadata_error() = catching(() -> render(colmetadata!(DF(a = [1]), :a, "n", 1)))

const ENTRY_POINTS = (
    (p_metadata_verbs, ()), (p_metadata_groups, ()), (p_metadata_rename, ()), (p_metadata_vcat, ()),
    (p_metadata_join, ()), (p_metadata_error, ()),
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
    (p_innerjoin, ()), (p_leftjoin, ()), (p_rightjoin, ()), (p_outerjoin, ()), (p_semijoin, ()), (p_antijoin, ()),
    (p_crossjoin, ()), (p_join_keys, ()), (p_join_vector_key, ()), (p_join_renamed, ()), (p_join_several, ()),
    (p_join_missing, ()), (p_join_notequal, ()), (p_join_runtime_key, (0, 1)),
    (p_expected, ()), (p_expected_second, ()), (p_expected_missing, ()), (p_expected_column, ()), (p_expected_subset, ()),
    (p_vector_source_vararg, ()), (p_tuple_source, ()), (p_small_set, ()), (p_small_set_vcat, ()),
    (p_runtime_function, (0, 1, 2)),
    (p_error_vcat, ()), (p_error_vcat_missing, ()), (p_error_transform, ()), (p_error_combine, ()),
    (p_error_outside_all, ()), (p_error_missing_column, ()), (p_error_duplicate, ()),
    (p_error_length, ()), (p_error_subset, ()), (p_error_vector_source, ()), (p_error_expected, ()),
    (p_error_join_key, ()), (p_error_join_missing, ()), (p_error_join_validate, ()), (p_error_join_allowed, ()),
)

end
