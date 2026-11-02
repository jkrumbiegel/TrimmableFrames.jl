const SAS_EPOCH_DATE = Date(1960, 1, 1)
const SAS_EPOCH_DATETIME = DateTime(1960, 1, 1)

const MAX_DAYS = 1.0e11
const SECONDS_PER_DAY = 86400.0
const NANOSECONDS_PER_DAY = 86_400_000_000_000

const DATE_FORMATS = [
    "WEEKDATE", "MMDDYY", "DDMMYY", "YYMMDD", "DATE",
    "DDMMYYB", "DDMMYYC", "DDMMYYD", "DDMMYYN", "DDMMYYP", "DDMMYYS",
    "MMDDYYB", "MMDDYYC", "MMDDYYD", "MMDDYYN", "MMDDYYP", "MMDDYYS",
    "MONNAME", "MONTH", "WEEKDATX", "WEEKDAY", "QTR", "QTRR", "YEAR",
    "YYMMDDB", "YYMMDDD", "YYMMDDN", "YYMMDDP", "YYMMDDS", "DAY", "DOWNAME",
    "E8601DA",
]

const DATETIME_FORMATS = [
    "DATETIME", "E8601DT", "E8601DX", "E8601DZ", "E8601LX", "E8601DN", "E8601LZ", "E8601TX", "E8601TZ",
]

const TIME_FORMATS = ["HHMM", "HOUR", "E8601TM"]

is_digit(byte::UInt8) = UInt8('0') <= byte <= UInt8('9')

"""
    format_name(format)

The name of a SAS format without its width and decimals: `DATETIME` for `DATETIME22.3`.
"""
function format_name(format::String)
    bytes = codeunits(format)
    stop = something(findfirst(==(UInt8('.')), bytes), length(bytes) + 1) - 1
    while stop > 0 && is_digit(bytes[stop])
        stop -= 1
    end
    return String(bytes[1:stop])
end

is_time_format(name::String) = startswith(name, "TIME") || name in TIME_FORMATS

function out_of_range(name::Symbol, value::Float64, label::String)
    throw(ArgumentError(string(
        "readxpt: column :", name, " has the value ", value, ", which is out of range for ", label,
        ". Leave ", label, " out of the allowed types to read this column as numbers",
    )))
end

stored_value(::Type{Float64}, value::Float64, ::Symbol) = value

function stored_value(::Type{Date}, value::Float64, name::Symbol)
    abs(value) <= MAX_DAYS || out_of_range(name, value, "Date")
    return SAS_EPOCH_DATE + Day(floor(Int64, value))
end

function stored_value(::Type{DateTime}, value::Float64, name::Symbol)
    abs(value) <= MAX_DAYS * SECONDS_PER_DAY || out_of_range(name, value, "DateTime")
    return SAS_EPOCH_DATETIME + Millisecond(round(Int64, value * 1000))
end

function stored_value(::Type{Time}, value::Float64, name::Symbol)
    0 <= value <= SECONDS_PER_DAY || out_of_range(name, value, "Time")
    nanoseconds = round(Int64, value * 1.0e9)
    nanoseconds < NANOSECONDS_PER_DAY || out_of_range(name, value, "Time")
    return Time(Nanosecond(nanoseconds))
end
