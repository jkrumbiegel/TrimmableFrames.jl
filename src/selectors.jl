struct Not{T}
    selection::T
end
Not(selections::Vararg{Any,N}) where {N} = Not(Cols(selections...))

struct Cols{T<:Tuple}
    selections::T
end
Cols(selections::Vararg{Any,N}) where {N} = Cols(selections)

struct All end

struct Between{A,B}
    first::A
    last::B
end

"""
    selectnames(df, selection)

The column names picked by `selection`, a run-time list of `Symbol`s.
"""
selectnames(df::Frame, ref::ColumnRef) = Symbol[columnnames(df)[columnindex(df, ref)]]
selectnames(df::Frame, ::Colon) = copy(columnnames(df))
selectnames(df::Frame, ::All) = copy(columnnames(df))
selectnames(df::Frame, refs::AbstractVector{<:ColumnRef}) = Symbol[columnnames(df)[columnindex(df, r)] for r in refs]
selectnames(df::Frame, refs::Tuple) = selectnames(df, Cols(refs))
selectnames(df::Frame, mask::AbstractVector{Bool}) = columnnames(df)[mask]
selectnames(df::Frame, refs::AbstractVector) =
    isempty(refs) ? Symbol[] : Symbol[columnnames(df)[columnindex(df, r)] for r in refs]

function selectnames(df::Frame, sel::Not)
    excluded = selectnames(df, sel.selection)
    return Symbol[n for n in columnnames(df) if !(n in excluded)]
end

function selectnames(df::Frame, sel::Between)
    from = columnindex(df, sel.first)
    to = columnindex(df, sel.last)
    return columnnames(df)[from:to]
end

selectnames_into!(out, df) = out
function selectnames_into!(out, df, sel, rest...)
    for name in selectnames(df, sel)
        name in out || push!(out, name)
    end
    return selectnames_into!(out, df, rest...)
end

selectnames(df::Frame, sel::Cols) = selectnames_into!(Symbol[], df, sel.selections...)
