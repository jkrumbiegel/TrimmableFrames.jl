struct WholeFrame
    nrow::Int
end

struct RowGroups
    rows::Vector{Int}
    starts::Vector{Int}
    stops::Vector{Int}
end

const GroupRows = SubArray{Int,1,Vector{Int},Tuple{UnitRange{Int}},true}

segmentcount(::WholeFrame) = 1
segmentcount(groups::RowGroups) = length(groups.starts)

segmentlength(whole::WholeFrame, ::Int) = whole.nrow
segmentlength(groups::RowGroups, g::Int) = groups.stops[g] - groups.starts[g] + 1

segmentrows(groups::RowGroups, g::Int) = view(groups.rows, groups.starts[g]:groups.stops[g])
segmentrows(whole::WholeFrame, ::Int) = 1:whole.nrow

@inline segment(::WholeFrame, col, ::Int) = col
# `view` would call `unalias` on the row indices, whose `unaliascopy` of a view is not trim-safe.
@inline segment(groups::RowGroups, col, g::Int) = SubArray(col, (segmentrows(groups, g),))

segmenttype(::Type{WholeFrame}, ::Type{V}) where {V} = V
segmenttype(::Type{RowGroups}, ::Type{V}) where {T,V<:Vector{T}} = SubArray{T,1,V,Tuple{GroupRows},false}

segmentframe(::WholeFrame, df::Frame, ::Int) = df
segmentframe(groups::RowGroups, df::Frame, g::Int) = take_frame(df, segmentrows(groups, g))

"""
    GroupedFrame{C,M}

The result of [`groupby`](@ref): a parent frame, its grouping columns and the rows of
each group.
"""
struct GroupedFrame{C,M}
    parent::Frame{C,M}
    cols::Vector{Symbol}
    groups::RowGroups
    rowgroup::Vector{Int}
end

Base.parent(gd::GroupedFrame) = getfield(gd, :parent)
groupcols(gd::GroupedFrame) = copy(getfield(gd, :cols))
groupindices(gd::GroupedFrame) = copy(getfield(gd, :rowgroup))
rowgroups(gd::GroupedFrame) = getfield(gd, :groups)

Base.length(gd::GroupedFrame) = segmentcount(rowgroups(gd))
Base.firstindex(::GroupedFrame) = 1
Base.lastindex(gd::GroupedFrame) = length(gd)
Base.getindex(gd::GroupedFrame, g::Integer) = segmentframe(rowgroups(gd), parent(gd), Int(g))
Base.iterate(gd::GroupedFrame, g::Int = 1) = g > length(gd) ? nothing : (gd[g], g + 1)
Base.eltype(::Type{GroupedFrame{C,M}}) where {C,M} = Frame{C,M}
Base.names(gd::GroupedFrame) = names(parent(gd))

function groupkeys(gd::GroupedFrame{C,M}) where {C,M}
    firstrows = Int[rowgroups(gd).rows[s] for s in rowgroups(gd).starts]
    return take_frame(columns_frame(parent(gd), groupcols(gd), false), firstrows)
end

function group_of!(seen::Dict{K,Int}, key::K, ngroups::Int) where {K}
    existing = get(seen, key, 0)
    existing != 0 && return existing, ngroups
    seen[key] = ngroups + 1
    return ngroups + 1, ngroups + 1
end

function hash_refine(ids::Vector{Int}, col::Vector{T}, skipmissing::Bool) where {T}
    S = nonmissingtype(T)
    seen = Dict{Tuple{Int,S},Int}()
    seen_missing = Dict{Int,Int}()
    refined = Vector{Int}(undef, length(col))
    ngroups = 0

    for i in eachindex(col, ids)
        id = ids[i]
        x = col[i]
        if id == 0 || (skipmissing && x === missing)
            refined[i] = 0
        elseif x === missing
            refined[i], ngroups = group_of!(seen_missing, id, ngroups)
        else
            refined[i], ngroups = group_of!(seen, (id, x::S), ngroups)
        end
    end
    return refined, ngroups
end

const SlotInteger = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64}

function integer_bounds(col::Vector{T}) where {T}
    S = nonmissingtype(T)
    lo = typemax(S)
    hi = typemin(S)
    for x in col
        x === missing && continue
        value = x::S
        value < lo && (lo = value)
        value > hi && (hi = value)
    end
    return lo, hi
end

"""
    slot_width(lo, hi, oldgroups, nrows)

The number of table slots per existing group for integer keys in `lo:hi`, the last one
being for `missing`, or 0 when the table would exceed two entries per row.
"""
function slot_width(lo, hi, oldgroups::Int, nrows::Int)
    lo > hi && return 0
    (Int128(lo) >= typemin(Int) && Int128(hi) <= typemax(Int)) || return 0

    width = Int128(hi) - Int128(lo) + 2
    return width * oldgroups <= 2 * Int128(nrows) ? Int(width) : 0
end

function slot_refine(ids::Vector{Int}, col::Vector{T}, lo::Int, width::Int, oldgroups::Int, skipmissing::Bool) where {T}
    S = nonmissingtype(T)
    table = zeros(Int, width * oldgroups)
    refined = Vector{Int}(undef, length(col))
    ngroups = 0

    for i in eachindex(col, ids)
        id = ids[i]
        x = col[i]
        if id == 0 || (skipmissing && x === missing)
            refined[i] = 0
        else
            offset = x === missing ? width - 1 : Int(x::S) - lo
            slot = (id - 1) * width + offset + 1
            if table[slot] == 0
                ngroups += 1
                table[slot] = ngroups
            end
            refined[i] = table[slot]
        end
    end
    return refined, ngroups
end

refine_groups(ids::Vector{Int}, ::Int, col::Vector, skipmissing::Bool) = hash_refine(ids, col, skipmissing)
refine_groups(ids::Vector{Int}, ::Int, col::Vector{Missing}, skipmissing::Bool) = hash_refine(ids, col, skipmissing)

function refine_groups(ids::Vector{Int}, oldgroups::Int, col::Vector{T}, skipmissing::Bool) where {T<:Union{SlotInteger,Missing}}
    lo, hi = integer_bounds(col)
    width = slot_width(lo, hi, oldgroups, length(col))
    width == 0 && return hash_refine(ids, col, skipmissing)
    return slot_refine(ids, col, Int(lo), width, oldgroups, skipmissing)
end

refine_by(df::Frame{C,M}, ids::Vector{Int}, oldgroups::Int, key::Symbol, skipmissing::Bool) where {C,M} =
    splitcolumn(c -> refine_groups(ids, oldgroups, c, skipmissing), C, column(df, key))::Tuple{Vector{Int},Int}

"""
    integer_pool_size(col, skipmissing)

The number of slots DataFrames gives this column in its integer fast path, or 0 when it
does not qualify. The order of groups with `sort=nothing` depends on it.
"""
function integer_pool_size(col::Vector{T}, skipmissing::Bool) where {T}
    T <: Union{Real,Missing} || return 0
    isempty(col) && return 0
    if !(T <: Union{Integer,Missing})
        for x in col
            x === missing && continue
            (isinteger(x) && !isequal(x, -0.0)) || return 0
        end
    end

    present = Missing <: T ? collect(skipmissing_values(col)) : col
    isempty(present) && return 0
    lo, hi = extrema(present)
    (typemin(Int) < lo && hi < typemax(Int)) || return 0

    span = Int128(Int(hi)) - Int128(Int(lo)) + 1
    span + 1 <= 2 * Int128(length(col)) || return 0
    hasmissingslot = Missing <: T
    return Int(span) + (hasmissingslot && !skipmissing)
end

skipmissing_values(col::Vector{T}) where {T} = (x::nonmissingtype(T) for x in col if x !== missing)

function uses_integer_order(df::Frame{C,M}, keys::Vector{Symbol}, skipmissing::Bool) where {C,M}
    isempty(keys) && return false
    slots = Int128(1)
    limit = 2 * Int128(nrow(df))
    for key in keys
        size = splitcolumn(c -> integer_pool_size(c, skipmissing), C, column(df, key))::Int
        size == 0 && return false
        slots *= size
        slots > limit && return false
    end
    return true
end

stable_order(::Type{C}, col, rows::Vector{Int}) where {C} =
    splitcolumn(c -> sortperm(c[rows]; alg = MergeSort), C, col)::Vector{Int}

function sorted_group_order(df::Frame{C,M}, keys::Vector{Symbol}, firstrows::Vector{Int}) where {C,M}
    order = collect(1:length(firstrows))
    for key in reverse(keys)
        order = order[stable_order(C, column(df, key), firstrows[order])]
    end
    return order
end

function group_firstrows(ids::Vector{Int}, ngroups::Int)
    firstrows = zeros(Int, ngroups)
    for (row, id) in enumerate(ids)
        if id != 0 && firstrows[id] == 0
            firstrows[id] = row
        end
    end
    return firstrows
end

function rows_by_group(ids::Vector{Int}, ngroups::Int)
    counts = zeros(Int, ngroups)
    for id in ids
        id != 0 && (counts[id] += 1)
    end

    starts = Vector{Int}(undef, ngroups)
    stops = Vector{Int}(undef, ngroups)
    position = 1
    for g in 1:ngroups
        starts[g] = position
        position += counts[g]
        stops[g] = position - 1
    end

    rows = Vector{Int}(undef, position - 1)
    next = copy(starts)
    for (row, id) in enumerate(ids)
        if id != 0
            rows[next[id]] = row
            next[id] += 1
        end
    end
    return RowGroups(rows, starts, stops)
end

"""
    groupby(df, cols; sort=nothing, skipmissing=false)

Group the rows of `df` by `cols`. The group order follows DataFrames: `sort=true` sorts by
the keys with `missing` last, `sort=false` keeps the order of first appearance and
`sort=nothing` is the order of first appearance, except that all-integer keys with a
narrow range come out sorted.
"""
function groupby(df::Frame{C,M}, cols; sort::Union{Bool,Nothing} = nothing, skipmissing::Bool = false) where {C,M}
    keys = selectnames(df, cols)
    allunique(keys) || throw(ArgumentError("duplicate column names selected"))

    ids = ones(Int, nrow(df))
    ngroups = nrow(df) == 0 ? 0 : 1
    for key in keys
        ids, ngroups = refine_by(df, ids, ngroups, key, skipmissing)
    end

    sorted = sort === true || (sort === nothing && uses_integer_order(df, keys, skipmissing))
    if sorted
        order = sorted_group_order(df, keys, group_firstrows(ids, ngroups))
        position = invperm(order)
        ids = Int[id == 0 ? 0 : position[id] for id in ids]
    end
    return GroupedFrame{C,M}(df, keys, rows_by_group(ids, ngroups), ids)
end
