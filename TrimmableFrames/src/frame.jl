struct Metadata{M}
    table::Dict{String,M}
    columns::Dict{Symbol,Dict{String,M}}
end

Metadata{M}() where {M} = Metadata{M}(Dict{String,M}(), Dict{Symbol,Dict{String,M}}())

"""
    Frame{C,M}

A column table whose columns are `Vector`s of the types in the union `C`, with metadata
values of the types in the union `M`. Column names, their number, which member of `C` each
column has and the metadata keys are run-time data. Use [`frametype`](@ref) to build the type.
"""
struct Frame{C,M}
    names::Vector{Symbol}
    cols::Vector{C}
    metadata::Metadata{M}

    function Frame{C,M}(names::Vector{Symbol}, cols::Vector{C}, metadata::Metadata{M} = Metadata{M}()) where {C,M}
        if length(names) != length(cols)
            throw(ArgumentError("got $(length(cols)) columns but $(length(names)) names"))
        end
        allunique(names) || throw(ArgumentError("duplicate column names"))
        for i in 2:length(cols)
            len = columnlength(C, cols[i])
            expected = columnlength(C, cols[1])
            if len != expected
                throw(DimensionMismatch(string("column :", names[i], " has length ", len, ", expected ", expected)))
            end
        end
        return new{C,M}(names, cols, metadata)
    end
end

"""
    frametype(T...; allowmissing=false, metadata=String)

The `Frame` type whose columns may have the element types `T...`. With
`allowmissing=true`, `Union{Missing,T}` is allowed for each `T` too. Single element types
can also be listed as `Union{Missing,T}` directly. `metadata` is the concrete type of
metadata values, or a tuple of them.

```julia
const DataFrame = frametype(String, Int64, Float64, Bool; allowmissing=true)
df = DataFrame(a=1:3, b=["x", "y", "z"])
```
"""
function frametype(types...; allowmissing::Bool = false, metadata = String)
    all_types = allowmissing ? (types..., map(T -> Union{Missing,T}, types)...) : types
    return Frame{Union{map(T -> Vector{T}, all_types)...},metadata_union(metadata)}
end

metadata_union(T::Type) = metadata_union((T,))

function metadata_union(types::Tuple)
    for T in types
        isconcretetype(T) || throw(ArgumentError(string("metadata types must be concrete, got ", T)))
    end
    return Union{types...}
end

columnnames(df::Frame) = getfield(df, :names)
columns(df::Frame) = getfield(df, :cols)
frame_metadata(df::Frame) = getfield(df, :metadata)

"""
    columnunion(FrameType)

The union of allowed column types. `columnunion(DF)[[1, 2], ["x", "y"]]` is a column vector
for `DF(cols, names)` whose elements keep their type through compilation.
"""
columnunion(::Frame{C}) where {C} = C
columnunion(::Type{<:Frame{C}}) where {C} = C

const ColumnRef = Union{Symbol,AbstractString,Integer}

not_found(name::Symbol) = throw(ArgumentError(string("column name :", name, " not found in the data frame")))

function maybe_columnindex(df::Frame, name::Symbol)
    all_names = columnnames(df)
    for i in eachindex(all_names)
        all_names[i] === name && return i
    end
    return 0
end

function columnindex(df::Frame, name::Symbol)
    i = maybe_columnindex(df, name)
    i == 0 && not_found(name)
    return i
end
columnindex(df::Frame, name::AbstractString) = columnindex(df, Symbol(name))

function columnindex(df::Frame, i::Integer)
    if !(1 <= i <= ncol(df))
        throw(ArgumentError(string("column index ", i, " is out of bounds for a frame with ", ncol(df), " columns")))
    end
    return Int(i)
end

column(df::Frame, ref::ColumnRef) = columns(df)[columnindex(df, ref)]

ncol(df::Frame) = length(columnnames(df))
nrow(df::Frame{C,M}) where {C,M} = ncol(df) == 0 ? 0 : columnlength(C, columns(df)[1])
Base.size(df::Frame) = (nrow(df), ncol(df))
Base.size(df::Frame, dim::Integer) = size(df)[dim]
Base.names(df::Frame) = String[string(n) for n in columnnames(df)]
Base.propertynames(df::Frame, ::Bool = false) = copy(columnnames(df))
Base.hasproperty(df::Frame, name::Symbol) = maybe_columnindex(df, name) != 0
Base.eachcol(df::Frame) = columns(df)
Base.isempty(df::Frame) = nrow(df) == 0 || ncol(df) == 0

Base.getproperty(df::Frame, name::Symbol) = column(df, name)
Base.setproperty!(df::Frame, name::Symbol, value) = (setcolumn!(df, name, value, :setproperty!); value)

function to_column(::Type{C}, verb::Symbol, name::Symbol, v::AbstractVector, copycols::Bool) where {C}
    fitted = fitcolumn(C, verb, name, v, false)::C
    return (copycols && fitted === v ? copycolumn(C, fitted)::C : fitted)::C
end

iscolumn(::AbstractVector) = true
iscolumn(::Any) = false

constructor_rows(::Tuple{}) = 1
constructor_rows(values::Tuple) =
    iscolumn(first(values)) ? length(first(values)) : constructor_rows(Base.tail(values))

to_constructor_column(::Type{C}, name, v::AbstractVector, n, copycols, verb) where {C} = to_column(C, verb, name, v, copycols)
to_constructor_column(::Type{C}, name, x, n, copycols, verb) where {C} = fitcolumn(C, verb, name, fill(x, n), false)::C

function fromvalues(::Type{Frame{C,M}}, names::Vector{Symbol}, values::Tuple, copycols::Bool) where {C,M}
    n = constructor_rows(values)
    cols = C[]
    append_columns!(cols, names, 1, values, n, copycols, C)
    return Frame{C,M}(names, cols)
end

append_columns!(cols, names, i, ::Tuple{}, n, copycols, ::Type{C}) where {C} = cols
function append_columns!(cols, names, i, values::Tuple, n, copycols, ::Type{C}) where {C}
    push!(cols, to_constructor_column(C, names[i], first(values), n, copycols, :constructor)::C)
    return append_columns!(cols, names, i + 1, Base.tail(values), n, copycols, C)
end

function (::Type{Frame{C,M}})(; copycols::Bool = true, kwargs...) where {C,M}
    isempty(kwargs) && return Frame{C,M}(Symbol[], C[])
    nt = values(kwargs)
    return fromvalues(Frame{C,M}, Symbol[keys(nt)...], Tuple(nt), copycols)
end

function (::Type{Frame{C,M}})(pairs::Vararg{Pair,N}; copycols::Bool = true) where {C,M,N}
    return fromvalues(Frame{C,M}, Symbol[map(p -> Symbol(p.first), pairs)...], map(last, pairs), copycols)
end

function (::Type{Frame{C,M}})(nt::NamedTuple; copycols::Bool = true) where {C,M}
    return fromvalues(Frame{C,M}, Symbol[keys(nt)...], Tuple(nt), copycols)
end

function (::Type{Frame{C,M}})(pairs::AbstractVector{<:Pair}; copycols::Bool = true) where {C,M}
    names = Symbol[Symbol(p.first) for p in pairs]
    cols = C[]
    for (i, p) in enumerate(pairs)
        push!(cols, to_column(C, :constructor, names[i], p.second, copycols)::C)
    end
    return Frame{C,M}(names, cols)
end

function (::Type{Frame{C,M}})(values::AbstractVector, names::AbstractVector; copycols::Bool = true) where {C,M}
    symbols = Symbol[Symbol(n) for n in names]
    cols = C[]
    for (i, v) in enumerate(values)
        push!(cols, to_column(C, :constructor, symbols[i], v, copycols)::C)
    end
    return Frame{C,M}(symbols, cols)
end

(::Type{Frame{C,M}})(df::Frame{C,M}) where {C,M} = copy(df)

Base.copy(df::Frame{C,M}) where {C,M} =
    Frame{C,M}(copy(columnnames(df)), C[copycolumn(C, c)::C for c in columns(df)], copy(frame_metadata(df)))

function take_frame(df::Frame{C,M}, rows::AbstractVector{Int}) where {C,M}
    return Frame{C,M}(copy(columnnames(df)), C[takerows(C, c, rows)::C for c in columns(df)], copy(frame_metadata(df)))
end

Base.first(df::Frame, n::Integer) = take_frame(df, 1:min(n, nrow(df)))
Base.last(df::Frame, n::Integer) = take_frame(df, max(nrow(df) - n + 1, 1):nrow(df))

rowindices(df::Frame, rows::AbstractVector{Bool}) = findall(rows)
rowindices(df::Frame, rows::AbstractVector{<:Integer}) = convert(Vector{Int}, rows)
rowindices(df::Frame, ::Colon) = 1:nrow(df)

function columns_frame(df::Frame{C,M}, names::Vector{Symbol}, copied::Bool) where {C,M}
    cols = C[column(df, n) for n in names]
    return Frame{C,M}(names, copied ? C[copycolumn(C, c)::C for c in cols] : cols, selected_metadata(df, names))
end

Base.getindex(df::Frame, ::typeof(!), ref::ColumnRef) = column(df, ref)
Base.getindex(df::Frame, ::typeof(!), sel) = columns_frame(df, selectnames(df, sel), false)
Base.getindex(df::Frame{C,M}, ::Colon, ref::ColumnRef) where {C,M} = copycolumn(C, column(df, ref))::C
Base.getindex(df::Frame, ::Colon, sel) = columns_frame(df, selectnames(df, sel), true)
Base.getindex(df::Frame, rows::AbstractVector, ::Colon) = take_frame(df, rowindices(df, rows))
Base.getindex(df::Frame{C,M}, rows::AbstractVector, ref::ColumnRef) where {C,M} =
    takerows(C, column(df, ref), rowindices(df, rows))::C
Base.getindex(df::Frame, rows::AbstractVector, sel) =
    take_frame(columns_frame(df, selectnames(df, sel), false), rowindices(df, rows))
Base.getindex(df::Frame{C,M}, row::Integer, ref::ColumnRef) where {C,M} =
    splitcolumn(c -> c[row], C, column(df, ref))

function check_length(df::Frame{C,M}, name::Symbol, col) where {C,M}
    if ncol(df) > 0 && columnlength(C, col)::Int != nrow(df)
        throw(ArgumentError(string(
            "New columns must have the same length as old columns: column :", name,
            " has length ", columnlength(C, col), ", expected ", nrow(df),
        )))
    end
end

function setcolumn!(df::Frame{C,M}, name::Symbol, value, verb::Symbol) where {C,M}
    col = fitcolumn(C, verb, name, value isa AbstractVector ? value : fill(value, nrow(df)), false)::C
    if ncol(df) == 1 && maybe_columnindex(df, name) == 1
        columns(df)[1] = col
        return df
    end
    check_length(df, name, col)
    i = maybe_columnindex(df, name)
    if i == 0
        push!(columnnames(df), name)
        push!(columns(df), col)
    else
        columns(df)[i] = col
    end
    return df
end

Base.setindex!(df::Frame, value, ::typeof(!), ref::Union{Symbol,AbstractString}) =
    (setcolumn!(df, Symbol(ref), value, :setindex!); df)
Base.setindex!(df::Frame, value, ::typeof(!), i::Integer) =
    (setcolumn!(df, columnnames(df)[columnindex(df, i)], value, :setindex!); df)

insert_position(df::Frame, at::Integer, after::Bool) = Int(at) + after
insert_position(df::Frame, at::ColumnRef, after::Bool) = columnindex(df, at) + after

insert_next!(df::Frame, position, copycols, n, ::Tuple{}) = df
function insert_next!(df::Frame{C,M}, position, copycols, n, pairs::Tuple{Any,Vararg}) where {C,M}
    p = first(pairs)
    name = Symbol(p.first)
    if hasproperty(df, name)
        throw(ArgumentError(string("Column ", name, " is already present in the data frame which is not allowed when `makeunique=false`")))
    end
    col = to_constructor_column(C, name, p.second, n, copycols, :insertcols!)::C
    check_length(df, name, col)
    insert!(columnnames(df), position, name)
    insert!(columns(df), position, col)
    return insert_next!(df, position + 1, copycols, n, Base.tail(pairs))
end

function insertcols!(df::Frame, at::ColumnRef, pairs::Vararg{Pair,N}; after::Bool = false, copycols::Bool = true) where {N}
    n = ncol(df) == 0 ? constructor_rows(map(last, pairs)) : nrow(df)
    return insert_next!(df, insert_position(df, at, after), copycols, n, pairs)
end

insertcols!(df::Frame, pairs::Vararg{Pair,N}; after::Bool = false, copycols::Bool = true) where {N} =
    insertcols!(df, ncol(df) + 1, pairs...; copycols = copycols)

insertcols(df::Frame, args::Vararg{Any,N}; after::Bool = false, copycols::Bool = true) where {N} =
    insertcols!(copy(df), args...; after = after, copycols = copycols)

function rename_one!(names::Vector{Symbol}, df_names::Vector{Symbol}, from::Symbol, to::Symbol)
    i = findfirst(==(from), df_names)
    i === nothing && not_found(from)
    names[i] = to
    return names
end

rename_next!(names, df_names, ::Tuple{}) = names
function rename_next!(names, df_names, pairs::Tuple{Any,Vararg})
    p = first(pairs)
    rename_one!(names, df_names, Symbol(p.first), Symbol(p.second))
    return rename_next!(names, df_names, Base.tail(pairs))
end

function replace_names!(df::Frame, renamed::Vector{Symbol})
    allunique(renamed) || throw(ArgumentError("duplicate column names after renaming"))
    rename_metadata!(df, renamed)
    copyto!(columnnames(df), renamed)
    return df
end

function rename!(df::Frame, pairs::Vararg{Pair,N}) where {N}
    return replace_names!(df, rename_next!(copy(columnnames(df)), columnnames(df), pairs))
end

function rename!(df::Frame, names::AbstractVector)
    if length(names) != ncol(df)
        throw(DimensionMismatch(string("got ", length(names), " names for ", ncol(df), " columns")))
    end
    return replace_names!(df, Symbol[Symbol(n) for n in names])
end

rename!(f::F, df::Frame) where {F<:Function} = rename!(df, String[f(n) for n in names(df)])
rename(df::Frame, args::Vararg{Any,N}) where {N} = rename!(copy(df), args...)
rename(f::F, df::Frame) where {F<:Function} = rename!(f, copy(df))

function frames_equal(same::F, a::Frame{C,M}, b::Frame{C,M}) where {F,C,M}
    columnnames(a) == columnnames(b) || return false
    result = true
    for i in 1:ncol(a)
        equal = columnsequal(same, columns(a), i, columns(b), i)
        if equal === missing
            result = missing
        elseif !equal
            return false
        end
    end
    return result
end

Base.:(==)(a::Frame{C,M}, b::Frame{C,M}) where {C,M} = frames_equal(==, a, b)
Base.isequal(a::Frame{C,M}, b::Frame{C,M}) where {C,M} = frames_equal(isequal, a, b)::Bool

columntypelabel(::Type{C}, col) where {C} = splitcolumn(c -> shortlabel(eltype(c)), C, col)::String
shortlabel(::Type{T}) where {T} = Missing <: T ? string(typelabel(nonmissingtype(T)), "?") : typelabel(T)

cellstring(::Type{C}, col, row::Int) where {C} = splitcolumn(c -> string(c[row]), C, col)::String

function repeated(c::Char, n::Int)
    io = IOBuffer()
    for _ in 1:n
        print(io, c)
    end
    return String(take!(io))
end

pad(s::String, width::Int) = string(s, repeated(' ', width - length(s)))

function Base.show(io::IO, df::Frame{C,M}) where {C,M}
    cols = columns(df)
    headers = String[string(n) for n in columnnames(df)]
    types = String[columntypelabel(C, c) for c in cols]
    rows = [String[cellstring(C, c, row) for row in 1:nrow(df)] for c in cols]
    widths = Int[maximum(length, vcat(headers[j], types[j], rows[j])) for j in eachindex(cols)]
    rowwidth = max(length(string(nrow(df))), 3)

    print(io, nrow(df), "×", ncol(df), " Frame")
    ncol(df) == 0 && return

    print(io, "\n ", pad("Row", rowwidth), " │ ", rstrip(join(map(pad, headers, widths), "  ")))
    print(io, "\n ", pad("", rowwidth), " │ ", rstrip(join(map(pad, types, widths), "  ")))
    print(io, "\n", repeated('─', rowwidth + 2), "┼", repeated('─', sum(widths) + 2 * (length(widths) - 1) + 2))
    for row in 1:nrow(df)
        label = string(row)
        print(io, "\n ", repeated(' ', rowwidth - length(label)), label, " │ ")
        print(io, rstrip(join([pad(rows[j][row], widths[j]) for j in eachindex(cols)], "  ")))
    end
end
