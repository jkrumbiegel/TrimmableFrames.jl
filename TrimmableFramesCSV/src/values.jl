@enum FieldKind EMPTY BOOL INT FLOAT TEXT

field_view(src::String, field::Field) = SubString(src, field.start, thisind(src, field.stop))

function text_value(src::String, field::Field)
    has_no_bytes(field) && return ""
    field.escaped || return String(field_view(src, field))

    out = UInt8[]
    pos = field.start
    while pos <= field.stop
        byte = codeunit(src, pos)
        push!(out, byte)
        pos += byte == QUOTE ? 2 : 1
    end
    return String(out)
end

function trimmed_range(src::String, field::Field)
    start, stop = field.start, field.stop
    while start <= stop && codeunit(src, start) == UInt8(' ')
        start += 1
    end
    while start <= stop && codeunit(src, stop) == UInt8(' ')
        stop -= 1
    end
    return start, stop
end

function integer_value(src::String, field::Field)
    start, stop = trimmed_range(src, field)
    start > stop && return false, Int64(0)

    sign_byte = codeunit(src, start)
    negative = sign_byte == UInt8('-')
    if negative || sign_byte == UInt8('+')
        start += 1
        start > stop && return false, Int64(0)
    end

    # accumulated below zero, since typemin(Int64) has no positive counterpart
    value = Int64(0)
    for pos in start:stop
        digit = Int64(codeunit(src, pos)) - Int64(UInt8('0'))
        0 <= digit <= 9 || return false, Int64(0)
        value, overflowed_mul = Base.mul_with_overflow(value, Int64(10))
        value, overflowed_sub = Base.sub_with_overflow(value, digit)
        (overflowed_mul || overflowed_sub) && return false, Int64(0)
    end

    negative && return true, value
    value == typemin(Int64) && return false, Int64(0)
    return true, -value
end

function has_hex_marker(src::String, field::Field)
    for pos in field.start:field.stop
        byte = codeunit(src, pos)
        (byte == UInt8('x') || byte == UInt8('X')) && return true
    end
    return false
end

function float_value(src::String, field::Field)
    has_hex_marker(src, field) && return nothing
    return tryparse(Float64, field_view(src, field))
end

function bool_value(src::String, field::Field)
    length_in_bytes = field.stop - field.start + 1
    (length_in_bytes == 4 || length_in_bytes == 5) || return nothing
    text = field_view(src, field)
    (text == "true" || text == "True" || text == "TRUE") && return true
    (text == "false" || text == "False" || text == "FALSE") && return false
    return nothing
end

function field_kind(src::String, field::Field)
    is_missing(field) && return EMPTY
    (field.escaped || has_no_bytes(field)) && return TEXT
    bool_value(src, field) === nothing || return BOOL
    first(integer_value(src, field)) && return INT
    float_value(src, field) === nothing || return FLOAT
    return TEXT
end

parse_value(::Type{Bool}, src::String, field::Field) = bool_value(src, field)::Bool
parse_value(::Type{Int64}, src::String, field::Field) = last(integer_value(src, field))
parse_value(::Type{String}, src::String, field::Field) = text_value(src, field)

function parse_value(::Type{Float64}, src::String, field::Field)
    is_integer, value = integer_value(src, field)
    is_integer ? Float64(value) : float_value(src, field)::Float64
end
