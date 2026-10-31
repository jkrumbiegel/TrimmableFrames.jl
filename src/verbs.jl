function manipulate(verb::Symbol, df::Frame{C}, args::Tuple, keeprows::Bool, renamecols::Bool, copycols::Bool) where {C}
    out = Output{C}(verb, keeprows)
    segments = WholeFrame(nrow(df))
    run_all!(Context(df, segments, out, renamecols, copycols), args)
    return out, segments
end

function finish(out::Output{C}, segments::WholeFrame) where {C}
    return result_frame(out, aligned_columns(out, segments, target_lengths(out, segments)))
end

"""
    select(df, args...; copycols=true, renamecols=true)

Columns and transformations of `df`, in the DataFrames mini-language. Also takes a
[`GroupedFrame`](@ref).
"""
@specialized_args function select(df::Frame, args...; copycols::Bool = true, renamecols::Bool = true, threads::Bool = true)
    return finish(manipulate(:select, df, args, true, renamecols, copycols)...)
end

@specialized_args function transform(df::Frame, args...; copycols::Bool = true, renamecols::Bool = true, threads::Bool = true)
    return finish(manipulate(:transform, df, (:, args...), true, renamecols, copycols)...)
end

@specialized_args function combine(df::Frame, args...; renamecols::Bool = true, threads::Bool = true)
    return finish(manipulate(:combine, df, args, false, renamecols, true)...)
end

function replace_contents!(df::Frame{C}, result::Frame{C}) where {C}
    empty!(columnnames(df))
    append!(columnnames(df), columnnames(result))
    empty!(columns(df))
    append!(columns(df), columns(result))
    return df
end

@specialized_args function select!(df::Frame, args...; renamecols::Bool = true, threads::Bool = true)
    return replace_contents!(df, select(df, args...; copycols = false, renamecols = renamecols))
end

@specialized_args function transform!(df::Frame, args...; renamecols::Bool = true, threads::Bool = true)
    return replace_contents!(df, transform(df, args...; copycols = false, renamecols = renamecols))
end

select(f::F, df::Union{Frame,GroupedFrame}; kwargs...) where {F<:Base.Callable} = select(df, f; kwargs...)
transform(f::F, df::Union{Frame,GroupedFrame}; kwargs...) where {F<:Base.Callable} = transform(df, f; kwargs...)
combine(f::F, df::Union{Frame,GroupedFrame}; kwargs...) where {F<:Base.Callable} = combine(df, f; kwargs...)
select!(f::F, df::Frame; kwargs...) where {F<:Base.Callable} = select!(df, f; kwargs...)
transform!(f::F, df::Frame; kwargs...) where {F<:Base.Callable} = transform!(df, f; kwargs...)

function reject_dropped_rows(verb::Symbol, gd::GroupedFrame)
    if length(rowgroups(gd).rows) != nrow(parent(gd))
        throw(ArgumentError(string(
            verb, " does not support a GroupedFrame from which some rows were dropped, ",
            "as with groupby(df, cols; skipmissing=true)",
        )))
    end
end

function manipulate(verb::Symbol, gd::GroupedFrame{C}, args::Tuple, keeprows::Bool, renamecols::Bool, copycols::Bool) where {C}
    keeprows && reject_dropped_rows(verb, gd)
    out = Output{C}(verb, keeprows)
    run_all!(Context(parent(gd), rowgroups(gd), out, renamecols, copycols), args)
    return out
end

function key_columns(gd::GroupedFrame{C}, target::Vector{Int}, keeprows::Bool) where {C}
    df = parent(gd)
    keys = groupcols(gd)
    keeprows && return C[copycolumn(C, column(df, k))::C for k in keys]

    firstrows = Int[rowgroups(gd).rows[s] for s in rowgroups(gd).starts]
    rows = firstrows[repeat_rows(target)]
    return C[takerows(C, column(df, k), rows)::C for k in keys]
end

function check_key_column(name::Symbol, aligned::Vector{C}, i::Int, keycols::Vector{C}, position::Int) where {C}
    if !(columnsequal(isequal, aligned, i, keycols, position)::Bool)
        throw(ArgumentError(string("column :", name, " in returned data frame is not equal to grouping key :", name)))
    end
end

function finish(out::Output{C}, gd::GroupedFrame{C}, keepkeys::Bool) where {C}
    segments = rowgroups(gd)
    target = target_lengths(out, segments)
    aligned = aligned_columns(out, segments, target)
    keepkeys || return result_frame(out, aligned)

    keys = groupcols(gd)
    keycols = key_columns(gd, target, out.keeprows)
    names = copy(keys)
    cols = copy(keycols)
    for i in eachindex(out.names)
        name = out.names[i]
        position = findfirst(==(name), keys)
        if position === nothing
            push!(names, name)
            push!(cols, aligned[i])
        else
            check_key_column(name, aligned, i, keycols, position)
        end
    end
    return Frame{C}(names, cols)
end

function restore_parent_order(result::Frame{C}, gd::GroupedFrame{C}) where {C}
    parent_names = columnnames(parent(gd))
    ordered = Symbol[n for n in parent_names if hasproperty(result, n)]
    append!(ordered, Symbol[n for n in columnnames(result) if !(n in parent_names)])
    return columns_frame(result, ordered, false)
end

@specialized_args function select(gd::GroupedFrame, args...; copycols::Bool = true, keepkeys::Bool = true, renamecols::Bool = true, threads::Bool = true)
    return finish(manipulate(:select, gd, args, true, renamecols, copycols), gd, keepkeys)
end

@specialized_args function transform(gd::GroupedFrame, args...; copycols::Bool = true, keepkeys::Bool = true, renamecols::Bool = true, threads::Bool = true)
    out = manipulate(:transform, gd, (:, args...), true, renamecols, copycols)
    return restore_parent_order(finish(out, gd, keepkeys), gd)
end

@specialized_args function combine(gd::GroupedFrame, args...; keepkeys::Bool = true, renamecols::Bool = true, threads::Bool = true)
    return finish(manipulate(:combine, gd, args, false, renamecols, true), gd, keepkeys)
end

@specialized_args function select!(gd::GroupedFrame, args...; renamecols::Bool = true, threads::Bool = true)
    replace_contents!(parent(gd), select(gd, args...; copycols = false, renamecols = renamecols))
    return parent(gd)
end

@specialized_args function transform!(gd::GroupedFrame, args...; renamecols::Bool = true, threads::Bool = true)
    replace_contents!(parent(gd), transform(gd, args...; copycols = false, renamecols = renamecols))
    return parent(gd)
end

function bad_condition(number::Int, x)
    if x === missing
        throw(ArgumentError(string(
            "missing was returned in condition number ", number,
            " but only true or false are allowed; pass skipmissing=true to skip missing values",
        )))
    end
    throw(ArgumentError(string(
        "value of type ", typelabel(typeof(x)), " was returned in condition number ", number,
        " but only true, false or missing are allowed",
    )))
end

function apply_condition!(mask::Vector{Bool}, row::Int, x, number::Int, skipmissing::Bool)
    if x === true
        return nothing
    elseif x === false || (skipmissing && x === missing)
        mask[row] = false
        return nothing
    end
    return bad_condition(number, x)
end

function condition_rows!(mask, rows, r::AbstractVector, number, skipmissing)
    if length(r) != length(rows)
        throw(ArgumentError(string(
            "condition number ", number, " returned ", length(r),
            " values for ", length(rows), " rows",
        )))
    end
    for (row, x) in zip(rows, r)
        apply_condition!(mask, row, x, number, skipmissing)
    end
end

function scalar_condition_error(number::Int, ::Type{T}) where {T}
    throw(ArgumentError(string(
        "function passed to `subset`/`subset!` returned value of type `", typelabel(T),
        "` while it must return an `AbstractVector` when subsetting a data frame",
    )))
end

condition_rows!(mask, rows, x, number, skipmissing) = begin
    for row in rows
        apply_condition!(mask, row, x, number, skipmissing)
    end
end

struct ConditionSink{S}
    segments::S
    mask::Vector{Bool}
    number::Int
    skipmissing::Bool
end

function (sink::ConditionSink{S})(results::Vector{R}) where {S,R}
    if S === WholeFrame && !(R <: AbstractVector)
        scalar_condition_error(sink.number, R)
    end
    for g in eachindex(results)
        rows = segmentrows(sink.segments, g)
        condition_rows!(sink.mask, rows, results[g], sink.number, sink.skipmissing)
    end
    return nothing
end

struct ApplyCondition{F,S}
    f::F
    sink::ConditionSink{S}
end

function (a::ApplyCondition)(cols::Tuple)
    a.sink(apply_segments(a.f, a.sink.segments, cols, false))
    return nothing
end

function condition_columns!(df::Frame, sink, names::NTuple{N,Symbol}, f::F) where {N,F}
    indices = map(n -> columnindex(df, n), names)
    splitcolumns(ApplyCondition(f, sink), columns(df), indices)
    return nothing
end

function condition_vector!(df::Frame, sink, names::Vector{Symbol}, f::F) where {F}
    n = length(names)
    if n == 1 && accepts(f, Val(1))
        return condition_columns!(df, sink, (names[1],), f)
    elseif n == 2 && accepts(f, Val(2))
        return condition_columns!(df, sink, (names[1], names[2]), f)
    elseif n == 3 && accepts(f, Val(3))
        return condition_columns!(df, sink, (names[1], names[2], names[3]), f)
    end
    throw(ArgumentError(string(
        "subset: condition number ", sink.number, " needs a tuple source, (:a, :b, ...) => f: ",
        "a vector source supports at most ", MAX_VECTOR_SOURCE, " columns",
    )))
end

condition!(df::Frame, sink, source::ColumnRef, f::F) where {F} =
    condition_columns!(df, sink, (source_name(df, source),), f)
condition!(df::Frame, sink, source::Tuple, f::F) where {F} =
    condition_columns!(df, sink, map(s -> source_name(df, s), source), f)
condition!(df::Frame, sink, source::AsTable{Val{Names}}, f::F) where {Names,F} =
    condition_columns!(df, sink, Names, with_names(Val(Names), f))
condition!(df::Frame, sink, source, f::F) where {F} =
    condition_vector!(df, sink, selectnames(df, source), f)

run_conditions!(df, segments, mask, skipmissing, number, ::Tuple{}) = mask
function run_conditions!(df, segments, mask, skipmissing, number, args::Tuple)
    p = first(args)
    condition!(df, ConditionSink(segments, mask, number, skipmissing), p.first, condition_function(p.second))
    return run_conditions!(df, segments, mask, skipmissing, number + 1, Base.tail(args))
end

condition_function(f) = f
condition_function(p::Pair) = p.first

function reject_view(view::Bool)
    view && throw(ArgumentError("subset: view=true is not supported, TrimmableFrames has no frame views"))
end

@specialized_args function subset(df::Frame, args...; skipmissing::Bool = false, view::Bool = false, threads::Bool = true)
    reject_view(view)
    mask = run_conditions!(df, WholeFrame(nrow(df)), fill(true, nrow(df)), skipmissing, 1, args)
    return take_frame(df, findall(mask))
end

@specialized_args function subset(gd::GroupedFrame, args...; skipmissing::Bool = false, view::Bool = false, threads::Bool = true)
    reject_view(view)
    reject_dropped_rows(:subset, gd)
    df = parent(gd)
    mask = run_conditions!(df, rowgroups(gd), fill(true, nrow(df)), skipmissing, 1, args)
    return take_frame(df, findall(mask))
end

@specialized_args function subset!(df::Frame, args...; skipmissing::Bool = false, threads::Bool = true)
    return replace_contents!(df, subset(df, args...; skipmissing = skipmissing))
end

@specialized_args function subset!(gd::GroupedFrame, args...; skipmissing::Bool = false, threads::Bool = true)
    replace_contents!(parent(gd), subset(gd, args...; skipmissing = skipmissing))
    return parent(gd)
end
