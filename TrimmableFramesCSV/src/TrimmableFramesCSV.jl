module TrimmableFramesCSV

using TrimmableFrames: Frame, fitcolumn

export readcsv

include("tokenize.jl")
include("values.jl")
include("columns.jl")

"""
    readcsv(DF, source; delim = ',', strings = Symbol[])

Reads CSV text into a frame of type `DF`, from a `String` or from a `Vector{UInt8}`.

Each column gets the narrowest of `Bool`, `Int64`, `Float64` and `String` that holds its
values, with `Missing` added if a field is empty. `Int64` and `Float64` values in one column
give `Float64`. Other mixtures throw an `ArgumentError`, and a type outside the allowed types
of `DF` throws a `ColumnTypeError`. `strings` lists columns to keep as text, for values such
as `01234`.
"""
function readcsv(::Type{Frame{C}}, source::AbstractString; delim::Char = ',', strings::Vector{Symbol} = Symbol[]) where {C}
    src = String(source)
    table = tokenize(src, delimiter_byte(delim))
    names = unique_names(table)
    check_strings(strings, names)

    cols = C[]
    for col in 1:table.width
        push!(cols, read_column(C, table, col, names[col], names[col] in strings))
    end
    return Frame{C}(names, cols)
end

readcsv(::Type{Frame{C}}, bytes::Vector{UInt8}; delim::Char = ',', strings::Vector{Symbol} = Symbol[]) where {C} =
    readcsv(Frame{C}, String(copy(bytes)); delim, strings)

end
