module Programs

using TrimmableFrames
using TrimmableFramesCSV

const DF = frametype(String, Int64, Float64, Bool; allowmissing = true)
const SAMPLE = "id,name,score,ok\n1,ann,1.5,true\n2,\"b,\"\"c\",,false\n3,ä,2,\n"
const INPUT = UInt8[]

function render(df)
    io = IOBuffer()
    show(io, df)
    println(Core.stdout, String(take!(io)))
    return nrow(df)
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

function score_total(x)
    total = 0.0
    for value in x
        value === missing || (total += value)
    end
    return total
end

p_read() = render(readcsv(DF, SAMPLE))
p_read_bytes() = render(readcsv(DF, Vector{UInt8}(SAMPLE)))
p_read_options() = render(readcsv(DF, "zip;n\n01234;1\n;2\n"; delim = ';', strings = [:zip]))
p_pipeline() = render(combine(groupby(readcsv(DF, "k,x\na,1\nb,2.5\na,\n"), :k), :x => score_total => :total))
p_error_mixture() = catching(() -> render(readcsv(DF, "a\n1\nx\n")))
p_error_row() = catching(() -> render(readcsv(DF, "a,b\n1\n")))
p_error_quote() = catching(() -> render(readcsv(DF, "a\n\"x\n")))
p_error_type() = catching(() -> render(readcsv(frametype(String, Int64), "a\n1.5\n")))

const ENTRY_POINTS = (
    p_read, p_read_bytes, p_read_options, p_pipeline,
    p_error_mixture, p_error_row, p_error_quote, p_error_type,
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
    return nrow(readcsv(DF, INPUT))
end

end
