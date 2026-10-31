member_index(::Type{C}, ::Type{E}) where {C,E} = something(findfirst(==(Vector{E}), collect(Any, columnmembers(C))), 0)

@generated function member_position(::Type{C}, col) where {C}
    branches = [:(col isa $T && return $i) for (i, T) in enumerate(columnmembers(C))]
    return Expr(:block, branches..., :(unreachable_column()))
end

@generated member_labels(::Type{C}) where {C} = Tuple(string(eltype(T)) for T in columnmembers(C))

@generated function promotion_table(::Type{C}) where {C}
    members = columnmembers(C)
    n = length(members)
    rows = map(1:n) do i
        map(1:n) do j
            joined = promote_type(eltype(members[i]), eltype(members[j]))
            member_index(C, joined), string(joined)
        end
    end
    return Tuple(Tuple(r) for r in rows)
end

@generated function with_missing_table(::Type{C}) where {C}
    return Tuple(map(columnmembers(C)) do T
        joined = Union{Missing,eltype(T)}
        member_index(C, joined), string(joined)
    end)
end

const NO_COLUMN = 0

"""
The position in the column union of the common type of `current` and member `position`, or
an error that names `vcat` and the column.
"""
function promoted_position(::Type{C}, current::Int, position::Int, name::Symbol) where {C}
    current == NO_COLUMN && return position
    target, label = promotion_table(C)[current][position]
    target == 0 && promotion_error(C, current, position, label, name)
    return target
end

function promotion_error(::Type{C}, current::Int, position::Int, label::String, name::Symbol) where {C}
    labels = member_labels(C)
    throw(ColumnTypeError(string(
        "vcat: column :", name, " combines element types ", labels[current], " and ", labels[position],
        " into ", label, ", which is not among the allowed column types (", allowedlabel(C), ")",
    )))
end

function with_missing_position(::Type{C}, position::Int, name::Symbol) where {C}
    target, label = with_missing_table(C)[position]
    if target == 0
        throw(ColumnTypeError(string(
            "vcat: column :", name, " needs element type ", label,
            ", which is not among the allowed column types (", allowedlabel(C), ")",
        )))
    end
    return target
end

function copy_converted!(out::Vector{T}, start::Int, col::Vector{S}) where {T,S}
    if S <: T || promote_type(S, T) === T
        for i in eachindex(col)
            out[start + i - 1] = col[i]
        end
    else
        unreachable_column()
    end
    return out
end

struct ColumnSources{C}
    name::Symbol
    pieces::Vector{C}
    lengths::Vector{Int}
    present::Vector{Bool}
end

@generated function allocate_member(::Type{C}, position::Int, n::Int) where {C}
    branches = [:(position == $i && return Vector{$(eltype(T))}(undef, n)::C) for (i, T) in enumerate(columnmembers(C))]
    return Expr(:block, branches..., :(unreachable_column()))
end

function fill_gaps!(out::Vector{T}, start::Int, n::Int) where {T}
    if Missing <: T
        for i in start:(start + n - 1)
            out[i] = missing
        end
    else
        unreachable_column()
    end
    return out
end

function concat_into!(out::Vector, sources::ColumnSources{C}) where {C}
    position = 1
    piece = 1
    for (present, n) in zip(sources.present, sources.lengths)
        if present
            splitcolumn(c -> (copy_converted!(out, position, c); nothing), C, sources.pieces[piece])
            piece += 1
        else
            fill_gaps!(out, position, n)
        end
        position += n
    end
    return out
end

holds_missing_only(col::Vector{T}) where {T} = Missing <: T && !isempty(col) && all(ismissing, col)

function concat_column(sources::ColumnSources{C}) where {C}
    target = NO_COLUMN
    for piece in sources.pieces
        target = promoted_position(C, target, member_position(C, piece), sources.name)
    end
    if !all(sources.present)
        target = with_missing_position(C, target, sources.name)
    end
    out = allocate_member(C, target, sum(sources.lengths))
    return splitcolumn(v -> concat_into!(v, sources), C, out)::Vector
end

function union_names(frames::Vector{<:Frame})
    names = Symbol[]
    for df in frames
        for name in columnnames(df)
            name in names || push!(names, name)
        end
    end
    return names
end

function intersect_names(frames::Vector{<:Frame})
    return Symbol[n for n in columnnames(frames[1]) if all(df -> hasproperty(df, n), frames)]
end

function set_equal_names(frames::Vector{<:Frame})
    names = columnnames(frames[1])
    for (i, df) in enumerate(frames)
        absent = Symbol[n for n in union_names(frames) if !hasproperty(df, n)]
        if !isempty(absent)
            throw(ArgumentError(string("column(s) ", joined_names(absent), " are missing from argument(s) ", i)))
        end
    end
    return copy(names)
end

function order_equal_names(frames::Vector{<:Frame})
    names = columnnames(frames[1])
    for df in frames
        if columnnames(df) != names
            throw(ArgumentError("when `cols=:orderequal` all data frames need to have the same column names and be in the same order"))
        end
    end
    return copy(names)
end

function vcat_names(frames::Vector{<:Frame}, cols::Symbol)
    cols === :setequal && return set_equal_names(frames)
    cols === :orderequal && return order_equal_names(frames)
    cols === :intersect && return intersect_names(frames)
    cols === :union && return union_names(frames)
    throw(ArgumentError(string("Invalid `cols` value :", cols, ", only :orderequal, :setequal, :intersect, :union or a vector of column names are allowed")))
end

function vcat_names(frames::Vector{<:Frame}, cols::AbstractVector)
    return Symbol[Symbol(c) for c in cols]
end

function source_column(frames::Vector{Frame{C}}, source::Symbol, ::Type{C}) where {C}
    return source_labels(frames, collect(1:length(frames)), C, source)
end

function source_labels(frames::Vector{Frame{C}}, labels::AbstractVector, ::Type{C}, name::Symbol) where {C}
    if length(labels) != length(frames)
        throw(ArgumentError(string("got ", length(labels), " source labels for ", length(frames), " frames")))
    end
    values = reduce(vcat, [fill(labels[i], nrow(df)) for (i, df) in enumerate(frames)])
    return fitcolumn(C, :vcat, name, values, false)
end

add_source!(names, cols, frames, ::Nothing, ::Type{C}) where {C} = nothing

function add_source!(names, cols, frames, source::Union{Symbol,AbstractString}, ::Type{C}) where {C}
    name = Symbol(source)
    check_source_name(names, name)
    push!(names, name)
    push!(cols, source_column(frames, name, C))
    return nothing
end

function add_source!(names, cols, frames, source::Pair, ::Type{C}) where {C}
    name = Symbol(source.first)
    check_source_name(names, name)
    push!(names, name)
    push!(cols, source_labels(frames, source.second, C, name))
    return nothing
end

function check_source_name(names::Vector{Symbol}, name::Symbol)
    if name in names
        throw(ArgumentError(string("source column name :", name, " already exists in data frame ")))
    end
end

function column_sources(frames::Vector{Frame{C}}, name::Symbol, lengths::Vector{Int}) where {C}
    pieces = C[]
    present = fill(false, length(frames))
    fallback = 0
    for (i, df) in enumerate(frames)
        hasproperty(df, name) || continue
        fallback = fallback == 0 ? i : fallback
        col = column(df, name)
        if !(splitcolumn(holds_missing_only, C, col)::Bool)
            push!(pieces, col)
            present[i] = true
        end
    end
    if isempty(pieces) && fallback != 0
        push!(pieces, column(frames[fallback], name))
        present[fallback] = true
    end
    return ColumnSources{C}(name, pieces, lengths, present)
end

function vcat_frames(frames::Vector{Frame{C}}, cols, source) where {C}
    kept = Frame{C}[df for df in frames if ncol(df) > 0]
    isempty(kept) && return Frame{C}()

    names = vcat_names(kept, cols)
    outcols = C[]
    lengths = Int[nrow(df) for df in kept]
    for name in names
        push!(outcols, concat_column(column_sources(kept, name, lengths)))
    end
    add_source!(names, outcols, kept, source, C)
    return Frame{C}(names, outcols)
end

function Base.vcat(frames::Vararg{Frame{C},N}; cols = :setequal, source = nothing) where {C,N}
    return vcat_frames(Frame{C}[frames...], cols, source)
end

Base.reduce(::typeof(vcat), frames::AbstractVector{Frame{C}}; cols = :setequal, source = nothing) where {C} =
    vcat_frames(convert(Vector{Frame{C}}, frames), cols, source)
