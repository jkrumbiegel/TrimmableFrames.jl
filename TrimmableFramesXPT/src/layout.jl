const RECORD_LENGTH = 80
const HEADER_PREFIX = codeunits("HEADER RECORD*******")

struct Variable
    name::String
    label::String
    format::String
    storage_width::Int
    display_width::Int
    decimals::Int
    numeric::Bool
end

struct Layout
    version::Int
    table_name::String
    file_label::String
    creation_time::String
    modified_time::String
    variables::Vector{Variable}
    row_length::Int
    data_start::Int
    nrows::Int
end

function need(bytes::Vector{UInt8}, position::Int, count::Int, part::String)
    position + count - 1 <= length(bytes) ||
        throw(ArgumentError(string("readxpt: the input ends inside ", part, " at byte ", position)))
end

function trimmed_text(bytes::Vector{UInt8}, start::Int, stop::Int)
    last_byte = stop
    while last_byte >= start && (bytes[last_byte] == UInt8(' ') || bytes[last_byte] == 0x00)
        last_byte -= 1
    end
    return String(bytes[start:last_byte])
end

big_endian16(bytes::Vector{UInt8}, position::Int) = Int(bytes[position]) << 8 | Int(bytes[position + 1])

function has_header_prefix(bytes::Vector{UInt8}, position::Int)
    position + RECORD_LENGTH - 1 <= length(bytes) || return false
    for i in eachindex(HEADER_PREFIX)
        bytes[position + i - 1] == HEADER_PREFIX[i] || return false
    end
    return true
end

header_name(bytes::Vector{UInt8}, position::Int) =
    has_header_prefix(bytes, position) ? trimmed_text(bytes, position + 20, position + 27) : ""

function expect_header(bytes::Vector{UInt8}, position::Int, name::String)
    need(bytes, position, RECORD_LENGTH, string("the ", name, " header"))
    header_name(bytes, position) == name ||
        throw(ArgumentError(string("readxpt: expected a ", name, " header at byte ", position)))
    return position + RECORD_LENGTH
end

function decimal_field(bytes::Vector{UInt8}, start::Int, stop::Int)
    value = 0
    for position in start:stop
        byte = bytes[position]
        UInt8('0') <= byte <= UInt8('9') || continue
        value = value * 10 + Int(byte - UInt8('0'))
    end
    return value
end

next_record(position::Int) = position + mod(1 - position, RECORD_LENGTH)

function format_text(name::String, width::Int, decimals::Int)
    decimals != 0 && return string(name, width, ".", decimals)
    width != 0 && return string(name, width, ".")
    return name
end

function read_variable(bytes::Vector{UInt8}, start::Int, version::Int)
    numeric = big_endian16(bytes, start) == 1
    storage_width = big_endian16(bytes, start + 4)
    name = version == 5 ? trimmed_text(bytes, start + 8, start + 15) : trimmed_text(bytes, start + 88, start + 119)
    display_width = big_endian16(bytes, start + 64)
    decimals = big_endian16(bytes, start + 66)
    format = format_text(trimmed_text(bytes, start + 56, start + 63), display_width, decimals)

    if numeric && !(2 <= storage_width <= 8)
        throw(ArgumentError(string("readxpt: column :", name, " has numeric width ", storage_width, ", expected 2 to 8")))
    end
    return Variable(name, trimmed_text(bytes, start + 16, start + 55), format, storage_width, display_width, decimals, numeric)
end

function read_variables(bytes::Vector{UInt8}, start::Int, count::Int, size::Int, version::Int)
    need(bytes, start, count * size, "the variable descriptors")
    return Variable[read_variable(bytes, start + (i - 1) * size, version) for i in 1:count]
end

function read_long_labels!(variables::Vector{Variable}, bytes::Vector{UInt8}, start::Int, count::Int, has_formats::Bool)
    position = start
    entry_size = has_formats ? 10 : 6
    for _ in 1:count
        need(bytes, position, entry_size, "the long labels")
        index = big_endian16(bytes, position)
        name_length = big_endian16(bytes, position + 2)
        label_length = big_endian16(bytes, position + 4)
        format_length = has_formats ? big_endian16(bytes, position + 6) : 0
        informat_length = has_formats ? big_endian16(bytes, position + 8) : 0
        position += entry_size

        need(bytes, position, name_length + label_length + format_length + informat_length, "the long labels")
        1 <= index <= length(variables) ||
            throw(ArgumentError(string("readxpt: a long label refers to variable ", index, ", which does not exist")))

        name = trimmed_text(bytes, position, position + name_length - 1)
        position += name_length
        label = trimmed_text(bytes, position, position + label_length - 1)
        position += label_length
        format = has_formats ? trimmed_text(bytes, position, position + format_length - 1) : variables[index].format
        position += format_length + informat_length

        v = variables[index]
        variables[index] = Variable(name, label, format, v.storage_width, v.display_width, v.decimals, v.numeric)
    end
    return next_record(position)
end

function read_observation_header!(variables::Vector{Variable}, bytes::Vector{UInt8}, position::Int, version::Int)
    version == 5 && return expect_header(bytes, position, "OBS"), 0

    need(bytes, position, RECORD_LENGTH, "the OBSV8 header")
    name = header_name(bytes, position)
    if name == "LABELV8" || name == "LABELV9"
        count = decimal_field(bytes, position + 48, position + 52)
        position = read_long_labels!(variables, bytes, position + RECORD_LENGTH, count, name == "LABELV9")
    end
    start = expect_header(bytes, position, "OBSV8")
    return start, decimal_field(bytes, position + 48, position + 62)
end

function check_single_member(bytes::Vector{UInt8}, data_start::Int)
    position = data_start
    while position + RECORD_LENGTH - 1 <= length(bytes)
        if bytes[position] == UInt8('H')
            name = header_name(bytes, position)
            if name == "MEMBER" || name == "MEMBV8"
                throw(ArgumentError("readxpt: the file has more than one data set, which is not supported"))
            end
        end
        position += RECORD_LENGTH
    end
end

function is_blank_row(bytes::Vector{UInt8}, start::Int, row_length::Int)
    for position in start:(start + row_length - 1)
        bytes[position] == UInt8(' ') || return false
    end
    return true
end

# A file ends on a full record, padded with blanks that look like rows narrower than a record.
function row_count(bytes::Vector{UInt8}, data_start::Int, row_length::Int, declared::Int)
    row_length == 0 && return 0
    available = (length(bytes) - data_start + 1) ÷ row_length
    declared > 0 && return min(declared, available)
    row_length >= RECORD_LENGTH && return available

    rows = available
    while rows > 0 && is_blank_row(bytes, data_start + (rows - 1) * row_length, row_length)
        rows -= 1
    end
    return rows
end

function library_version(bytes::Vector{UInt8})
    name = header_name(bytes, 1)
    name == "LIBRARY" && return 5
    name == "LIBV8" && return 8
    throw(ArgumentError("readxpt: this is not a SAS transport file"))
end

function read_layout(bytes::Vector{UInt8})
    version = library_version(bytes)
    need(bytes, 1, 3 * RECORD_LENGTH, "the library header")
    creation_time = trimmed_text(bytes, RECORD_LENGTH + 65, RECORD_LENGTH + 80)
    modified_time = trimmed_text(bytes, 2 * RECORD_LENGTH + 1, 2 * RECORD_LENGTH + 16)

    member = 3 * RECORD_LENGTH + 1
    position = expect_header(bytes, member, version == 5 ? "MEMBER" : "MEMBV8")
    descriptor_size = decimal_field(bytes, member + 74, member + 77)
    position = expect_header(bytes, position, version == 5 ? "DSCRPTR" : "DSCPTV8")

    need(bytes, position, 2 * RECORD_LENGTH, "the data set header")
    table_name = trimmed_text(bytes, position + 8, position + (version == 5 ? 15 : 39))
    file_label = trimmed_text(bytes, position + RECORD_LENGTH + 32, position + RECORD_LENGTH + 71)
    position += 2 * RECORD_LENGTH

    names_header = position
    position = expect_header(bytes, position, version == 5 ? "NAMESTR" : "NAMSTV8")
    variable_count = decimal_field(bytes, names_header + 53, names_header + 57)
    variables = read_variables(bytes, position, variable_count, descriptor_size == 0 ? 140 : descriptor_size, version)
    position = next_record(position + variable_count * (descriptor_size == 0 ? 140 : descriptor_size))

    data_start, declared_rows = read_observation_header!(variables, bytes, position, version)
    check_single_member(bytes, data_start)

    row_length = sum(v -> v.storage_width, variables; init = 0)
    nrows = row_count(bytes, data_start, row_length, declared_rows)
    return Layout(version, table_name, file_label, creation_time, modified_time, variables, row_length, data_start, nrows)
end
