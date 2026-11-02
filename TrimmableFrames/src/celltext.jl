"""
    celltext(x)

The text of a value in `show`. Equal to `string(x)`, but for Dates types written without
`lpad` and `@sprintf`, which the juliac verifier rejects.
"""
celltext(x) = string(x)

function zero_padded(n::Int64, width::Int)
    digits = string(abs(n))
    sign = n < 0 ? "-" : ""
    return string(sign, repeated('0', width - length(digits)), digits)
end

function celltext(date::Date)
    y, m, d = yearmonthday(date)
    return string(zero_padded(Int64(y), 4), "-", zero_padded(Int64(m), 2), "-", zero_padded(Int64(d), 2))
end

clocktext(h::Integer, m::Integer, s::Integer) =
    string(zero_padded(Int64(h), 2), ":", zero_padded(Int64(m), 2), ":", zero_padded(Int64(s), 2))

function celltext(stamp::DateTime)
    text = string(celltext(Date(stamp)), "T", clocktext(hour(stamp), minute(stamp), second(stamp)))
    milli = millisecond(stamp)
    return milli == 0 ? text : string(text, ".", zero_padded(Int64(milli), 3))
end

function celltext(clock::Time)
    text = clocktext(hour(clock), minute(clock), second(clock))
    fraction = Dates.value(clock) % 1_000_000_000
    fraction == 0 && return text
    return string(text, ".", rstrip(zero_padded(fraction, 9), '0'))
end
