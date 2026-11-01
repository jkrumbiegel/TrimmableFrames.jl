using Test
using TrimmableFrames
using TrimmableFramesCSV
using Supposition
import CSV
import DataFrames

const DF = frametype(String, Int64, Float64, Bool; allowmissing = true)

csvjl(text) = CSV.read(IOBuffer(text), DataFrames.DataFrame; stringtype = String, pool = false, ntasks = 1)

matches_type(ours, theirs) = eltype(theirs) === Missing || ours isa Vector{eltype(theirs)}

function agrees_with_csvjl(text)
    ours = readcsv(DF, text)
    theirs = csvjl(text)
    names(ours) == names(theirs) || return false
    for name in names(ours)
        matches_type(ours[!, name], theirs[!, name]) || return false
        isequal(ours[!, name], theirs[!, name]) || return false
    end
    return true
end

@testset "TrimmableFramesCSV" begin
    @testset "column types" begin
        df = readcsv(DF, "a,b,c,d\n1,1.5,x,true\n2,2.5,y,false\n")
        @test names(df) == ["a", "b", "c", "d"]
        @test df.a::Vector{Int64} == [1, 2]
        @test df.b::Vector{Float64} == [1.5, 2.5]
        @test df.c::Vector{String} == ["x", "y"]
        @test df.d::Vector{Bool} == [true, false]
    end

    @testset "missing values" begin
        df = readcsv(DF, "a,b\n,x\n2,\n")
        @test isequal(df.a::Vector{Union{Missing,Int64}}, [missing, 2])
        @test isequal(df.b::Vector{Union{Missing,String}}, ["x", missing])
    end

    @testset "integers widen to floats" begin
        @test readcsv(DF, "a\n1\n2.5\n").a::Vector{Float64} == [1.0, 2.5]
        @test isequal(readcsv(DF, "a,b\n1,x\n2.5,y\n,z\n").a::Vector{Union{Missing,Float64}}, [1.0, 2.5, missing])
        @test readcsv(DF, "a\n99999999999999999999\n").a::Vector{Float64} == [1.0e20]
    end

    @testset "layout" begin
        @test readcsv(DF, "a,b\r\n1,2\r\n").b::Vector{Int64} == [2]
        @test readcsv(DF, "\xef\xbb\xbfa\n1\n").a == [1]
        @test readcsv(DF, "a\n1").a == [1]
        @test readcsv(DF, "a\n1\n\n2\n").a == [1, 2]
        @test readcsv(DF, "a;b\n1;2\n"; delim = ';').b == [2]
        @test nrow(readcsv(DF, "a,b\n")) == 0
        @test names(readcsv(DF, "a,a,\n1,2,3\n")) == ["a", "a_1", "Column3"]
        @test readcsv(DF, Vector{UInt8}("a\n1\n")).a == [1]
    end

    @testset "quotes" begin
        df = readcsv(DF, "a,\"b,c\"\n\"x,y\",\"line\nbreak\"\n\"say \"\"hi\"\"\",\"\"\"\"\n")
        @test names(df) == ["a", "b,c"]
        @test df.a == ["x,y", "say \"hi\""]
        @test df[!, "b,c"] == ["line\nbreak", "\""]
        @test readcsv(DF, "a\n\"1\"\n").a::Vector{Int64} == [1]
        @test isequal(readcsv(DF, "a,b\n\"\",\n\"x\",1\n").b, [missing, 1])
        @test readcsv(DF, "a,b\n\"\",\n\"x\",1\n").a::Vector{String} == ["", "x"]
    end

    @testset "strings keyword" begin
        df = readcsv(DF, "zip,n\n01234,1\n,2\n"; strings = [:zip])
        @test isequal(df.zip::Vector{Union{Missing,String}}, ["01234", missing])
        @test df.n::Vector{Int64} == [1, 2]
    end

    @testset "errors" begin
        @test_throws "readcsv: column :a mixes numbers or booleans with text: row 2 has \"x\"" readcsv(DF, "a\n1\nx\n")
        @test_throws "readcsv: column :a mixes numbers or booleans with text: row 1 has \"x\"" readcsv(DF, "a\nx\n1\n")
        @test_throws "readcsv: column :a mixes numbers and booleans: row 2 has \"true\"" readcsv(DF, "a\n1\ntrue\n")
        @test_throws "readcsv: row 2 has 1 fields, expected 2" readcsv(DF, "a,b\n1,2\n3\n")
        @test_throws "readcsv: row 1 has 3 fields, expected 2" readcsv(DF, "a,b\n1,2,3\n")
        @test_throws "readcsv: quote opened at byte 3 is not closed" readcsv(DF, "a\n\"x\n")
        @test_throws "readcsv: unexpected text after the quote closed at byte 5" readcsv(DF, "a\n\"x\"y\n")
        @test_throws "readcsv: delim must be a single-byte character other than a quote or line break" readcsv(DF, "a\n"; delim = 'ä')
        @test_throws "readcsv: the input has no header row" readcsv(DF, "")
        @test_throws "readcsv: strings names column :b, which is not in the input" readcsv(DF, "a\n1\n"; strings = [:b])

        strict = frametype(String, Int64)
        @test_throws "readcsv: column :a would have element type Float64" readcsv(strict, "a\n1.5\n")
        @test_throws "readcsv: column :a would have element type Union{Missing, Int64}" readcsv(strict, "a,b\n1,x\n,y\n")
    end

    @testset "agreement with CSV.jl" begin
        @testset "$text" for text in (
                "a,b\n1,x\n2,y\n",
                "a\n1\n2.5\n",
                "a,b\n,1\n,2\n",
                "a,b\n\"\",1\n\"x\",2\n",
                "a\n 1\n 2\n",
                "a\ntrue\nfalse\n",
                "a\nTrue\nFalse\n",
                "a\n1e3\n-2.5E-1\n",
                "a\n007\n+5\n",
                "a\n0x10\n0x11\n",
                "a\nNaN\nInf\n",
                "a,a\n1,2\n",
                ",\n1,2\n",
                "a\r\n1\r\n",
                "a\r1\r2\r",
            )
            @test agrees_with_csvjl(text)
        end
    end

    @testset "property: agreement with CSV.jl" begin
        cells = (
            ["1", "-2", "0", "007", "12345", ""],
            ["1.5", "-2.25", "3", "1e3", "0.1", ""],
            ["true", "false", ""],
            ["x", "a b", "\"\"", "\"q,r\"", "\"s\"\"t\"", "\"l\nm\"", "ä", ""],
        )

        @check db = false max_examples = 400 function same_as_csvjl(
                ncols = Data.Integers(1, 4),
                nrows = Data.Integers(1, 6),
                picks = Data.Vectors(Data.Integers(1, 1000); min_size = 28, max_size = 28),
            )
            kinds = [cells[mod1(picks[c], 4)] for c in 1:ncols]
            pick(c, r) = kinds[c][mod1(picks[4 + (c - 1) * 6 + r], length(kinds[c]))]
            lines = [join((pick(c, r) for c in 1:ncols), ',') for r in 1:nrows]
            blank_free = ncols > 1 || !any(isempty, lines)
            assume!(blank_free)
            text = string(join(("c$c" for c in 1:ncols), ','), '\n', join(lines, '\n'), '\n')
            agrees_with_csvjl(text)
        end
    end
end
