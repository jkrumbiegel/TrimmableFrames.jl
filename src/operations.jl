"""
    ByRow(f)

Applies `f` to each row of the source columns, as in DataFrames.
"""
struct ByRow{F}
    f::F
end

ByRow(::Type{T}) where {T} = ByRow{Type{T}}(T)

@generated function row_result_type(f::F, ::Type{Columns}) where {F,Columns<:Tuple}
    arguments = Tuple{map(eltype, fieldtypes(Columns))...}
    return :(Core.Compiler.return_type(f, $arguments))
end

function (b::ByRow{F})(cols::Vararg{AbstractVector,N}) where {F,N}
    R = row_result_type(b.f, typeof(cols))
    out = Vector{R}(undef, length(first(cols)))
    for i in eachindex(out)
        out[i] = b.f(map(c -> c[i], cols)...)
    end
    return out
end

narrows_result(f) = false
narrows_result(::ByRow) = true

"""
    AsTable(Val((:a, :b)))

As a source, passes the columns `:a` and `:b` to the function as one `NamedTuple` (or one
`NamedTuple` per row with [`ByRow`](@ref)). The names must be part of the type: a
`NamedTuple` with run-time names cannot be compiled.

`=> AsTable` as a target, as in DataFrames, expands a `NamedTuple` result into columns.
"""
struct AsTable{S}
    source::S
end

function AsTable(source::AbstractVector)
    throw(ArgumentError(string(
        "AsTable([:x, :y]): a NamedTuple with run-time names cannot be compiled, ",
        "put the names in the type with AsTable(Val((:x, :y)))",
    )))
end

proprow(df::Frame) = 1.0

struct NamedArguments{Names,F}
    f::F
end
NamedArguments{Names}(f::F) where {Names,F} = NamedArguments{Names,F}(f)
(args::NamedArguments{Names})(values::Vararg{Any,N}) where {Names,N} = args.f(NamedTuple{Names}(values))

with_names(::Val{Names}, f::F) where {Names,F} = NamedArguments{Names}(f)
with_names(::Val{Names}, f::ByRow) where {Names} = ByRow(NamedArguments{Names}(f.f))

@generated function functionname_of(::Type{F}) where {F}
    if F <: Type
        return QuoteNode(nameof(F.parameters[1]))
    end
    name = F <: Function ? String(F.name.singletonname) : "#"
    return QuoteNode(startswith(name, "#") ? :function : Symbol(name))
end

functionname(f::F) where {F} = functionname_of(F)
functionname(f::ByRow) = functionname(f.f)
functionname(f::NamedArguments) = functionname(f.f)
functionname(f::ComposedFunction) = Symbol(functionname(f.outer), :_, functionname(f.inner))

function joined_names(names)
    joined = ""
    for name in names
        joined = isempty(joined) ? string(name) : string(joined, "_", name)
    end
    return joined
end

function default_name(names, f, renamecols::Bool)
    if length(names) > 3
        prefix = string(joined_names(names[1:2]), "_etc")
    elseif isempty(names)
        renamecols || throw(ArgumentError("when renamecols=false target column name must be passed if there are no input columns"))
        return functionname(f)
    else
        prefix = joined_names(names)
    end
    return renamecols ? Symbol(prefix, "_", functionname(f)) : Symbol(prefix)
end

struct Context{C,S}
    df::Frame{C}
    segments::S
    out::Output{C}
    renamecols::Bool
    copycols::Bool
end

column_type(::Context{C}) where {C} = C

@generated function result_type(f::F, ::Type{S}, ::Type{Columns}) where {F,S,Columns<:Tuple}
    arguments = Tuple{map(V -> segmenttype(S, V), fieldtypes(Columns))...}
    return :(Core.Compiler.return_type(f, $arguments))
end

@generated function element_union(::Type{R}) where {R}
    return Union{map(eltype, columnmembers(R))...}
end

unaliased(r, cols::Tuple) = any(c -> c === r, cols) ? copy(r) : r

function apply_segments(f::F, segments::S, cols::Columns, copycols::Bool) where {F,S,Columns<:Tuple}
    R = result_type(f, S, Columns)
    n = segmentcount(segments)
    results = Vector{R}(undef, n)
    for g in 1:n
        r = f(map(c -> segment(segments, c, g), cols)...)
        results[g] = S === WholeFrame && copycols && r isa AbstractVector ? unaliased(r, cols) : r
    end
    return results
end

function flatten_segments(results::Vector{<:Any}, ::Type{E}) where {E}
    lengths = Int[length(r) for r in results]
    out = Vector{E}(undef, sum(lengths; init = 0))
    position = 1
    for r in results
        for x in r
            out[position] = x
            position += 1
        end
    end
    return out, lengths
end

function flatten_segments(results::Vector{Vector{E}}, ::Type{E}) where {E}
    length(results) == 1 && return results[1], Int[length(results[1])]
    return invoke(flatten_segments, Tuple{Vector{<:Any},Type{E}}, results, E)
end

function emit_vectors!(cx::Context, name::Symbol, results::Vector{R}, E::Type, narrow::Bool) where {R}
    C = column_type(cx)
    values, lengths = flatten_segments(results, E)
    col = fitcolumn(C, cx.out.verb, name, values, narrow || !isconcretetype(R))
    return store_transformed!(cx.out, name, col, SEGMENTED, lengths)
end

function emit_values!(cx::Context, name::Symbol, results::Vector{R}, narrow::Bool = false) where {R}
    C = column_type(cx)
    col = fitcolumn(C, cx.out.verb, name, results, narrow || !isconcretetype(R))
    return store_transformed!(cx.out, name, col, PER_SEGMENT, Int[])
end

function emit!(cx::Context, name::Symbol, results::Vector{R}, narrow::Bool) where {R}
    if R <: AbstractVector
        return emit_vectors!(cx, name, results, element_union(R), narrow)
    elseif typeintersect(R, AbstractVector) === Union{}
        return emit_values!(cx, name, results, narrow)
    elseif !isempty(results) && all(r -> r isa AbstractVector, results)
        return emit_vectors!(cx, name, results, Any, true)
    end
    return emit_values!(cx, name, results, true)
end

not_a_table(verb::Symbol) = throw(ArgumentError(string(
    verb, ": a function with target AsTable or a list of columns must return a NamedTuple, ",
    "a vector of NamedTuples or a vector of Tuples, with a type known to the compiler",
)))

check_target_count(::Type{AsTable}, n::Int) = nothing
function check_target_count(names::Vector{Symbol}, n::Int)
    length(names) == n && return
    throw(ArgumentError(string("got ", n, " result columns for ", length(names), " target columns")))
end

target_name(::Type{AsTable}, fieldnames::Tuple, j::Int) = fieldnames[j]
target_name(names::Vector{Symbol}, fieldnames::Tuple, j::Int) = names[j]

function row_field_names(::Type{Row}) where {Row}
    Row === Union{} && return nothing
    labels = map(columnmembers(Row)) do member
        if member <: NamedTuple && isconcretetype(member)
            fieldnames(member)
        elseif member <: Tuple && isconcretetype(member)
            ntuple(j -> Symbol(:x, j), fieldcount(member))
        end
    end
    return all(==(first(labels)), labels) ? first(labels) : nothing
end

row_field_type(::Type{Row}, j::Int) where {Row} = Union{map(member -> fieldtype(member, j), columnmembers(Row))...}

field_values(::Type{E}, results, j::Int, ::Val{false}) where {E} = E[r[j] for r in results]
field_values(::Type{E}, results, j::Int, ::Val{true}) where {E} = Vector{E}[E[row[j] for row in r] for r in results]

@generated function emit_fields!(cx::Context, target, results, ::Type{Row}, rows::Val, narrow::Bool) where {Row}
    labels = row_field_names(Row)
    n = length(labels)
    statements = map(1:n) do j
        E = row_field_type(Row, j)
        values = :(field_values($E, results, $j, rows))
        :(emit!(cx, target_name(target, $labels, $j), $values, narrow || $(!isconcretetype(E))))
    end
    return Expr(:block, :(check_target_count(target, $n)), statements..., :(return nothing))
end

@generated is_table_row(::Type{Row}) where {Row} = row_field_names(Row) !== nothing && Row <: NamedTuple
@generated is_row(::Type{Row}) where {Row} = row_field_names(Row) !== nothing

function emit!(cx::Context, target, results::Vector{R}, narrow::Bool) where {R}
    if is_table_row(R)
        return emit_fields!(cx, target, results, R, Val(false), narrow)
    elseif R <: AbstractVector && is_row(element_union(R))
        return emit_fields!(cx, target, results, element_union(R), Val(true), narrow)
    end
    return not_a_table(cx.out.verb)
end

function emit_frames!(cx::Context, results::Vector{Frame{C}}) where {C}
    lengths = Int[nrow(df) for df in results]
    isempty(results) && return nothing
    combined = reduce(vcat, results)
    for (name, col) in zip(columnnames(combined), columns(combined))
        store_transformed!(cx.out, name, col, SEGMENTED, lengths)
    end
    return nothing
end

function emit_auto!(cx::Context, results::Vector{R}) where {R}
    if R <: Frame
        return emit_frames!(cx, results)
    elseif is_table_row(R) || (R <: AbstractVector && is_table_row(element_union(R)))
        return emit!(cx, AsTable, results, false)
    end
    return emit!(cx, :x1, results, false)
end

resolve_target(cx::Context, names, f, ::Nothing) = default_name(names, f, cx.renamecols)
resolve_target(cx::Context, names, f, target::Union{Symbol,AbstractString}) = Symbol(target)
resolve_target(cx::Context, names, f, target::AbstractVector) = Symbol[Symbol(t) for t in target]
resolve_target(cx::Context, names, f, ::Type{AsTable}) = AsTable

struct ApplyFunction{F,X,T}
    f::F
    cx::X
    target::T
end

function (a::ApplyFunction)(cols::Tuple)
    results = apply_segments(a.f, a.cx.segments, cols, a.cx.copycols)
    emit!(a.cx, a.target, results, narrows_result(a.f))
    return nothing
end

function apply_columns!(cx::Context, names::NTuple{N,Symbol}, f::F, target::T) where {N,F,T}
    resolved = resolve_target(cx, names, f, target)
    indices = map(n -> columnindex(cx.df, n), names)
    splitcolumns(ApplyFunction(f, cx, resolved), columns(cx.df), indices)
    return nothing
end

const MAX_VECTOR_SOURCE = 3

"""
    accepts(f, Val(N))

Whether `f` has a method for `N` arguments. Folded by inference, so that a vector source
does not compile the arities `f` does not have.
"""
accepts(f::F, ::Val{N}) where {F,N} = Core.Compiler.return_type(f, NTuple{N,Any}) !== Union{}
accepts(f::ByRow, arity::Val) = accepts(f.f, arity)

function too_many_sources(cx::Context, names::Vector{Symbol}, f)
    n = length(names)
    if n > MAX_VECTOR_SOURCE
        throw(ArgumentError(string(
            cx.out.verb, ": a source given as a vector supports at most ", MAX_VECTOR_SOURCE,
            " columns because its length is only known at run time, got ", n,
            ". Write the columns as a tuple, (:a, :b, ...) => f",
        )))
    end
    throw(ArgumentError(string(cx.out.verb, ": the function has no method for ", n, " columns")))
end

function apply_vector_source!(cx::Context, names::Vector{Symbol}, f::F, target::T) where {F,T}
    n = length(names)
    if n == 0 && accepts(f, Val(0))
        return apply_columns!(cx, (), f, target)
    elseif n == 1 && accepts(f, Val(1))
        return apply_columns!(cx, (names[1],), f, target)
    elseif n == 2 && accepts(f, Val(2))
        return apply_columns!(cx, (names[1], names[2]), f, target)
    elseif n == 3 && accepts(f, Val(3))
        return apply_columns!(cx, (names[1], names[2], names[3]), f, target)
    end
    return too_many_sources(cx, names, f)
end

source_name(df::Frame, ref::ColumnRef) = columnnames(df)[columnindex(df, ref)]

apply!(cx::Context, source::ColumnRef, f::F, target::T) where {F,T} =
    apply_columns!(cx, (source_name(cx.df, source),), f, target)
apply!(cx::Context, source::Tuple, f::F, target::T) where {F,T} =
    apply_columns!(cx, map(s -> source_name(cx.df, s), source), f, target)
apply!(cx::Context, source::AsTable{Val{Names}}, f::F, target::T) where {Names,F,T} =
    apply_columns!(cx, Names, with_names(Val(Names), f), target)
apply!(cx::Context, source, f::F, target::T) where {F,T} =
    apply_vector_source!(cx, selectnames(cx.df, source), f, target)

function apply_frame_function!(cx::Context{C,S}, f::F) where {C,S,F}
    R = Core.Compiler.return_type(f, Tuple{Frame{C}})
    results = Vector{R}(undef, segmentcount(cx.segments))
    for g in eachindex(results)
        results[g] = f(segmentframe(cx.segments, cx.df, g))
    end
    return emit_auto!(cx, results)
end

function count_rows!(cx::Context, name::Symbol)
    n = segmentcount(cx.segments)
    counts = Int[segmentlength(cx.segments, g) for g in 1:n]
    return emit_values!(cx, name, counts)
end

function count_proportions!(cx::Context, name::Symbol)
    n = segmentcount(cx.segments)
    total = sum(g -> segmentlength(cx.segments, g), 1:n; init = 0)
    return emit_values!(cx, name, Float64[segmentlength(cx.segments, g) / total for g in 1:n])
end

copied(cx::Context{C}, col) where {C} = cx.copycols ? copycolumn(C, col) : col

function select_plain!(cx::Context{C,S}, name::Symbol, target::Symbol) where {C,S}
    col = column(cx.df, name)
    if cx.out.keeprows
        return store_transformed!(cx.out, target, copied(cx, col), PARENT_ROWS, Int[])
    end
    lengths = Int[segmentlength(cx.segments, g) for g in 1:segmentcount(cx.segments)]
    ordered = S === WholeFrame ? copied(cx, col) : takerows(C, col, cx.segments.rows)
    return store_transformed!(cx.out, target, ordered, SEGMENTED, lengths)
end

function select_many!(cx::Context{C}, names::Vector{Symbol}) where {C}
    for name in names
        name in cx.out.names && continue
        if cx.out.keeprows
            store!(cx.out, name, copied(cx, column(cx.df, name)), PARENT_ROWS, Int[])
        else
            select_plain!(cx, name, name)
        end
    end
    return nothing
end

run!(cx::Context, ref::ColumnRef) = (name = source_name(cx.df, ref); select_plain!(cx, name, name))
run!(cx::Context, ::Colon) = select_many!(cx, selectnames(cx.df, :))
run!(cx::Context, sel::Union{All,Not,Cols,Between}) = select_many!(cx, selectnames(cx.df, sel))
run!(cx::Context, sel::AbstractVector{<:Union{ColumnRef}}) = select_many!(cx, selectnames(cx.df, sel))
run!(cx::Context, sel::AbstractVector{Any}) = select_many!(cx, selectnames(cx.df, sel))
run!(cx::Context, range::AbstractRange{<:Integer}) = select_many!(cx, selectnames(cx.df, range))

function run!(cx::Context, pairs::AbstractVector{<:Pair})
    for p in pairs
        run!(cx, p)
    end
end

run!(cx::Context, f::Base.Callable) = apply_frame_function!(cx, f)
run!(cx::Context, ::typeof(nrow)) = count_rows!(cx, :nrow)
run!(cx::Context, ::typeof(proprow)) = count_proportions!(cx, :proprow)
run!(cx::Context, p::Pair{typeof(nrow)}) = count_rows!(cx, Symbol(p.second))
run!(cx::Context, p::Pair{typeof(proprow)}) = count_proportions!(cx, Symbol(p.second))

run!(cx::Context, p::Pair) = run_pair!(cx, p.first, p.second)

run_pair!(cx::Context, source, f::F) where {F} = apply!(cx, source, f, nothing)
run_pair!(cx::Context, source, p::Pair) = apply!(cx, source, p.first, p.second)
function run_pair!(cx::Context, source, ::Pair{<:Union{Symbol,AbstractString}})
    throw(ArgumentError(string(cx.out.verb, ": expected a function between source and target column")))
end
run_pair!(cx::Context, source::ColumnRef, target::Union{Symbol,AbstractString}) =
    select_plain!(cx, source_name(cx.df, source), Symbol(target))

function run_pair!(cx::Context, sources, targets::AbstractVector{<:Union{Symbol,AbstractString}})
    names = selectnames(cx.df, sources)
    check_target_count(Symbol[Symbol(t) for t in targets], length(names))
    for (name, target) in zip(names, targets)
        select_plain!(cx, name, Symbol(target))
    end
end

run_all!(cx::Context, ::Tuple{}) = nothing
function run_all!(cx::Context, args::Tuple)
    run!(cx, first(args))
    return run_all!(cx, Base.tail(args))
end
