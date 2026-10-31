struct JoinKeys
    left::Vector{Symbol}
    right::Vector{Symbol}
end

struct JoinOptions{L,R}
    makeunique::Bool
    validate::Tuple{Bool,Bool}
    left_rename::L
    right_rename::R
    matchmissing::Symbol
    order::Symbol
    source::Union{Nothing,Symbol}
end

function JoinOptions(makeunique::Bool, validate, renamecols::Pair, matchmissing::Symbol, order::Symbol, source)
    label = source === nothing ? nothing : Symbol(source)
    return JoinOptions(
        makeunique, (first(validate), last(validate)), first(renamecols), last(renamecols),
        matchmissing, order, label,
    )
end

function add_key!(keys::JoinKeys, left::Symbol, right::Symbol)
    push!(keys.left, left)
    push!(keys.right, right)
    return keys
end

@inline function add_key!(keys::JoinKeys, v)
    if v isa Symbol
        return add_key!(keys, v, v)
    elseif v isa String
        return add_key!(keys, Symbol(v), Symbol(v))
    elseif v isa Pair{Symbol,Symbol}
        return add_key!(keys, v.first, v.second)
    elseif v isa Pair{String,String}
        return add_key!(keys, Symbol(v.first), Symbol(v.second))
    elseif v isa NTuple{2,Symbol}
        throw(ArgumentError("a tuple is not supported as a value of `on`: use a `Pair{Symbol, Symbol}`"))
    end
    throw(ArgumentError("all elements of `on` must be a name or a Pair of names"))
end

function join_keys(on::AbstractVector)
    isempty(on) && throw(ArgumentError("missing join argument `on`"))
    keys = JoinKeys(Symbol[], Symbol[])
    for v in on
        add_key!(keys, v)
    end
    return keys
end
join_keys(on) = add_key!(JoinKeys(Symbol[], Symbol[]), on)

function check_key_names(names::Vector{Symbol}, df::Frame, side::String)
    allunique(names) || throw(ArgumentError(string("duplicate key columns in the ", side, " frame")))
    for name in names
        hasproperty(df, name) || throw(ArgumentError(string("column :", name, " not found in the ", side, " frame")))
    end
end

function check_join_options(kind::Symbol, options::JoinOptions)
    if !(options.matchmissing in (:error, :equal, :notequal))
        throw(ArgumentError("matchmissing allows only :error, :equal, or :notequal"))
    elseif kind === :outer && options.matchmissing === :notequal
        throw(ArgumentError("matchmissing == :notequal for `outerjoin` is not allowed"))
    elseif !(options.order in (:undefined, :left, :right))
        throw(ArgumentError("order argument must be :undefined, :left, or :right"))
    end
end

reject_special_values(::Vector, ::Symbol, ::String) = nothing
function reject_special_values(col::Vector{T}, name::Symbol, side::String) where {T<:Union{AbstractFloat,Missing}}
    for x in col
        if x !== missing && (isnan(x) || isequal(x, -0.0))
            throw(ArgumentError(string(
                "NaN and -0.0 are not allowed in key columns, found in column :", name, " of the ", side, " frame",
            )))
        end
    end
end

function check_key_values(col::Vector{T}, name::Symbol, side::String, matchmissing::Symbol) where {T}
    if matchmissing === :error && Missing <: T && any(ismissing, col)
        throw(ArgumentError(string(
            "missing found in key column :", name, " of the ", side,
            " frame: pass matchmissing=:equal or matchmissing=:notequal",
        )))
    end
    reject_special_values(col, name, side)
    return nothing
end

function check_key_columns(df::Frame{C}, names::Vector{Symbol}, side::String, matchmissing::Symbol) where {C}
    for name in names
        splitcolumn(c -> check_key_values(c, name, side, matchmissing), C, column(df, name))
    end
end

"""
    same_base(f, C, S, col, mismatch)

Calls `f` with `col` narrowed to the member of `C` with element type `S` or
`Union{Missing,S}`, and `mismatch()` for any other member.
"""
@generated function same_base(f::F, ::Type{C}, ::Type{S}, col, mismatch::M) where {F,C,S,M}
    branches = [:(col isa $T && return f(col)) for T in columnmembers(C) if nonmissingtype(eltype(T)) === S]
    return Expr(:block, branches..., :(return mismatch()))
end

function key_type_error(verb::Symbol, lname::Symbol, rname::Symbol, llabel::String, rlabel::String)
    throw(ArgumentError(string(
        verb, ": key column :", lname, " in the left frame has element type ", llabel,
        " and :", rname, " in the right frame has element type ", rlabel,
        ", but keys need the same element type apart from Missing",
    )))
end

function pair_with_right(f::F, verb::Symbol, l::Vector{T}, pair::Vector{C}, lname::Symbol, rname::Symbol) where {F,C,T}
    paired = r -> f(l, r)
    mismatch = () -> key_type_error(
        verb, lname, rname, typelabel(T), splitcolumn(c -> typelabel(eltype(c)), C, pair[2])::String,
    )
    return same_base(paired, C, nonmissingtype(T), pair[2], mismatch)
end

# The two columns travel in a vector: a call with two arguments of a large union is not resolved.
function with_key_pair(f::F, verb::Symbol, df1::Frame{C}, df2::Frame{C}, lname::Symbol, rname::Symbol) where {F,C}
    pair = C[column(df1, lname)]
    push!(pair, column(df2, rname))
    return splitcolumn(l -> pair_with_right(f, verb, l, pair, lname, rname), C, pair[1])
end

function concatenated(l::Vector{A}, r::Vector{B}) where {A,B}
    out = Vector{Union{A,B}}(undef, length(l) + length(r))
    copyto!(out, 1, l, 1, length(l))
    copyto!(out, length(l) + 1, r, 1, length(r))
    return out
end

function refine_key(verb::Symbol, ids::Vector{Int}, ngroups::Int, df1::Frame{C}, df2::Frame{C}, lname::Symbol, rname::Symbol, skipmissing::Bool) where {C}
    refine = (l, r) -> refine_groups(ids, ngroups, concatenated(l, r), skipmissing)
    return with_key_pair(refine, verb, df1, df2, lname, rname)::Tuple{Vector{Int},Int}
end

function shared_ids(verb::Symbol, df1::Frame, df2::Frame, keys::JoinKeys, skipmissing::Bool)
    total = nrow(df1) + nrow(df2)
    ids = ones(Int, total)
    ngroups = total == 0 ? 0 : 1
    for i in eachindex(keys.left)
        ids, ngroups = refine_key(verb, ids, ngroups, df1, df2, keys.left[i], keys.right[i], skipmissing)
    end
    return ids, ngroups
end

function has_duplicates(ids::Vector{Int}, ngroups::Int)
    seen = fill(false, ngroups)
    for id in ids
        id == 0 && continue
        seen[id] && return true
        seen[id] = true
    end
    return false
end

function check_unique_keys(leftids::Vector{Int}, rightids::Vector{Int}, ngroups::Int, validate::Tuple{Bool,Bool})
    left_invalid = validate[1] && has_duplicates(leftids, ngroups)
    right_invalid = validate[2] && has_duplicates(rightids, ngroups)
    left_invalid && right_invalid && throw(ArgumentError("merge key(s) are not unique in both frames"))
    left_invalid && throw(ArgumentError("merge key(s) in the left frame are not unique"))
    right_invalid && throw(ArgumentError("merge key(s) in the right frame are not unique"))
end

function joined_ids(verb::Symbol, kind::Symbol, df1::Frame, df2::Frame, on, options::JoinOptions)
    keys = join_keys(on)
    check_key_names(keys.left, df1, "left")
    check_key_names(keys.right, df2, "right")
    check_join_options(kind, options)
    check_key_columns(df1, keys.left, "left", options.matchmissing)
    check_key_columns(df2, keys.right, "right", options.matchmissing)

    ids, ngroups = shared_ids(verb, df1, df2, keys, options.matchmissing === :notequal)
    leftids = ids[1:nrow(df1)]
    rightids = ids[(nrow(df1) + 1):end]
    check_unique_keys(leftids, rightids, ngroups, options.validate)
    return keys, leftids, rightids, ngroups
end

function matched_rows(leftids::Vector{Int}, rightids::Vector{Int}, ngroups::Int)
    groups = rows_by_group(rightids, ngroups)
    total = 0
    for id in leftids
        id != 0 && (total += segmentlength(groups, id))
    end

    left = Vector{Int}(undef, total)
    right = Vector{Int}(undef, total)
    position = 0
    for (row, id) in enumerate(leftids)
        id == 0 && continue
        for match in segmentrows(groups, id)
            position += 1
            left[position] = row
            right[position] = match
        end
    end
    return left, right
end

function unmatched_rows(matched::Vector{Int}, n::Int)
    unseen = fill(true, n)
    for row in matched
        unseen[row] = false
    end
    return findall(unseen)
end

function reordered(left::Vector{Int}, right::Vector{Int}, rows::Vector{Int}, n::Int)
    positions = Int[row == 0 ? n + 1 : row for row in rows]
    permutation = sortperm(positions; alg = MergeSort)
    return left[permutation], right[permutation]
end

function joined_rows(kind::Symbol, leftids::Vector{Int}, rightids::Vector{Int}, ngroups::Int, order::Symbol)
    left, right = matched_rows(leftids, rightids, ngroups)
    leftonly = kind in (:left, :outer) ? unmatched_rows(left, length(leftids)) : Int[]
    rightonly = kind in (:right, :outer) ? unmatched_rows(right, length(rightids)) : Int[]

    allleft = vcat(left, leftonly, zeros(Int, length(rightonly)))
    allright = vcat(right, zeros(Int, length(leftonly)), rightonly)
    order === :left && return reordered(allleft, allright, allleft, length(leftids))
    order === :right && return reordered(allleft, allright, allright, length(rightids))
    return allleft, allright
end

renamed_column(name::Symbol, f::F) where {F} = Symbol(f(string(name)))
renamed_column(name::Symbol, suffix::Union{Symbol,AbstractString}) = Symbol(name, suffix)

function suffixed(name::Symbol, taken::Vector{Symbol})
    k = 1
    while true
        candidate = Symbol(name, "_", k)
        candidate in taken || return candidate
        k += 1
    end
end

function unique_names(names::Vector{Symbol}, makeunique::Bool)
    taken = Symbol[]
    duplicates = Int[]
    for (i, name) in enumerate(names)
        name in taken ? push!(duplicates, i) : push!(taken, name)
    end
    isempty(duplicates) && return copy(names)

    if !makeunique
        throw(ArgumentError(string(
            "duplicate column name :", names[duplicates[1]],
            ": pass makeunique=true to make it unique using a suffix",
        )))
    end
    out = copy(names)
    for i in duplicates
        out[i] = suffixed(names[i], taken)
        push!(taken, out[i])
    end
    return out
end

function joined_names(df1::Frame, df2::Frame, keys::JoinKeys, options::JoinOptions)
    left = Symbol[n in keys.left ? n : renamed_column(n, options.left_rename) for n in columnnames(df1)]
    right = Symbol[renamed_column(n, options.right_rename) for n in columnnames(df2) if !(n in keys.right)]
    return unique_names(vcat(left, right), options.makeunique)
end

function gathered(col::Vector{T}, rows::Vector{Int}) where {T}
    out = Vector{Union{T,Missing}}(undef, length(rows))
    for (i, row) in enumerate(rows)
        out[i] = row == 0 ? missing : col[row]
    end
    return out
end

function merged_key(l::Vector{A}, r::Vector{B}, left::Vector{Int}, right::Vector{Int}) where {A,B}
    out = Vector{Union{A,B}}(undef, length(left))
    for i in eachindex(left, right)
        out[i] = left[i] == 0 ? r[right[i]] : l[left[i]]
    end
    return out
end

gathered_column(::Type{C}, verb::Symbol, name::Symbol, col, rows::Vector{Int}) where {C} =
    splitcolumn(c -> fitcolumn(C, verb, name, gathered(c, rows), false)::C, C, col)::C

side_column(::Type{C}, verb::Symbol, name::Symbol, col, rows::Vector{Int}, nullable::Bool) where {C} =
    (nullable ? gathered_column(C, verb, name, col, rows) : takerows(C, col, rows))::C

function key_column(verb::Symbol, kind::Symbol, df1::Frame{C}, df2::Frame{C}, name::Symbol, lname::Symbol, rname::Symbol, left::Vector{Int}, right::Vector{Int}) where {C}
    kind === :right && return takerows(C, column(df2, rname), right)::C
    kind === :outer || return takerows(C, column(df1, lname), left)::C

    merge = (l, r) -> fitcolumn(C, verb, name, merged_key(l, r, left, right), false)::C
    return with_key_pair(merge, verb, df1, df2, lname, rname)::C
end

function source_labels(left::Vector{Int}, right::Vector{Int})
    labels = Vector{String}(undef, length(left))
    for i in eachindex(left, right)
        labels[i] = left[i] == 0 ? "right_only" : right[i] == 0 ? "left_only" : "both"
    end
    return labels
end

function source_name(label::Symbol, names::Vector{Symbol}, makeunique::Bool)
    label in names || return label
    if !makeunique
        throw(ArgumentError(string(
            "joined frame already has column :", label,
            ": pass makeunique=true to make it unique using a suffix",
        )))
    end
    return suffixed(label, names)
end

function compose_join(verb::Symbol, kind::Symbol, df1::Frame{C}, df2::Frame{C}, keys::JoinKeys, left::Vector{Int}, right::Vector{Int}, options::JoinOptions) where {C}
    names = joined_names(df1, df2, keys, options)
    cols = C[]
    for (i, name) in enumerate(columnnames(df1))
        position = findfirst(==(name), keys.left)
        col = if position === nothing
            side_column(C, verb, names[i], column(df1, name), left, kind in (:right, :outer))
        else
            key_column(verb, kind, df1, df2, name, name, keys.right[position], left, right)
        end
        push!(cols, col)
    end
    for name in columnnames(df2)
        name in keys.right && continue
        i = length(cols) + 1
        push!(cols, side_column(C, verb, names[i], column(df2, name), right, kind in (:left, :outer)))
    end

    label = options.source
    if label !== nothing
        name = source_name(label, names, options.makeunique)
        push!(names, name)
        push!(cols, fitcolumn(C, verb, name, source_labels(left, right), false)::C)
    end
    return Frame{C}(names, cols)
end

function run_join(verb::Symbol, kind::Symbol, df1::Frame, df2::Frame, on, options::JoinOptions)
    keys, leftids, rightids, ngroups = joined_ids(verb, kind, df1, df2, on, options)
    left, right = joined_rows(kind, leftids, rightids, ngroups, options.order)
    return compose_join(verb, kind, df1, df2, keys, left, right, options)
end

"""
    innerjoin(df1, df2, dfs...; on, makeunique=false, validate=(false, false),
              renamecols=identity => identity, matchmissing=:error, order=:undefined)

Rows whose keys match in all frames, as in DataFrames. All frames have the same allowed
column types, and a key column pair must have the same element type apart from `Missing`.
"""
function innerjoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, validate = (false, false),
                   renamecols::Pair = identity => identity, matchmissing::Symbol = :error, order::Symbol = :undefined) where {C}
    return run_join(:innerjoin, :inner, df1, df2, on, JoinOptions(makeunique, validate, renamecols, matchmissing, order, nothing))
end

function innerjoin(df1::Frame{C}, df2::Frame{C}, df3::Frame{C}, dfs::Vararg{Frame{C},N}; on = Symbol[], makeunique::Bool = false,
                   validate = (false, false), matchmissing::Symbol = :error, order::Symbol = :undefined) where {C,N}
    rest = (df3, dfs...)
    intermediate = order === :right ? :undefined : order
    result = innerjoin(df1, df2; on, makeunique, validate, matchmissing, order = intermediate)
    for (i, df) in enumerate(rest)
        step = i == length(rest) ? order : intermediate
        result = innerjoin(result, df; on, makeunique, validate, matchmissing, order = step)
    end
    return result
end

"""
    leftjoin(df1, df2; on, makeunique=false, source=nothing, validate=(false, false),
             renamecols=identity => identity, matchmissing=:error, order=:undefined)

All rows of `df1` with their matches in `df2`. The columns of `df2` need a `Missing` member
in the allowed types, unless every row of `df1` has a match.
"""
function leftjoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, source = nothing, validate = (false, false),
                  renamecols::Pair = identity => identity, matchmissing::Symbol = :error, order::Symbol = :undefined) where {C}
    return run_join(:leftjoin, :left, df1, df2, on, JoinOptions(makeunique, validate, renamecols, matchmissing, order, source))
end

"""
    rightjoin(df1, df2; on, makeunique=false, source=nothing, validate=(false, false),
              renamecols=identity => identity, matchmissing=:error, order=:undefined)

All rows of `df2` with their matches in `df1`. The columns of `df1` need a `Missing` member
in the allowed types, unless every row of `df2` has a match.
"""
function rightjoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, source = nothing, validate = (false, false),
                   renamecols::Pair = identity => identity, matchmissing::Symbol = :error, order::Symbol = :undefined) where {C}
    return run_join(:rightjoin, :right, df1, df2, on, JoinOptions(makeunique, validate, renamecols, matchmissing, order, source))
end

"""
    outerjoin(df1, df2, dfs...; on, makeunique=false, source=nothing, validate=(false, false),
              renamecols=identity => identity, matchmissing=:error, order=:undefined)

All rows of all frames, matched where their keys agree. `source` and `renamecols` apply to
two frames only.
"""
function outerjoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, source = nothing, validate = (false, false),
                   renamecols::Pair = identity => identity, matchmissing::Symbol = :error, order::Symbol = :undefined) where {C}
    return run_join(:outerjoin, :outer, df1, df2, on, JoinOptions(makeunique, validate, renamecols, matchmissing, order, source))
end

function outerjoin(df1::Frame{C}, df2::Frame{C}, df3::Frame{C}, dfs::Vararg{Frame{C},N}; on = Symbol[], makeunique::Bool = false,
                   validate = (false, false), matchmissing::Symbol = :error, order::Symbol = :undefined) where {C,N}
    result = outerjoin(df1, df2; on, makeunique, validate, matchmissing, order)
    for df in (df3, dfs...)
        result = outerjoin(result, df; on, makeunique, validate, matchmissing, order)
    end
    return result
end

function rows_with_match(leftids::Vector{Int}, rightids::Vector{Int}, ngroups::Int)
    present = fill(false, ngroups)
    for id in rightids
        id != 0 && (present[id] = true)
    end
    return Bool[id != 0 && present[id] for id in leftids]
end

function filter_by_match(verb::Symbol, kind::Symbol, df1::Frame, df2::Frame, on, options::JoinOptions, keep_matches::Bool)
    _, leftids, rightids, ngroups = joined_ids(verb, kind, df1, df2, on, options)
    matched = rows_with_match(leftids, rightids, ngroups)
    return take_frame(df1, findall(keep_matches ? matched : .!matched))
end

"""
    semijoin(df1, df2; on, makeunique=false, validate=(false, false), matchmissing=:error)

The rows of `df1` with a match in `df2`.
"""
function semijoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, validate = (false, false), matchmissing::Symbol = :error) where {C}
    return filter_by_match(:semijoin, :semi, df1, df2, on, JoinOptions(makeunique, validate, identity => identity, matchmissing, :left, nothing), true)
end

"""
    antijoin(df1, df2; on, makeunique=false, validate=(false, false), matchmissing=:error)

The rows of `df1` without a match in `df2`.
"""
function antijoin(df1::Frame{C}, df2::Frame{C}; on = Symbol[], makeunique::Bool = false, validate = (false, false), matchmissing::Symbol = :error) where {C}
    return filter_by_match(:antijoin, :anti, df1, df2, on, JoinOptions(makeunique, validate, identity => identity, matchmissing, :left, nothing), false)
end

function cross_rows(n1::Int, n2::Int)
    total = n1 * n2
    left = Vector{Int}(undef, total)
    right = Vector{Int}(undef, total)
    for i in 1:n1, j in 1:n2
        position = (i - 1) * n2 + j
        left[position] = i
        right[position] = j
    end
    return left, right
end

"""
    crossjoin(df1, df2, dfs...; makeunique=false, renamecols=identity => identity)

Every combination of rows. `renamecols` applies to two frames only.
"""
function crossjoin(df1::Frame{C}, df2::Frame{C}; makeunique::Bool = false, renamecols::Pair = identity => identity) where {C}
    left, right = cross_rows(nrow(df1), nrow(df2))
    options = JoinOptions(makeunique, (false, false), renamecols, :error, :undefined, nothing)
    return compose_join(:crossjoin, :inner, df1, df2, JoinKeys(Symbol[], Symbol[]), left, right, options)
end

function crossjoin(df1::Frame{C}, df2::Frame{C}, df3::Frame{C}, dfs::Vararg{Frame{C},N}; makeunique::Bool = false) where {C,N}
    result = crossjoin(df1, df2; makeunique)
    for df in (df3, dfs...)
        result = crossjoin(result, df; makeunique)
    end
    return result
end
