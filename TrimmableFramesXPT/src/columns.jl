cell_position(layout::Layout, row::Int, offset::Int) = layout.data_start + (row - 1) * layout.row_length + offset

function has_missing_number(bytes::Vector{UInt8}, layout::Layout, variable::Variable, offset::Int)
    for row in 1:layout.nrows
        bits = field_bits(bytes, cell_position(layout, row, offset), variable.storage_width)
        is_missing_number(bits) && return true
    end
    return false
end

function fill_numbers!(out::Vector{E}, ::Type{T}, bytes::Vector{UInt8}, layout::Layout, variable::Variable, offset::Int) where {E,T}
    name = Symbol(variable.name)
    for row in eachindex(out)
        bits = field_bits(bytes, cell_position(layout, row, offset), variable.storage_width)
        if !is_missing_number(bits)
            out[row] = stored_value(T, ibm_to_float(bits), name)
        elseif Missing <: E
            out[row] = missing
        end
    end
    return out
end

function number_column(::Type{C}, ::Type{T}, bytes::Vector{UInt8}, layout::Layout, variable::Variable, offset::Int) where {C,T}
    name = Symbol(variable.name)
    if has_missing_number(bytes, layout, variable, offset)
        values = fill_numbers!(Vector{Union{Missing,T}}(undef, layout.nrows), T, bytes, layout, variable, offset)
        return fitcolumn(C, :readxpt, name, values, false)::C
    end
    values = fill_numbers!(Vector{T}(undef, layout.nrows), T, bytes, layout, variable, offset)
    return fitcolumn(C, :readxpt, name, values, false)::C
end

function text_column(::Type{C}, bytes::Vector{UInt8}, layout::Layout, variable::Variable, offset::Int) where {C}
    values = Vector{String}(undef, layout.nrows)
    for row in eachindex(values)
        start = cell_position(layout, row, offset)
        values[row] = trimmed_text(bytes, start, start + variable.storage_width - 1)
    end
    return fitcolumn(C, :readxpt, Symbol(variable.name), values, false)::C
end

allows(::Type{C}, ::Type{T}) where {C,T} = Vector{T} <: C || Vector{Union{Missing,T}} <: C

function read_column(::Type{C}, bytes::Vector{UInt8}, layout::Layout, variable::Variable, offset::Int) where {C}
    variable.numeric || return text_column(C, bytes, layout, variable, offset)

    name = format_name(variable.format)
    allows(C, Date) && name in DATE_FORMATS && return number_column(C, Date, bytes, layout, variable, offset)
    allows(C, DateTime) && name in DATETIME_FORMATS && return number_column(C, DateTime, bytes, layout, variable, offset)
    allows(C, Time) && is_time_format(name) && return number_column(C, Time, bytes, layout, variable, offset)
    return number_column(C, Float64, bytes, layout, variable, offset)
end
