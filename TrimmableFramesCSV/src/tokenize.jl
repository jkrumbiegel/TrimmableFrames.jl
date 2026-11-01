const QUOTE = UInt8('"')
const LF = UInt8('\n')
const CR = UInt8('\r')

struct Field
    start::Int
    stop::Int
    escaped::Bool
    quoted::Bool
end

has_no_bytes(field::Field) = field.stop < field.start

is_missing(field::Field) = has_no_bytes(field) && !field.quoted

struct Table
    src::String
    fields::Vector{Field}
    width::Int
end

rowcount(table::Table) = length(table.fields) ÷ table.width - 1

field_at(table::Table, row::Int, col::Int) = table.fields[row * table.width + col]

function delimiter_byte(delim::Char)
    isascii(delim) && delim != '"' && delim != '\n' && delim != '\r' ||
        throw(ArgumentError("readcsv: delim must be a single-byte character other than a quote or line break"))
    return UInt8(delim)
end

is_linebreak(byte::UInt8) = byte == LF || byte == CR

function after_linebreak(src::String, pos::Int)
    crlf = codeunit(src, pos) == CR && pos < ncodeunits(src) && codeunit(src, pos + 1) == LF
    return pos + (crlf ? 2 : 1)
end

function quoted_field(src::String, opening::Int, delim::UInt8)
    n = ncodeunits(src)
    escaped = false
    pos = opening + 1
    while pos <= n
        if codeunit(src, pos) != QUOTE
            pos += 1
        elseif pos < n && codeunit(src, pos + 1) == QUOTE
            escaped = true
            pos += 2
        else
            ends_field = pos == n || codeunit(src, pos + 1) == delim || is_linebreak(codeunit(src, pos + 1))
            ends_field || throw(ArgumentError(string("readcsv: unexpected text after the quote closed at byte ", pos)))
            return Field(opening + 1, pos - 1, escaped, true), pos + 1
        end
    end
    throw(ArgumentError(string("readcsv: quote opened at byte ", opening, " is not closed")))
end

function plain_field(src::String, start::Int, delim::UInt8)
    n = ncodeunits(src)
    pos = start
    while pos <= n && codeunit(src, pos) != delim && !is_linebreak(codeunit(src, pos))
        pos += 1
    end
    return Field(start, pos - 1, false, false), pos
end

function read_field(src::String, pos::Int, delim::UInt8)
    is_quoted = pos <= ncodeunits(src) && codeunit(src, pos) == QUOTE
    return is_quoted ? quoted_field(src, pos, delim) : plain_field(src, pos, delim)
end

function read_row!(fields::Vector{Field}, src::String, start::Int, delim::UInt8)
    pos = start
    while true
        field, pos = read_field(src, pos, delim)
        push!(fields, field)
        pos > ncodeunits(src) && return pos
        codeunit(src, pos) == delim || return after_linebreak(src, pos)
        pos += 1
    end
end

function first_byte(src::String)
    has_bom = ncodeunits(src) >= 3 && codeunit(src, 1) == 0xef && codeunit(src, 2) == 0xbb && codeunit(src, 3) == 0xbf
    return has_bom ? 4 : 1
end

function tokenize(src::String, delim::UInt8)
    fields = Field[]
    width = 0
    row = 0
    pos = first_byte(src)
    while pos <= ncodeunits(src)
        if is_linebreak(codeunit(src, pos))
            pos = after_linebreak(src, pos)
            continue
        end

        before = length(fields)
        pos = read_row!(fields, src, pos, delim)
        found = length(fields) - before
        row == 0 && (width = found)
        found == width ||
            throw(ArgumentError(string("readcsv: row ", row, " has ", found, " fields, expected ", width)))
        row += 1
    end
    width == 0 && throw(ArgumentError("readcsv: the input has no header row"))
    return Table(src, fields, width)
end
