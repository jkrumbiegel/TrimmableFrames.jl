module Programs

using TrimmableFrames
using TrimmableFramesXPT
using Dates

include("../builder.jl")
using .XPTBuilder: Tagged, file, member, number, text

const DF = frametype(String, Int64, Float64, Bool; allowmissing = true, metadata = (String, Int64))

const VARIABLES = [
    number("AGE"; label = "Age", format = "BEST", display_width = 12),
    text("SEX", 2; label = "Sex"),
    number("WEIGHT"; label = "Weight", storage_width = 4),
]
const ROWS = [(34.0, "F", 61.5), (missing, "M", 80.25), (Tagged(UInt8('A')), "", 0.0), (-1.5e-3, "F", 1.0e4)]
const SAMPLE = file(VARIABLES, ROWS; table_name = "DM", file_label = "Demographics")
const SEVERAL = [SAMPLE; member(VARIABLES, ROWS)]
const INPUT = UInt8[]

function render(df)
    io = IOBuffer()
    show(io, df)
    println(Core.stdout, String(take!(io)))
    return nrow(df)
end

metadata_text(value) = value isa String ? value : string(value::Int64)

function render_metadata(df)
    for key in metadatakeys(df)
        println(Core.stdout, key, " = ", metadata_text(metadata(df, key)))
    end
    for (name, keys) in colmetadatakeys(df)
        for key in keys
            println(Core.stdout, name, ".", key, " = ", metadata_text(colmetadata(df, name, key)))
        end
    end
    return render(df)
end

function caught_message(e)
    e isa ColumnTypeError && return e.msg
    e isa ArgumentError && return e.msg::String
    return "unexpected error"
end

function catching(f::F) where {F}
    try
        return f()
    catch e
        println(Core.stdout, caught_message(e))
        return -1
    end
end

function total(x)
    sum = 0.0
    for value in x
        value === missing || (sum += value)
    end
    return sum
end

p_read() = render(readxpt(DF, SAMPLE))
p_metadata() = render_metadata(readxpt(DF, SAMPLE))
p_pipeline() = render_metadata(combine(groupby(readxpt(DF, SAMPLE), :SEX), :WEIGHT => total => :WEIGHT))
p_labels_only() = render_metadata(readxpt(frametype(String, Float64; allowmissing = true), SAMPLE))
p_error_format() = catching(() -> render(readxpt(DF, UInt8[0x61, 0x62])))
p_error_several() = catching(() -> render(readxpt(DF, SEVERAL)))
p_error_truncated() = catching(() -> render(readxpt(DF, SAMPLE[1:500])))
p_error_type() = catching(() -> render(readxpt(frametype(String), SAMPLE)))

const Dated = frametype(String, Float64, Date, DateTime, Time; allowmissing = true, metadata = (String, Int64))

const VISITS = file(
    [
        number("VISITDT"; label = "Visit date", format = "DATE", display_width = 9),
        number("STAMP"; format = "E8601DT", display_width = 19),
        number("CLOCK"; format = "TIME", display_width = 8),
        number("DOSE"),
    ],
    [(23742.0, 2.0513088e9, 3661.0, 1.0), (missing, 0.5, 86399.5, 2.0), (23742.0, -1.0, 0.0, 4.0)],
)

p_dates() = render_metadata(readxpt(Dated, VISITS))
p_dates_as_numbers() = render(readxpt(DF, VISITS))
p_dates_pipeline() = render_metadata(combine(groupby(readxpt(Dated, VISITS), :VISITDT; sort = true), :DOSE => total => :DOSE, :CLOCK => maximum => :CLOCK))
p_error_date_range() = catching(() -> render(readxpt(Dated, file([number("D"; format = "DATE")], [(1.0e15,)]))))

const ENTRY_POINTS = (
    p_dates, p_dates_as_numbers, p_dates_pipeline, p_error_date_range,
    p_read, p_metadata, p_pipeline, p_labels_only,
    p_error_format, p_error_several, p_error_truncated, p_error_type,
)

function reset_input(capacity::Int)
    empty!(INPUT)
    sizehint!(INPUT, capacity)
    return 0
end

function push_word(word::Int64)
    for shift in 0:8:56
        push!(INPUT, (word >> shift) % UInt8)
    end
    return 0
end

function read_input(nbytes::Int)
    resize!(INPUT, nbytes)
    return nrow(readxpt(DF, INPUT))
end

large_file(rows::Int) = file([number("ID"), text("NAME", 8), number("SCORE")], [(Float64(i), string("n", i % 100), i / 8) for i in 1:rows])

end
