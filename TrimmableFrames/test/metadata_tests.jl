for side in (DFSide, TFSide)
    Core.eval(side, quote
        function annotated()
            df = DataFrame(id = [1, 2, 2, 3], k = ["a", "a", "b", "b"], x = [1.0, 2.0, 3.0, 4.0], y = [1, 2, 3, 4])
            metadata!(df, "study", "s1"; style = :note)
            metadata!(df, "version", 2; style = :note)
            colmetadata!(df, :id, "label", "Identifier"; style = :note)
            colmetadata!(df, :id, "length", 8; style = :note)
            colmetadata!(df, :k, "label", "Group"; style = :note)
            colmetadata!(df, :x, "label", "Weight"; style = :note)
            colmetadata!(df, :x, "scale", 1.5; style = :note)
            return df
        end

        function other()
            df = DataFrame(id = [2, 3, 4], z = [true, false, true])
            metadata!(df, "study", "s1"; style = :note)
            metadata!(df, "version", 3; style = :note)
            colmetadata!(df, :id, "label", "Identifier"; style = :note)
            colmetadata!(df, :id, "length", 9; style = :note)
            colmetadata!(df, :z, "label", "Flag"; style = :note)
            return df
        end

        function third()
            df = DataFrame(id = [2], w = [1.5])
            metadata!(df, "study", "s1"; style = :note)
            colmetadata!(df, :id, "label", "Identifier"; style = :note)
            return df
        end

        unmarked() = DataFrame(id = [9], k = ["c"], x = [0.5], y = [7])

        function column_entries(df)
            entries = []
            for name in names(df)
                for key in sort(collect(colmetadatakeys(df, name)))
                    push!(entries, (name, key, colmetadata(df, name, key)))
                end
            end
            return entries
        end

        table_entries(df) = [(key, metadata(df, key)) for key in sort(collect(metadatakeys(df)))]
    end)
end

metadata_outcome(side::Module, ex) = try
    result = Core.eval(side, ex)
    (canonical(result), side.table_entries(result), side.column_entries(result))
catch e
    e isa LoadError && rethrow()
    (:error, typeof(e))
end

macro samemetadata(ex)
    quoted = QuoteNode(ex)
    return quote
        theirs = metadata_outcome(DFSide, $quoted)
        @test first(theirs) !== :error
        @test isequal(theirs, metadata_outcome(TFSide, $quoted))
    end
end

@testset "metadata" begin
    @testset "reading and writing" begin
        df = TFSide.annotated()
        @test metadata(df, "study") == "s1"
        @test metadata(df, "version") == 2
        @test metadata(df, "absent", "fallback") == "fallback"
        @test metadatakeys(df) == ["study", "version"]
        @test colmetadata(df, :id, "length") == 8
        @test colmetadata(df, "x", "scale") == 1.5
        @test colmetadata(df, 1, "label") == "Identifier"
        @test colmetadata(df, :y, "label", "none") == "none"
        @test colmetadatakeys(df, :id) == ["label", "length"]
        @test colmetadatakeys(df, :y) == String[]
        @test colmetadatakeys(df) == [:id => ["label", "length"], :k => ["label"], :x => ["label", "scale"]]

        deletemetadata!(df, "study")
        deletecolmetadata!(df, :id, "label")
        @test metadatakeys(df) == ["version"]
        @test colmetadatakeys(df, :id) == ["length"]

        emptycolmetadata!(df, :id)
        @test colmetadatakeys(df, :id) == String[]
        emptycolmetadata!(df)
        emptymetadata!(df)
        @test colmetadatakeys(df) == Pair{Symbol,Vector{String}}[]
        @test metadatakeys(df) == String[]
    end

    @testset "a concrete type for a single allowed type" begin
        Labelled = frametype(Int64)
        df = Labelled(a = [1])
        colmetadata!(df, :a, "label", "A")
        read_label(df) = colmetadata(df, :a, "label")
        @test only(Base.return_types(read_label, (Labelled,))) === String
    end

    @testset "errors" begin
        Labelled = frametype(Int64)
        df = Labelled(a = [1])
        @test_throws "colmetadata!: key \"n\" of column :a has a value of type Int64, not among the allowed metadata types (String)" colmetadata!(df, :a, "n", 1)
        @test_throws "metadata!: key \"n\" has a value of type Float64, not among the allowed metadata types (String)" metadata!(df, "n", 1.5)
        @test_throws "metadata!: only style=:note is supported, got :default" metadata!(df, "n", "v"; style = :default)
        @test_throws "colmetadata!: only style=:note is supported, got :other" colmetadata!(df, :a, "n", "v"; style = :other)
        @test_throws "no metadata found for key \"n\"" metadata(df, "n")
        @test_throws "no metadata found for key \"n\" of column :a" colmetadata(df, :a, "n")
        @test_throws "column name :b not found" colmetadata!(df, :b, "n", "v")
        @test_throws "metadata types must be concrete, got AbstractString" frametype(Int64; metadata = AbstractString)
    end

    @testset "an empty frame of metadata does not change the result of a verb" begin
        Allowed = frametype(Int64; metadata = (String, Int64))
        @test Allowed === Frame{Vector{Int64},Union{Int64,String}}
        @test metadatakeys(select(Allowed(a = [1]), :a)) == String[]
    end

    @testset "copies are independent" begin
        df = TFSide.annotated()
        copied = copy(df)
        colmetadata!(copied, :id, "label", "Changed")
        metadata!(copied, "study", "s2")
        @test colmetadata(df, :id, "label") == "Identifier"
        @test metadata(df, "study") == "s1"
    end

    @testset "same as DataFrames" begin
        @testset "no change to columns" begin
            @samemetadata annotated()
            @samemetadata copy(annotated())
            @samemetadata DataFrame(annotated())
            @samemetadata first(annotated(), 2)
            @samemetadata last(annotated(), 2)
            @samemetadata annotated()[[1, 3], :]
            @samemetadata annotated()[:, [:id, :x]]
            @samemetadata annotated()[!, [:x, :id]]
            @samemetadata annotated()[1:2, [:x]]
        end

        @testset "changing columns in place" begin
            @samemetadata (df = annotated(); df.x = [5.0, 6.0, 7.0, 8.0]; df)
            @samemetadata (df = annotated(); df[!, :x] = [1, 2, 3, 4]; df)
            @samemetadata (df = annotated(); df.new = [1, 2, 3, 4]; df)
            @samemetadata insertcols!(annotated(), :new => 1)
            @samemetadata insertcols(annotated(), 1, :new => 1)
            @samemetadata rename(annotated(), :x => :weight)
            @samemetadata rename(annotated(), :x => :y, :y => :x)
            @samemetadata rename!(annotated(), [:a, :b, :c, :d])
            @samemetadata rename(uppercase, annotated())
        end

        @testset "select, transform and combine" begin
            @samemetadata select(annotated(), :x, :id)
            @samemetadata select(annotated(), Not(:x))
            @samemetadata select(annotated(), :)
            @samemetadata select(annotated(), :x => :weight)
            @samemetadata select(annotated(), [:x, :id] .=> [:weight, :key])
            @samemetadata select(annotated(), :x => identity => :weight)
            @samemetadata select(annotated(), :x => copy => :weight)
            @samemetadata select(annotated(), :x => ByRow(identity) => :weight)
            @samemetadata select(annotated(), :x => ByRow(sqrt) => :weight)
            @samemetadata select(annotated(), :x => ByRow(sqrt) => :x)
            @samemetadata select(annotated(), :x => ByRow(sqrt))
            @samemetadata select(annotated(), :x => ByRow(sqrt); renamecols = false)
            @samemetadata select(annotated(), [:x] => sum => :x)
            @samemetadata select(annotated(), :y => sum => :x)
            @samemetadata select(annotated(), [:x, :y] => ByRow(+) => :x)
            @samemetadata select(annotated(), :x => (v -> (a = v, b = v)) => AsTable)
            @samemetadata select(annotated(), :x => (v -> [(x = t,) for t in v]) => AsTable)
            @samemetadata transform(annotated(), :x => ByRow(sqrt) => :x)
            @samemetadata transform(annotated(), :x => ByRow(sqrt) => :root)
            @samemetadata transform(annotated(), :y => ByRow(float) => :x)
            @samemetadata transform(annotated(), :x => identity => :y)
            @samemetadata select!(annotated(), :x, :id)
            @samemetadata transform!(annotated(), :y => ByRow(float) => :x)
            @samemetadata combine(annotated(), :x => sum => :x)
            @samemetadata combine(annotated(), :x => sum)
            @samemetadata combine(annotated(), :id, :x => sum => :total)
            @samemetadata combine(annotated(), nrow)
            @samemetadata select(sdf -> (x = sdf.x,), annotated())
        end

        @testset "subset" begin
            @samemetadata subset(annotated(), :x => ByRow(>(1.5)))
            @samemetadata subset!(annotated(), :x => ByRow(>(1.5)))
            @samemetadata subset(groupby(annotated(), :k), :x => (v -> v .> minimum(v)))
        end

        @testset "groups" begin
            @samemetadata groupby(annotated(), :k)[1]
            @samemetadata parent(groupby(annotated(), :k))
            @samemetadata combine(groupby(annotated(), :k), :x => sum => :total)
            @samemetadata combine(groupby(annotated(), :k), :x => sum => :x)
            @samemetadata combine(groupby(annotated(), :k), :x => sum => :total; keepkeys = false)
            @samemetadata combine(groupby(annotated(), :k), :id, nrow)
            @samemetadata combine(groupby(annotated(), :k), :k => first => :k)
            @samemetadata combine(groupby(annotated(), :k), sdf -> (total = sum(sdf.x),))
            @samemetadata select(groupby(annotated(), :k), :x)
            @samemetadata transform(groupby(annotated(), :k), :x => cumsum => :x)
            @samemetadata transform(groupby(annotated(), :k), :x => cumsum => :running)
            @samemetadata select!(groupby(annotated(), :k), :x)
            @samemetadata transform!(groupby(annotated(), :k), :x => cumsum => :x)
        end

        @testset "vcat" begin
            @samemetadata vcat(annotated(), annotated())
            @samemetadata vcat(annotated(), unmarked())
            @samemetadata vcat(annotated(), select(annotated(), :id); cols = :union)
            @samemetadata vcat(annotated(), select(annotated(), :id); cols = :intersect)
            @samemetadata vcat(annotated(), annotated(); source = :from)
            @samemetadata reduce(vcat, [annotated(), annotated()])
            @samemetadata vcat(annotated(), rename(annotated(), :x => :z); cols = :union)
            @samemetadata (a = annotated(); colmetadata!(a, :x, "label", "Other"; style = :note); vcat(a, annotated()))
            @samemetadata (a = annotated(); metadata!(a, "version", 7; style = :note); vcat(a, annotated()))
            @samemetadata vcat(annotated(), DataFrame())
            @samemetadata vcat(DataFrame(), annotated())
        end

        @testset "joins" begin
            for verb in (:innerjoin, :leftjoin, :rightjoin, :outerjoin, :semijoin, :antijoin)
                @eval @samemetadata $verb(annotated(), other(); on = :id, matchmissing = :equal)
                @eval @samemetadata $verb(other(), annotated(); on = :id, matchmissing = :equal)
            end
            @samemetadata innerjoin(annotated(), other(); on = :id, renamecols = "_l" => "_r")
            @samemetadata leftjoin(annotated(), other(); on = :id, renamecols = "_l" => "_r")
            @samemetadata innerjoin(annotated(), rename(other(), :id => :key); on = :id => :key)
            @samemetadata rightjoin(annotated(), rename(other(), :id => :key); on = :id => :key)
            @samemetadata outerjoin(annotated(), other(); on = :id, source = :from)
            @samemetadata innerjoin(annotated(), other(), third(); on = :id)
            @samemetadata outerjoin(annotated(), other(), third(); on = :id)
            @samemetadata crossjoin(select(annotated(), :x), select(other(), :z))
            @samemetadata crossjoin(select(annotated(), :id), select(other(), :id); makeunique = true)
            @samemetadata crossjoin(select(annotated(), :x), select(other(), :z), select(third(), :w))
        end
    end
end
