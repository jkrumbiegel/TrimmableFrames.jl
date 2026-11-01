@generated function metadata_label(::Type{M}) where {M}
    return join((string(T) for T in columnmembers(M)), ", ")
end

function check_style(verb::Symbol, style::Symbol)
    style === :note || throw(ArgumentError(string(verb, ": only style=:note is supported, got :", style)))
end

function metadata_type_error(subject::String, label::String, ::Type{M}) where {M}
    throw(ColumnTypeError(string(
        subject, " has a value of type ", label,
        ", not among the allowed metadata types (", metadata_label(M), ")",
    )))
end

key_subject(verb::Symbol, key::String) = string(verb, ": key \"", key, "\"")
key_subject(verb::Symbol, key::String, name::Symbol) = string(verb, ": key \"", key, "\" of column :", name)

table_metadata(df::Frame) = frame_metadata(df).table

column_metadata(df::Frame{C,M}, name::Symbol) where {C,M} =
    get(frame_metadata(df).columns, name, Dict{String,M}())

missing_key(key::String) = throw(ArgumentError(string("no metadata found for key \"", key, "\"")))
missing_key(key::String, name::Symbol) =
    throw(ArgumentError(string("no metadata found for key \"", key, "\" of column :", name)))

"""
    metadata(df, key)
    metadata(df, key, default)

The table-level metadata value of `key`. With several allowed metadata types the result has
the union of them, so narrow it with `::T` or `isa`.
"""
function metadata(df::Frame, key::AbstractString)
    entries = table_metadata(df)
    text = String(key)
    haskey(entries, text) || missing_key(text)
    return entries[text]
end

metadata(df::Frame, key::AbstractString, default) = get(table_metadata(df), String(key), default)

metadatakeys(df::Frame) = sort!(collect(keys(table_metadata(df))))

"""
    metadata!(df, key, value; style=:note)

Sets table-level metadata. Only `:note` metadata exists, so that is also the default.
"""
function metadata!(df::Frame{C,M}, key::AbstractString, value::V; style::Symbol = :note) where {C,M,V}
    check_style(:metadata!, style)
    text = String(key)
    V <: M || metadata_type_error(key_subject(:metadata!, text), typelabel(V), M)
    table_metadata(df)[text] = value
    return df
end

function deletemetadata!(df::Frame, key::AbstractString)
    delete!(table_metadata(df), String(key))
    return df
end

function emptymetadata!(df::Frame)
    empty!(table_metadata(df))
    return df
end

metadata_column_name(df::Frame, col::ColumnRef) = columnnames(df)[columnindex(df, col)]

"""
    colmetadata(df, col, key)
    colmetadata(df, col, key, default)

The column-level metadata value of `key`. With several allowed metadata types the result has
the union of them, so narrow it with `::T` or `isa`.
"""
function colmetadata(df::Frame, col::ColumnRef, key::AbstractString)
    name = metadata_column_name(df, col)
    entries = column_metadata(df, name)
    text = String(key)
    haskey(entries, text) || missing_key(text, name)
    return entries[text]
end

colmetadata(df::Frame, col::ColumnRef, key::AbstractString, default) =
    get(column_metadata(df, metadata_column_name(df, col)), String(key), default)

colmetadatakeys(df::Frame, col::ColumnRef) =
    sort!(collect(keys(column_metadata(df, metadata_column_name(df, col)))))

function colmetadatakeys(df::Frame)
    entries = Pair{Symbol,Vector{String}}[]
    for name in columnnames(df)
        isempty(column_metadata(df, name)) || push!(entries, name => colmetadatakeys(df, name))
    end
    return entries
end

"""
    colmetadata!(df, col, key, value; style=:note)

Sets column-level metadata. Only `:note` metadata exists, so that is also the default.
"""
function colmetadata!(df::Frame{C,M}, col::ColumnRef, key::AbstractString, value::V; style::Symbol = :note) where {C,M,V}
    check_style(:colmetadata!, style)
    name = metadata_column_name(df, col)
    text = String(key)
    V <: M || metadata_type_error(key_subject(:colmetadata!, text, name), typelabel(V), M)
    entries = get!(() -> Dict{String,M}(), frame_metadata(df).columns, name)
    entries[text] = value
    return df
end

function deletecolmetadata!(df::Frame, col::ColumnRef, key::AbstractString)
    name = metadata_column_name(df, col)
    all_columns = frame_metadata(df).columns
    if haskey(all_columns, name)
        delete!(all_columns[name], String(key))
        isempty(all_columns[name]) && delete!(all_columns, name)
    end
    return df
end

function emptycolmetadata!(df::Frame, col::ColumnRef)
    delete!(frame_metadata(df).columns, metadata_column_name(df, col))
    return df
end

function emptycolmetadata!(df::Frame)
    empty!(frame_metadata(df).columns)
    return df
end

function Base.copy(metadata::Metadata{M}) where {M}
    copied = Metadata{M}(copy(metadata.table), Dict{Symbol,Dict{String,M}}())
    for (name, entries) in metadata.columns
        copied.columns[name] = copy(entries)
    end
    return copied
end

function copy_column_metadata!(target::Metadata{M}, name::Symbol, entries::Dict{String,M}) where {M}
    isempty(entries) || (target.columns[name] = copy(entries))
    return target
end

function selected_metadata(df::Frame{C,M}, names::Vector{Symbol}) where {C,M}
    selected = Metadata{M}(copy(table_metadata(df)), Dict{Symbol,Dict{String,M}}())
    for name in names
        copy_column_metadata!(selected, name, column_metadata(df, name))
    end
    return selected
end

function derived_metadata(df::Frame{C,M}, names::Vector{Symbol}, origins::Dict{Symbol,Symbol}) where {C,M}
    derived = Metadata{M}(copy(table_metadata(df)), Dict{Symbol,Dict{String,M}}())
    for name in names
        haskey(origins, name) && copy_column_metadata!(derived, name, column_metadata(df, origins[name]))
    end
    return derived
end

keeps_metadata(f, source::Symbol, target::Symbol) = source === target
keeps_metadata(::typeof(identity), source::Symbol, target::Symbol) = true
keeps_metadata(::typeof(copy), source::Symbol, target::Symbol) = true

record_origin!(out::Output, names::Tuple, f::F, target) where {F} = nothing
function record_origin!(out::Output, names::Tuple{Symbol}, f::F, target::Symbol) where {F}
    keeps_metadata(f, names[1], target) && (out.origins[target] = names[1])
    return nothing
end

function rename_metadata!(df::Frame{C,M}, renamed::Vector{Symbol}) where {C,M}
    all_columns = frame_metadata(df).columns
    isempty(all_columns) && return df

    moved = Dict{Symbol,Dict{String,M}}()
    for (i, name) in enumerate(columnnames(df))
        haskey(all_columns, name) && (moved[renamed[i]] = all_columns[name])
    end
    empty!(all_columns)
    merge!(all_columns, moved)
    return df
end

function replace_metadata!(df::Frame, result::Frame)
    target, source = frame_metadata(df), frame_metadata(result)
    empty!(target.table)
    merge!(target.table, source.table)
    empty!(target.columns)
    merge!(target.columns, source.columns)
    return df
end

function metadata_equal(a::M, b::M) where {M}
    pair = M[a, b]
    return splitcolumns(values -> isequal(values[1], values[2]), pair, (1, 2))::Bool
end

function agrees_with_all(sources::Vector{Dict{String,M}}, key::String, value::M) where {M}
    for source in sources
        haskey(source, key) && metadata_equal(source[key], value) || return false
    end
    return true
end

function common_entries(sources::Vector{Dict{String,M}}) where {M}
    common = Dict{String,M}()
    isempty(sources) && return common
    for (key, value) in sources[1]
        agrees_with_all(sources, key, value) && (common[key] = value)
    end
    return common
end

function stacked_metadata(frames::Vector{Frame{C,M}}, names::Vector{Symbol}) where {C,M}
    stacked = Metadata{M}(common_entries(Dict{String,M}[table_metadata(df) for df in frames]), Dict{Symbol,Dict{String,M}}())
    for name in names
        sources = Dict{String,M}[column_metadata(df, name) for df in frames if hasproperty(df, name)]
        copy_column_metadata!(stacked, name, common_entries(sources))
    end
    return stacked
end

function joined_key_metadata(kind::Symbol, left::Dict{String,M}, right::Dict{String,M}) where {M}
    kind === :right && return right
    kind === :left && return left
    return common_entries(Dict{String,M}[left, right])
end

function joined_table_metadata(kind::Symbol, df1::Frame{C,M}, df2::Frame{C,M}) where {C,M}
    kind === :right && return copy(table_metadata(df2))
    kind === :left && return copy(table_metadata(df1))
    return common_entries(Dict{String,M}[table_metadata(df1), table_metadata(df2)])
end

function joined_metadata(kind::Symbol, df1::Frame{C,M}, df2::Frame{C,M}, keys::JoinKeys, names::Vector{Symbol}) where {C,M}
    joined = Metadata{M}(joined_table_metadata(kind, df1, df2), Dict{Symbol,Dict{String,M}}())

    for (i, name) in enumerate(columnnames(df1))
        position = findfirst(==(name), keys.left)
        entries = column_metadata(df1, name)
        if position !== nothing
            entries = joined_key_metadata(kind, entries, column_metadata(df2, keys.right[position]))
        end
        copy_column_metadata!(joined, names[i], entries)
    end

    i = ncol(df1)
    for name in columnnames(df2)
        name in keys.right && continue
        i += 1
        copy_column_metadata!(joined, names[i], column_metadata(df2, name))
    end
    return joined
end
