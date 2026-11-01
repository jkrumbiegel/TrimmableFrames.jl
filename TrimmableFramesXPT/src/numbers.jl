function field_bits(bytes::Vector{UInt8}, position::Int, width::Int)
    bits = UInt64(0)
    for i in 0:(width - 1)
        bits |= UInt64(bytes[position + i]) << (56 - 8i)
    end
    return bits
end

function is_missing_marker(byte::UInt8)
    return byte == UInt8('.') || byte == UInt8('_') || UInt8('A') <= byte <= UInt8('Z')
end

is_missing_number(bits::UInt64) = bits << 8 == 0 && is_missing_marker((bits >> 56) % UInt8)

const FRACTION_MASK = 0x00ffffffffffffff
const MAGNITUDE_MASK = 0x7fffffffffffffff

"""
    ibm_to_float(bits)

The value of an IBM double: a sign bit, a 7-bit power of 16 biased by 64, and a 56-bit
fraction. Bits below the 53 of a `Float64` are cut off, as ReadStat does, not rounded.
"""
function ibm_to_float(bits::UInt64)
    iszero(bits) && return 0.0

    negative = bits >> 63 == 1
    fraction = bits & FRACTION_MASK
    iszero(fraction) && return NaN
    bits & MAGNITUDE_MASK == MAGNITUDE_MASK && return negative ? -Inf : Inf

    power = Int((bits >> 56) & 0x7f) - 64
    shift = leading_zeros(fraction) - 11
    mantissa = shift >= 0 ? fraction << shift : fraction >> -shift
    magnitude = ldexp(Float64(mantissa), 4 * power - 56 - shift)
    return negative ? -magnitude : magnitude
end
