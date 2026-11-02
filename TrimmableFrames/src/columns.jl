"""
    ColumnTypeError(msg)

Thrown when an operation would produce a column outside the allowed column types of a
frame. `msg` names the operation and the column.
"""
struct ColumnTypeError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ColumnTypeError) = print(io, "ColumnTypeError: ", e.msg)

columnmembers(::Type{C}) where {C} = Base.uniontypes(C)

# Printing a Union at run time needs reflection, so type names are built into the code.
@generated typelabel(::Type{T}) where {T} = unqualified_label(T)

joined_labels(types) = join((unqualified_label(T) for T in types), ", ")

function unqualified_label(::Type{T}) where {T}
    T isa Union && return string("Union{", joined_labels(Base.uniontypes(T)), "}")
    T isa DataType && T <: Tuple && return string("Tuple{", joined_labels(fieldtypes(T)), "}")
    return T isa DataType && isempty(T.parameters) ? string(nameof(T)) : string(T)
end

@generated function allowedlabel(::Type{C}) where {C}
    return join((unqualified_label(eltype(T)) for T in columnmembers(C)), ", ")
end

function column_type_error(verb::Symbol, name::Symbol, label::String, ::Type{C}) where {C}
    msg = string(
        verb === :constructor ? "Frame constructor" : string(verb),
        ": column :", name, " would have element type ", label,
        ", which is not among the allowed column types (", allowedlabel(C), ")",
    )
    throw(ColumnTypeError(msg))
end

unreachable_column() = throw(ArgumentError("value is not a member of the column union"))

"""
    @specialized_args function verb(x, args...; kw...) ... end

Defines `verb` once per argument count with a type parameter per argument. `args::Vararg`
is not enough: for native code Julia widens `Function` arguments that a method only passes
on (`:`, `nrow`, a plain `f`) to `Function`, which leaves a dynamic call. The last method
takes any number of arguments for native use, without that guarantee.
"""
macro specialized_args(definition)
    @assert definition.head === :function
    signature, body = definition.args
    call = signature.head === :where ? signature.args[1] : signature
    outer = signature.head === :where ? signature.args[2:end] : Any[]
    position = findfirst(a -> a isa Expr && a.head === :..., call.args)

    methods = map(0:MAX_SPECIALIZED_ARGS) do n
        values = [Symbol(:arg, i) for i in 1:n]
        types = [Symbol(:Arg, i) for i in 1:n]
        specialized = copy(call)
        splice!(specialized.args, position, Any[:($v::$T) for (v, T) in zip(values, types)])
        typed_body = Expr(:block, :(args = ($(values...),)), body)
        parameters = Any[outer..., types...]
        Expr(:function, isempty(parameters) ? specialized : Expr(:where, specialized, parameters...), typed_body)
    end

    fallback = copy(call)
    fallback.args[position] = :(args::Vararg{Any,N})
    fallback_method = Expr(:function, Expr(:where, fallback, outer..., :N), body)
    return esc(Expr(:block, methods..., :(Base.@__doc__ $fallback_method)))
end

const MAX_SPECIALIZED_ARGS = 16

"""
    splitcolumn(f, C, col)

Calls `f` with `col` narrowed to its concrete member of the union `C`. The generated chain
of `isa` tests is what keeps `f` statically dispatched, for any size of `C`.
"""
@generated function splitcolumn(f::F, ::Type{C}, col) where {F,C}
    branches = [:(col isa $T && return f(col)) for T in columnmembers(C)]
    return quote
        $(branches...)
        unreachable_column()
    end
end

"""
    splitcolumns(f, cols::Vector{C}, indices::NTuple{N,Int})

Calls `f` with the tuple of `cols[indices[i]]`, each narrowed to its concrete member of `C`.
This compiles `length(members of C)^N` calls of `f`.
"""
@generated function splitcolumns(f::F, cols::Vector{C}, indices::NTuple{N,Int}) where {F,C,N}
    N == 0 && return :(f(()))

    locals = [Symbol(:col, i) for i in 1:N]
    body = :(return f(($(locals...),)))
    for local_name in reverse(locals)
        branches = [:($local_name isa $T && $body) for T in columnmembers(C)]
        body = Expr(:block, branches..., :(unreachable_column()))
    end
    assignments = [:($(locals[i]) = cols[indices[$i]]) for i in 1:N]
    return Expr(:block, assignments..., body)
end

function fit_candidates(::Type{C}, ::Type{E}) where {C,E}
    eltypes = Any[eltype(T) for T in columnmembers(C)]
    overlapping = filter(T -> typeintersect(T, E) !== Union{}, eltypes)
    rank(T) = isconcretetype(T) ? 0 : E <: T ? 1 : 2
    return sort(overlapping; by = rank, alg = MergeSort)
end

function holds_only(::Type{T}, v) where {T}
    for x in v
        x isa T || return false
    end
    return true
end

function narrowed_copy(::Type{T}, v) where {T}
    out = Vector{T}(undef, length(v))
    for (i, x) in enumerate(v)
        out[i] = x
    end
    return out
end

"""
    fitcolumn(C, verb, name, v, narrow)

Turns the vector `v` into a member of the column union `C`, or throws a `ColumnTypeError`
naming `verb` and `name`. With `narrow`, a declared element type is ignored in favour of
the smallest allowed type that holds all values, as `map` and DataFrames' `ByRow` do.
"""
@generated function fitcolumn(::Type{C}, verb::Symbol, name::Symbol, v::V, narrow::Bool) where {C,V<:AbstractVector}
    E = eltype(V)
    exact = Vector{E} <: C

    attempts = [:(holds_only($T, v) && return narrowed_copy($T, v)::C) for T in fit_candidates(C, E)]
    search = isempty(attempts) ? :(nothing) : Expr(:block, attempts...)
    keep = exact ? :(return (v isa Vector ? v : narrowed_copy($E, v))::C) : :(nothing)
    return quote
        if !narrow || isempty(v)
            $keep
        end
        $search
        $(exact ? keep : :(column_type_error(verb, name, typelabel($E), C)))
    end
end

takerows(::Type{C}, col, rows::AbstractVector{Int}) where {C} =
    splitcolumn(c -> c[rows], C, col)::C

copycolumn(::Type{C}, col) where {C} = splitcolumn(copy, C, col)::C

columnlength(::Type{C}, col) where {C} = splitcolumn(length, C, col)::Int

function columnsequal(same::F, left::Vector{C}, i::Int, right::Vector{C}, j::Int) where {F,C}
    pair = C[left[i]]
    push!(pair, right[j])
    return splitcolumns(columns -> same(columns[1], columns[2]), pair, (1, 2))::Union{Bool,Missing}
end
