function unique_name(name::String, taken::Vector{Symbol})
    Symbol(name) in taken || return Symbol(name)
    suffix = 1
    while Symbol(name, "_", suffix) in taken
        suffix += 1
    end
    return Symbol(name, "_", suffix)
end

function unique_names(table::Table)
    names = Symbol[]
    for col in 1:table.width
        text = text_value(table.src, field_at(table, 0, col))
        push!(names, unique_name(isempty(text) ? string("Column", col) : text, names))
    end
    return names
end

function check_strings(strings::Vector{Symbol}, names::Vector{Symbol})
    for name in strings
        name in names ||
            throw(ArgumentError(string("readcsv: strings names column :", name, ", which is not in the input")))
    end
end

function mixture_error(name::Symbol, description::String, table::Table, row::Int, col::Int)
    text = text_value(table.src, field_at(table, row, col))
    throw(ArgumentError(string("readcsv: column :", name, " mixes ", description, ": row ", row, " has \"", text, "\"")))
end

is_number(kind::FieldKind) = kind === INT || kind === FLOAT

function merged_kind(kind::FieldKind, kind_row::Int, current::FieldKind, row::Int, name::Symbol, table::Table, col::Int)
    kind === TEXT && mixture_error(name, "numbers or booleans with text", table, kind_row, col)
    current === TEXT && mixture_error(name, "numbers or booleans with text", table, row, col)
    kind === BOOL && mixture_error(name, "numbers and booleans", table, kind_row, col)
    current === BOOL && mixture_error(name, "numbers and booleans", table, row, col)
    return FLOAT
end

function column_kind(table::Table, col::Int, name::Symbol, as_text::Bool)
    kind = EMPTY
    kind_row = 0
    has_missing = false
    for row in 1:rowcount(table)
        field = field_at(table, row, col)
        current = is_missing(field) ? EMPTY : as_text ? TEXT : field_kind(table.src, field)
        if current === EMPTY
            has_missing = true
        elseif kind === EMPTY
            kind, kind_row = current, row
        elseif current !== kind
            kind = merged_kind(kind, kind_row, current, row, name, table, col)
        end
    end
    return kind, has_missing
end

function parsed_column!(out::Vector{E}, ::Type{T}, table::Table, col::Int) where {E,T}
    for row in eachindex(out)
        field = field_at(table, row, col)
        if !is_missing(field)
            out[row] = parse_value(T, table.src, field)
        elseif Missing <: E
            out[row] = missing
        end
    end
    return out
end

function typed_column(::Type{C}, ::Type{T}, table::Table, col::Int, name::Symbol, has_missing::Bool) where {C,T}
    nrows = rowcount(table)
    has_missing && return fitcolumn(C, :readcsv, name, parsed_column!(Vector{Union{Missing,T}}(undef, nrows), T, table, col), false)::C
    return fitcolumn(C, :readcsv, name, parsed_column!(Vector{T}(undef, nrows), T, table, col), false)::C
end

function read_column(::Type{C}, table::Table, col::Int, name::Symbol, as_text::Bool) where {C}
    kind, has_missing = column_kind(table, col, name, as_text)
    kind === BOOL && return typed_column(C, Bool, table, col, name, has_missing)
    kind === INT && return typed_column(C, Int64, table, col, name, has_missing)
    kind === FLOAT && return typed_column(C, Float64, table, col, name, has_missing)
    kind === TEXT && return typed_column(C, String, table, col, name, has_missing)
    return fitcolumn(C, :readcsv, name, Vector{Missing}(missing, rowcount(table)), false)::C
end
