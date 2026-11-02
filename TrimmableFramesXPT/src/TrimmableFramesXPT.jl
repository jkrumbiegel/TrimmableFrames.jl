module TrimmableFramesXPT

using Dates: Date, DateTime, Day, Millisecond, Nanosecond, Time
using TrimmableFrames: Frame, colmetadata!, fitcolumn, metadata!

export readxpt

include("layout.jl")
include("numbers.jl")
include("dates.jl")
include("columns.jl")

"""
    readxpt(DF, bytes::Vector{UInt8})

Reads the data set of a SAS transport file, version 5, 8 or 9, into a frame of type `DF`.

Numeric variables become `Float64` columns, or `Union{Missing,Float64}` if they have missing
values of any kind, and character variables become `String` columns. A numeric variable with
a SAS date, datetime or time format becomes a `Date`, `DateTime` or `Time` column if that type
is allowed in `DF`, and stays a number otherwise. A type outside the allowed types of `DF`
throws a `ColumnTypeError`. Labels and formats become metadata, which
needs `String` among the allowed metadata types. Integer entries such as `storage_width` are
set if `Int64` is allowed as well.
"""
function readxpt(::Type{Frame{C,M}}, bytes::Vector{UInt8}) where {C,M}
    String <: M || throw(ArgumentError("readxpt: metadata needs String among the allowed metadata types"))

    layout = read_layout(bytes)
    cols = C[]
    offset = 0
    for variable in layout.variables
        push!(cols, read_column(C, bytes, layout, variable, offset))
        offset += variable.storage_width
    end

    df = Frame{C,M}(Symbol[Symbol(v.name) for v in layout.variables], cols)
    set_table_metadata!(df, layout)
    for variable in layout.variables
        set_column_metadata!(df, variable)
    end
    return df
end

function set_integer!(df::Frame{C,M}, name::Symbol, key::String, value::Int) where {C,M}
    if Int64 <: M
        colmetadata!(df, name, key, value)
    end
    return df
end

function set_table_metadata!(df::Frame{C,M}, layout::Layout) where {C,M}
    metadata!(df, "table_name", layout.table_name)
    metadata!(df, "file_label", layout.file_label)
    metadata!(df, "creation_time", layout.creation_time)
    metadata!(df, "modified_time", layout.modified_time)
    if Int64 <: M
        metadata!(df, "file_format_version", layout.version)
    end
    return df
end

function set_column_metadata!(df::Frame, variable::Variable)
    name = Symbol(variable.name)
    colmetadata!(df, name, "label", variable.label)
    colmetadata!(df, name, "format", variable.format)
    set_integer!(df, name, "storage_width", variable.storage_width)
    set_integer!(df, name, "display_width", variable.display_width)
    set_integer!(df, name, "decimals", variable.decimals)
    return df
end

end
