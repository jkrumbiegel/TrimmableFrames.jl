"""
    Frame{C}

A column table whose columns are `Vector`s of the types in the union `C`. Column names,
their number and which member of `C` each column has are run-time data. Use
[`frametype`](@ref) to build the type.
"""
struct Frame{C}
    names::Vector{Symbol}
    cols::Vector{C}

    function Frame{C}(names::Vector{Symbol}, cols::Vector{C}) where {C}
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
        return new{C}(names, cols)
    end
end

"""
    frametype(T...; allowmissing=false)

The `Frame` type whose columns may have the element types `T...`. With
`allowmissing=true`, `Union{Missing,T}` is allowed for each `T` too. Single element types
can also be listed as `Union{Missing,T}` directly.

```julia
const DataFrame = frametype(String, Int64, Float64, Bool; allowmissing=true)
df = DataFrame(a=1:3, b=["x", "y", "z"])
```
"""
function frametype(types...; allowmissing::Bool = false)
    all_types = allowmissing ? (types..., map(T -> Union{Missing,T}, types)...) : types
    return Frame{Union{map(T -> Vector{T}, all_types)...}}
end

columnnames(df::Frame) = getfield(df, :names)
columns(df::Frame) = getfield(df, :cols)
columnunion(::Frame{C}) where {C} = C
columnunion(::Type{Frame{C}}) where {C} = C

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
nrow(df::Frame{C}) where {C} = ncol(df) == 0 ? 0 : columnlength(C, columns(df)[1])
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
    fitted = fitcolumn(C, verb, name, v, false)
    return copycols && fitted === v ? copycolumn(C, fitted) : fitted
end

iscolumn(::AbstractVector) = true
iscolumn(::Any) = false

function constructor_rows(values::Tuple)
    n = -1
    for v in values
        if iscolumn(v)
            n = n == -1 ? length(v) : n
        end
    end
    return n == -1 ? 1 : n
end

to_constructor_column(::Type{C}, name, v::AbstractVector, n, copycols, verb) where {C} = to_column(C, verb, name, v, copycols)
to_constructor_column(::Type{C}, name, x, n, copycols, verb) where {C} = fitcolumn(C, verb, name, fill(x, n), false)

function fromvalues(::Type{Frame{C}}, names::Vector{Symbol}, values::Tuple, copycols::Bool) where {C}
    n = constructor_rows(values)
    cols = C[]
    append_columns!(cols, names, 1, values, n, copycols, C)
    return Frame{C}(names, cols)
end

append_columns!(cols, names, i, ::Tuple{}, n, copycols, ::Type{C}) where {C} = cols
function append_columns!(cols, names, i, values::Tuple, n, copycols, ::Type{C}) where {C}
    push!(cols, to_constructor_column(C, names[i], first(values), n, copycols, :constructor))
    return append_columns!(cols, names, i + 1, Base.tail(values), n, copycols, C)
end

function (::Type{Frame{C}})(; copycols::Bool = true, kwargs...) where {C}
    isempty(kwargs) && return Frame{C}(Symbol[], C[])
    nt = values(kwargs)
    return fromvalues(Frame{C}, Symbol[keys(nt)...], Tuple(nt), copycols)
end

function (::Type{Frame{C}})(pairs::Vararg{Pair,N}; copycols::Bool = true) where {C,N}
    return fromvalues(Frame{C}, Symbol[Symbol(p.first) for p in pairs], map(last, pairs), copycols)
end

function (::Type{Frame{C}})(nt::NamedTuple; copycols::Bool = true) where {C}
    return fromvalues(Frame{C}, Symbol[keys(nt)...], Tuple(nt), copycols)
end

function (::Type{Frame{C}})(pairs::AbstractVector{<:Pair}; copycols::Bool = true) where {C}
    names = Symbol[Symbol(p.first) for p in pairs]
    cols = C[]
    for (i, p) in enumerate(pairs)
        push!(cols, to_column(C, :constructor, names[i], p.second, copycols))
    end
    return Frame{C}(names, cols)
end

function (::Type{Frame{C}})(values::AbstractVector, names::AbstractVector; copycols::Bool = true) where {C}
    symbols = Symbol[Symbol(n) for n in names]
    cols = C[]
    for (i, v) in enumerate(values)
        push!(cols, to_column(C, :constructor, symbols[i], v, copycols))
    end
    return Frame{C}(symbols, cols)
end

(::Type{Frame{C}})(df::Frame{C}) where {C} = copy(df)

Base.copy(df::Frame{C}) where {C} = Frame{C}(copy(columnnames(df)), C[copycolumn(C, c) for c in columns(df)])

function take_frame(df::Frame{C}, rows::AbstractVector{Int}) where {C}
    return Frame{C}(copy(columnnames(df)), C[takerows(C, c, rows) for c in columns(df)])
end

Base.first(df::Frame, n::Integer) = take_frame(df, 1:min(n, nrow(df)))
Base.last(df::Frame, n::Integer) = take_frame(df, max(nrow(df) - n + 1, 1):nrow(df))

rowindices(df::Frame, rows::AbstractVector{Bool}) = findall(rows)
rowindices(df::Frame, rows::AbstractVector{<:Integer}) = convert(Vector{Int}, rows)
rowindices(df::Frame, ::Colon) = 1:nrow(df)

function columns_frame(df::Frame{C}, names::Vector{Symbol}, copied::Bool) where {C}
    cols = C[column(df, n) for n in names]
    return Frame{C}(names, copied ? C[copycolumn(C, c) for c in cols] : cols)
end

Base.getindex(df::Frame, ::typeof(!), ref::ColumnRef) = column(df, ref)
Base.getindex(df::Frame, ::typeof(!), sel) = columns_frame(df, selectnames(df, sel), false)
Base.getindex(df::Frame{C}, ::Colon, ref::ColumnRef) where {C} = copycolumn(C, column(df, ref))
Base.getindex(df::Frame, ::Colon, sel) = columns_frame(df, selectnames(df, sel), true)
Base.getindex(df::Frame, rows::AbstractVector, ::Colon) = take_frame(df, rowindices(df, rows))
Base.getindex(df::Frame{C}, rows::AbstractVector, ref::ColumnRef) where {C} =
    takerows(C, column(df, ref), rowindices(df, rows))
Base.getindex(df::Frame, rows::AbstractVector, sel) =
    take_frame(columns_frame(df, selectnames(df, sel), false), rowindices(df, rows))
Base.getindex(df::Frame{C}, row::Integer, ref::ColumnRef) where {C} =
    splitcolumn(c -> c[row], C, column(df, ref))

function check_length(df::Frame{C}, name::Symbol, col) where {C}
    if ncol(df) > 0 && columnlength(C, col) != nrow(df)
        throw(ArgumentError(string(
            "New columns must have the same length as old columns: column :", name,
            " has length ", columnlength(C, col), ", expected ", nrow(df),
        )))
    end
end

function setcolumn!(df::Frame{C}, name::Symbol, value, verb::Symbol) where {C}
    col = fitcolumn(C, verb, name, value isa AbstractVector ? value : fill(value, nrow(df)), false)
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

insert_next!(df, position, copycols, n) = df
function insert_next!(df::Frame{C}, position, copycols, n, p::Pair, rest...) where {C}
    name = Symbol(p.first)
    if hasproperty(df, name)
        throw(ArgumentError(string("Column ", name, " is already present in the data frame which is not allowed when `makeunique=false`")))
    end
    col = to_constructor_column(C, name, p.second, n, copycols, :insertcols!)
    check_length(df, name, col)
    insert!(columnnames(df), position, name)
    insert!(columns(df), position, col)
    return insert_next!(df, position + 1, copycols, n, rest...)
end

function insertcols!(df::Frame, at::ColumnRef, pairs::Vararg{Pair,N}; after::Bool = false, copycols::Bool = true) where {N}
    n = ncol(df) == 0 ? constructor_rows(map(last, pairs)) : nrow(df)
    return insert_next!(df, insert_position(df, at, after), copycols, n, pairs...)
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

rename_next!(names, df_names) = names
function rename_next!(names, df_names, p::Pair, rest...)
    rename_one!(names, df_names, Symbol(p.first), Symbol(p.second))
    return rename_next!(names, df_names, rest...)
end

function replace_names!(df::Frame, renamed::Vector{Symbol})
    allunique(renamed) || throw(ArgumentError("duplicate column names after renaming"))
    copyto!(columnnames(df), renamed)
    return df
end

function rename!(df::Frame, pairs::Vararg{Pair,N}) where {N}
    return replace_names!(df, rename_next!(copy(columnnames(df)), columnnames(df), pairs...))
end

function rename!(df::Frame, names::AbstractVector)
    if length(names) != ncol(df)
        throw(DimensionMismatch(string("got ", length(names), " names for ", ncol(df), " columns")))
    end
    return replace_names!(df, Symbol[Symbol(n) for n in names])
end

rename!(f::Function, df::Frame) = rename!(df, String[f(n) for n in names(df)])
rename(df::Frame, args::Vararg{Any,N}) where {N} = rename!(copy(df), args...)
rename(f::Function, df::Frame) = rename!(f, copy(df))

function frames_equal(same::F, a::Frame{C}, b::Frame{C}) where {F,C}
    columnnames(a) == columnnames(b) || return false
    result = true
    for i in 1:ncol(a)
        equal = columnsequal(same, columns(a)[i], columns(b)[i], C)
        if equal === missing
            result = missing
        elseif !equal
            return false
        end
    end
    return result
end

Base.:(==)(a::Frame{C}, b::Frame{C}) where {C} = frames_equal(==, a, b)
Base.isequal(a::Frame{C}, b::Frame{C}) where {C} = frames_equal(isequal, a, b)::Bool

columntypelabel(::Type{C}, col) where {C} = splitcolumn(c -> shortlabel(eltype(c)), C, col)::String
shortlabel(::Type{T}) where {T} = Missing <: T ? string(typelabel(nonmissingtype(T)), "?") : typelabel(T)

cellstring(::Type{C}, col, row::Int) where {C} = splitcolumn(c -> string(c[row]), C, col)::String

function pad(s::String, width::Int)
    return string(s, repeat(" ", max(width - length(s), 0)))
end

function Base.show(io::IO, df::Frame{C}) where {C}
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
    print(io, "\n", repeat("─", rowwidth + 2), "┼", repeat("─", sum(widths) + 2 * (length(widths) - 1) + 2))
    for row in 1:nrow(df)
        label = string(row)
        print(io, "\n ", repeat(" ", rowwidth - length(label)), label, " │ ")
        print(io, rstrip(join([pad(rows[j][row], widths[j]) for j in eachindex(cols)], "  ")))
    end
end
