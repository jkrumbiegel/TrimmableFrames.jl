using Test
using TrimmableFrames
using TrimmableFramesXPT
using Supposition
import DataFrames
import MappedArrays
import ReadStatTables

include("builder.jl")
using .XPTBuilder: Tagged, file, member, number, text

const DF = frametype(String, Float64; allowmissing = true, metadata = (String, Int64))
const SAMPLE_DIR = joinpath(pkgdir(ReadStatTables), "data")

reference(path) = ReadStatTables.readstat(path; apply_value_labels = false, inlinestring_width = 0, pool_width = typemax(Int))

stored_numbers(column::ReadStatTables.HMSCol) = column.a
stored_numbers(column::MappedArrays.AbstractMappedArray) = parent(column)
stored_numbers(column) = column

reference_column(table, name) =
    [x isa AbstractString ? String(x) : x === missing ? missing : Float64(x) for x in stored_numbers(getproperty(table, Symbol(name)))]

without_final_period(format::AbstractString) = chopsuffix(format, ".")

function write_version(path, table, version)
    ReadStatTables.metadata!(table, "file_format_version", version)
    return ReadStatTables.writestat(path, table)
end

function agrees_with_readstat(path)
    ours = readxpt(DF, read(path))
    theirs = reference(path)
    string.(propertynames(theirs)) == names(ours) || return false
    for name in names(ours)
        isequal(ours[!, name], reference_column(theirs, name)) || return false
        colmetadata(ours, name, "label") == ReadStatTables.colmetadata(theirs, Symbol(name), "label") || return false
        without_final_period(colmetadata(ours, name, "format")) == without_final_period(ReadStatTables.colmetadata(theirs, Symbol(name), "format")) || return false
        colmetadata(ours, name, "storage_width") == Int(ReadStatTables.colmetadata(theirs, Symbol(name), "storage_width")) || return false
        colmetadata(ours, name, "display_width") == Int(ReadStatTables.colmetadata(theirs, Symbol(name), "display_width")) || return false
    end
    return metadata(ours, "file_label") == ReadStatTables.metadata(theirs, "file_label") &&
        metadata(ours, "table_name") == ReadStatTables.metadata(theirs, "table_name") &&
        metadata(ours, "file_format_version") == ReadStatTables.metadata(theirs, "file_format_version")
end

@testset "TrimmableFramesXPT" begin
    @testset "columns" begin
        variables = [number("A"), text("B", 6), number("C", storage_width = 4)]
        rows = [(1.0, "ab", 0.5), (-118.625, "", 16.0), (1.0e10, "ä", 3.0)]
        df = readxpt(DF, file(variables, rows))

        @test names(df) == ["A", "B", "C"]
        @test df.A::Vector{Float64} == [1.0, -118.625, 1.0e10]
        @test df.B::Vector{String} == ["ab", "", "ä"]
        @test df.C::Vector{Float64} == [0.5, 16.0, 3.0]
    end

    @testset "missing numbers" begin
        rows = [(1.0,), (missing,), (Tagged(UInt8('_')),), (Tagged(UInt8('A')),), (Tagged(UInt8('Z')),)]
        df = readxpt(DF, file([number("A")], rows))
        @test isequal(df.A::Vector{Union{Missing,Float64}}, [1.0, missing, missing, missing, missing])
    end

    @testset "zero" begin
        @test readxpt(DF, file([number("A")], [(0.0,), (1.0,)])).A == [0.0, 1.0]
    end

    @testset "no rows" begin
        df = readxpt(DF, file([number("A"), text("B", 2)], []))
        @test names(df) == ["A", "B"]
        @test nrow(df) == 0
    end

    @testset "short variable descriptors" begin
        variables = [number("A"), text("B", 2)]
        df = readxpt(DF, file(variables, [(1.0, "x")]; descriptor_size = 136))
        @test df.A == [1.0]
        @test df.B == ["x"]
    end

    @testset "padding of the last record" begin
        @test nrow(readxpt(DF, file([number("A")], [(1.0,)]))) == 1
        @test nrow(readxpt(DF, file([text("A", 8)], [("x",), ("y",), ("z",)]))) == 3
        @test nrow(readxpt(DF, file([text("A", 80)], [("x",)]))) == 1
        @test readxpt(DF, file([text("A", 8)], [("x",), ("",), ("z",)])).A == ["x", "", "z"]
    end

    @testset "metadata" begin
        variables = [number("A"; label = "Age", format = "BEST", display_width = 12, decimals = 3), text("B", 6; label = "Name")]
        df = readxpt(DF, file(variables, [(1.0, "x")]; table_name = "DM", file_label = "Demographics"))

        @test metadata(df, "table_name") == "DM"
        @test metadata(df, "file_label") == "Demographics"
        @test metadata(df, "file_format_version") == 5
        @test metadata(df, "creation_time") == "01JAN20:00:00:00"
        @test metadata(df, "modified_time") == "01JAN20:00:00:00"
        @test colmetadata(df, :A, "label") == "Age"
        @test colmetadata(df, :A, "format") == "BEST12.3"
        @test colmetadata(df, :A, "display_width") == 12
        @test colmetadata(df, :A, "decimals") == 3
        @test colmetadata(df, :A, "storage_width") == 8
        @test colmetadata(df, :B, "label") == "Name"
        @test colmetadata(df, :B, "format") == ""
        @test colmetadata(df, :B, "storage_width") == 6
    end

    @testset "metadata types" begin
        Labels = frametype(Float64)
        df = readxpt(Labels, file([number("A"; label = "Age")], [(1.0,)]))
        @test colmetadata(df, :A, "label") == "Age"
        @test colmetadatakeys(df, :A) == ["format", "label"]
        @test metadatakeys(df) == ["creation_time", "file_label", "modified_time", "table_name"]

        Numbers = frametype(Float64; metadata = Int64)
        @test_throws "readxpt: metadata needs String among the allowed metadata types" readxpt(Numbers, file([number("A")], [(1.0,)]))
    end

    @testset "metadata follows verbs" begin
        df = readxpt(DF, file([number("A"; label = "Age"), text("B", 2)], [(1.0, "x"), (2.0, "x")]))
        grouped = combine(groupby(df, :B), :A => sum => :A)
        @test colmetadata(grouped, :A, "label") == "Age"
    end

    @testset "errors" begin
        one_column = file([number("A")], [(1.0,)])
        @test_throws "readxpt: this is not a SAS transport file" readxpt(DF, Vector{UInt8}("a,b\n1,2\n"))
        @test_throws "readxpt: this is not a SAS transport file" readxpt(DF, UInt8[])
        @test_throws "readxpt: expected a DSCRPTR header at byte 321" readxpt(DF, [one_column[1:320]; fill(UInt8(' '), 80)])
        @test_throws "readxpt: the input ends inside" readxpt(DF, one_column[1:500])
        @test_throws "readxpt: the file has more than one data set, which is not supported" readxpt(DF, [one_column; member([number("B")], [(2.0,)])])
        @test_throws "readxpt: column :A has numeric width 1, expected 2 to 8" readxpt(DF, file([number("A"; storage_width = 1)], []))

        strict = frametype(Float64)
        @test_throws "readxpt: column :A would have element type Union{Missing, Float64}" readxpt(strict, file([number("A")], [(missing,)]))
        @test_throws "readxpt: column :B would have element type String" readxpt(strict, file([text("B", 2)], [("x",)]))
    end

    @testset "same as ReadStatTables" begin
        @testset "$name" for name in ("sample.xpt", "datetime13.xpt")
            @test agrees_with_readstat(joinpath(SAMPLE_DIR, name))
        end

        @testset "long names and labels of version 8" begin
            frame = DataFrames.DataFrame(a_name_longer_than_eight = [1.0, 2.0], text_column_with_a_long_name = ["x", "y"])
            path = tempname() * ".xpt"
            table = ReadStatTables.writestat(path, frame)
            long_label = repeat("long label ", 8)
            ReadStatTables.colmetadata!(table, :a_name_longer_than_eight, "label", long_label)
            write_version(path, table, 8)

            df = readxpt(DF, read(path))
            @test metadata(df, "file_format_version") == 8
            @test names(df) == ["a_name_longer_than_eight", "text_column_with_a_long_name"]
            @test colmetadata(df, 1, "label") == rstrip(long_label)
            @test agrees_with_readstat(path)
            rm(path)
        end

        @testset "long formats of version 9" begin
            path = tempname() * ".xpt"
            table = ReadStatTables.writestat(path, DataFrames.DataFrame(A = [1.0, 2.0], B = [3.0, 4.0]))
            ReadStatTables.colmetadata!(table, :B, "format", "AVERYLONGFORMAT12.3")
            write_version(path, table, 8)

            @test occursin("LABELV9", String(read(path)))
            df = readxpt(DF, read(path))
            @test colmetadata(df, :B, "format") == "AVERYLONGFORMAT12.3"
            @test df.B == [3.0, 4.0]
            @test agrees_with_readstat(path)
            rm(path)
        end

        @check db = false max_examples = 200 function written_by_readstat(
                numbers = Data.Vectors(Data.Floats{Float64}(; nans = false, infs = false); min_size = 1, max_size = 12),
                texts = Data.Vectors(Data.SampledFrom(["", "a", "two words", "ä", "trailing "]); min_size = 1, max_size = 12),
                gaps = Data.Vectors(Data.Booleans(); min_size = 12, max_size = 12),
                version = Data.SampledFrom([5, 8]),
            )
            n = min(length(numbers), length(texts))
            representable(x) = iszero(x) || 1.0e-75 < abs(x) < 1.0e75
            values = Union{Missing,Float64}[gaps[i] || !representable(numbers[i]) ? missing : numbers[i] for i in 1:n]
            frame = DataFrames.DataFrame(NUM = values, TXT = texts[1:n])
            path = tempname() * ".xpt"
            write_version(path, ReadStatTables.writestat(path, frame), version)
            agreed = agrees_with_readstat(path) && metadata(readxpt(DF, read(path)), "file_format_version") == version
            rm(path)
            agreed
        end
    end
end
