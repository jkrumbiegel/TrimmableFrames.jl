@enum ResultShape begin
    PER_SEGMENT
    SEGMENTED
    PARENT_ROWS
end

"""
    Output{C}

The columns an operation has produced so far, before they are aligned to a common set of
rows. A `PER_SEGMENT` column has one value per segment, to be repeated. A `SEGMENTED`
column holds segments back to back with their lengths in `lengths`. A `PARENT_ROWS` column
is already in the row order of the source.
"""
struct Output{C}
    verb::Symbol
    keeprows::Bool
    names::Vector{Symbol}
    cols::Vector{C}
    shapes::Vector{ResultShape}
    lengths::Vector{Vector{Int}}
    transformed::Vector{Symbol}
end

Output{C}(verb::Symbol, keeprows::Bool) where {C} =
    Output{C}(verb, keeprows, Symbol[], C[], ResultShape[], Vector{Int}[], Symbol[])

function store!(out::Output{C}, name::Symbol, col, shape::ResultShape, lengths::Vector{Int}) where {C}
    i = findfirst(==(name), out.names)
    if i === nothing
        push!(out.names, name)
        push!(out.cols, col)
        push!(out.shapes, shape)
        push!(out.lengths, lengths)
    else
        out.cols[i] = col
        out.shapes[i] = shape
        out.lengths[i] = lengths
    end
    return out
end

function store_transformed!(out::Output, name::Symbol, col, shape::ResultShape, lengths::Vector{Int})
    if name in out.transformed
        throw(ArgumentError(string("duplicate output column name: :", name)))
    end
    push!(out.transformed, name)
    return store!(out, name, col, shape, lengths)
end

function repeat_rows(lengths::Vector{Int})
    rows = Vector{Int}(undef, sum(lengths; init = 0))
    position = 1
    for (g, len) in enumerate(lengths)
        for _ in 1:len
            rows[position] = g
            position += 1
        end
    end
    return rows
end

function target_lengths(out::Output, segments)
    n = segmentcount(segments)
    out.keeprows && return Int[segmentlength(segments, g) for g in 1:n]
    for i in eachindex(out.shapes)
        out.shapes[i] == SEGMENTED && return out.lengths[i]
    end
    return ones(Int, n)
end

mismatch_message(::WholeFrame) = "New columns must have the same length as old columns"
mismatch_message(::RowGroups) = "all functions must return vectors of the same length"
keeprows_message(::WholeFrame) = "of vector returned is different from number of rows of the source data frame"
keeprows_message(::RowGroups) = "all functions must return vectors with as many values as rows in each group"

function check_segment_lengths(out::Output, segments, target::Vector{Int}, i::Int)
    out.shapes[i] == SEGMENTED || return
    out.lengths[i] == target && return
    if out.keeprows
        throw(ArgumentError(string(out.verb, ": column :", out.names[i], ": ", keeprows_message(segments))))
    end
    throw(ArgumentError(string(out.verb, ": column :", out.names[i], ": ", mismatch_message(segments))))
end

parent_rows(col, ::Type{C}, ::WholeFrame) where {C} = col

function parent_rows(col, ::Type{C}, groups::RowGroups) where {C}
    return takerows(C, col, invperm(groups.rows))
end

function aligned_columns(out::Output{C}, segments, target::Vector{Int}) where {C}
    repeated = repeat_rows(target)
    aligned = Vector{C}(undef, length(out.cols))
    for i in eachindex(out.cols)
        check_segment_lengths(out, segments, target, i)
        shape = out.shapes[i]
        col = shape == PER_SEGMENT ? takerows(C, out.cols[i], repeated) : out.cols[i]
        aligned[i] = out.keeprows && shape != PARENT_ROWS ? parent_rows(col, C, segments) : col
    end
    return aligned
end

result_frame(out::Output{C}, cols::Vector{C}) where {C} = Frame{C}(out.names, cols)
