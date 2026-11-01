module XPTBuilder

struct Variable
    name::String
    label::String
    format::String
    display_width::Int
    decimals::Int
    storage_width::Int
    numeric::Bool
end

number(name; label = "", format = "", display_width = 0, decimals = 0, storage_width = 8) =
    Variable(name, label, format, display_width, decimals, storage_width, true)
text(name, storage_width; label = "") = Variable(name, label, "", 0, 0, storage_width, false)

struct Tagged
    byte::UInt8
end

padded(s::AbstractString, n::Int) = UInt8[Vector{UInt8}(s); fill(UInt8(' '), n - ncodeunits(s))]

header(name::String, suffix::String) = padded(string("HEADER RECORD*******", rpad(name, 8), "HEADER RECORD!!!!!!!", suffix), 80)

function big_endian(x::UInt16)
    return UInt8[x >> 8, x & 0xff]
end

big_endian(x::UInt32) = UInt8[(x >> 24) % UInt8, (x >> 16) % UInt8, (x >> 8) % UInt8, x % UInt8]

function namestr(v::Variable, varnum::Int, position::Int)
    out = UInt8[]
    append!(out, big_endian(UInt16(v.numeric ? 1 : 2)))
    append!(out, big_endian(UInt16(0)))
    append!(out, big_endian(UInt16(v.storage_width)))
    append!(out, big_endian(UInt16(varnum)))
    append!(out, padded(v.name, 8))
    append!(out, padded(v.label, 40))
    append!(out, padded(v.format, 8))
    append!(out, big_endian(UInt16(v.display_width)))
    append!(out, big_endian(UInt16(v.decimals)))
    append!(out, big_endian(UInt16(0)))
    append!(out, zeros(UInt8, 2))
    append!(out, padded("", 8))
    append!(out, big_endian(UInt16(0)))
    append!(out, big_endian(UInt16(0)))
    append!(out, big_endian(UInt32(position)))
    append!(out, zeros(UInt8, 52))
    return out
end

function ibm_bytes(x::Float64, width::Int)
    iszero(x) && return zeros(UInt8, width)
    exponent = 0
    fraction = abs(x)
    while fraction >= 1
        fraction /= 16
        exponent += 1
    end
    while fraction < 1 / 16
        fraction *= 16
        exponent -= 1
    end
    bits = round(UInt64, fraction * 2.0^56)
    first_byte = UInt8((x < 0 ? 0x80 : 0x00) | UInt8(exponent + 64))
    return [first_byte; UInt8[(bits >> (48 - 8 * i)) % UInt8 for i in 0:6]][1:width]
end

encode(v::Variable, x::Float64) = ibm_bytes(x, v.storage_width)
encode(v::Variable, ::Missing) = [UInt8('.'); zeros(UInt8, v.storage_width - 1)]
encode(v::Variable, tag::Tagged) = [tag.byte; zeros(UInt8, v.storage_width - 1)]
encode(v::Variable, s::String) = padded(s, v.storage_width)

record_padded(bytes::Vector{UInt8}) = [bytes; fill(UInt8(' '), mod(-length(bytes), 80))]

function member(variables, rows; table_name = "SAMPLE", file_label = "A label", descriptor_size = 140)
    out = UInt8[]
    append!(out, header("MEMBER", string(repeat('0', 16), "0160000000", lpad(descriptor_size, 4, '0'))))
    append!(out, header("DSCRPTR", repeat('0', 30)))
    append!(out, padded(string(rpad("SAS", 8), rpad(table_name, 8), rpad("SASDATA", 8), rpad("9.4", 8), rpad("Linux", 8), repeat(' ', 24), "01JAN20:00:00:00"), 80))
    append!(out, padded(string("01JAN20:00:00:00", repeat(' ', 16), rpad(file_label, 40), rpad("DATA", 8)), 80))
    append!(out, header("NAMESTR", string("000000", lpad(length(variables), 4, '0'), repeat('0', 20))))

    names = UInt8[]
    position = 0
    for (i, v) in enumerate(variables)
        append!(names, namestr(v, i, position)[1:descriptor_size])
        position += v.storage_width
    end
    append!(out, record_padded(names))

    append!(out, header("OBS", repeat('0', 30)))
    data = UInt8[]
    for row in rows
        for (v, x) in zip(variables, row)
            append!(data, encode(v, x))
        end
    end
    append!(out, record_padded(data))
    return out
end

function library()
    out = UInt8[]
    append!(out, header("LIBRARY", repeat('0', 30)))
    append!(out, padded(string(rpad("SAS", 8), rpad("SAS", 8), rpad("SASLIB", 8), rpad("9.4", 8), rpad("Linux", 8), repeat(' ', 24), "01JAN20:00:00:00"), 80))
    append!(out, padded("01JAN20:00:00:00", 80))
    return out
end

file(variables, rows; kwargs...) = [library(); member(variables, rows; kwargs...)]

end
