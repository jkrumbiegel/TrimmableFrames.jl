for side in (DFSide, TFSide)
    Core.eval(side, quote
        dated() = DatedFrame(
            d = [Date(2024, 3, 1), Date(2023, 1, 15), Date(2024, 3, 1), Date(2022, 7, 4), Date(2023, 1, 15)],
            e = Union{Missing,Date}[Date(2021, 1, 1), missing, Date(2020, 6, 1), missing, Date(2021, 1, 1)],
            t = [DateTime(2024, 1, 2, 3, 4, 5), DateTime(2020), DateTime(2024, 1, 2, 3, 4, 5), DateTime(2021, 1, 1, 0, 0, 0, 5), DateTime(2020)],
            h = [Time(1, 2, 3), Time(0), Time(23, 59, 59), Time(1, 2, 3), Time(12)],
            k = ["a", "b", "a", "b", "c"],
            x = [1.0, 2.0, 3.0, 4.0, 5.0],
        )

        later() = DatedFrame(d = [Date(2023, 1, 15), Date(2025, 1, 1)], e = Union{Missing,Date}[missing, Date(2021, 1, 1)], y = [10, 20])
    end)
end

TrimmableFrames.expected_types(::ByRow{Type{Date}}, ::Val{1}) = ((DateTime,),)

@testset "dates" begin
    @testset "same as DataFrames" begin
        @testset "columns" begin
            @same dated()
            @same dated()[[2, 4], [:d, :h]]
            @same (df = dated(); df.d2 = df.d; df)
            @same vcat(dated(), dated())
            @same vcat(dated(), later(); cols = :union)
        end

        @testset "verbs" begin
            @same select(dated(), :d => ByRow(year) => :year, :t => ByRow(hour) => :hour, :h => ByRow(minute) => :minute)
            @same select(dated(), :t => ByRow(Date) => :day)
            @same select(dated(), :t => ByRow(Date))
            @same select(dated(), :e => ByRow(v -> ismissing(v) ? missing : month(v)) => :month)
            @same transform(dated(), :d => ByRow(v -> v + Day(30)) => :due)
            @same transform(dated(), [:d, :t] => ByRow((a, b) -> DateTime(a) + Hour(hour(b))) => :merged)
            @same subset(dated(), :d => ByRow(>=(Date(2023, 6, 1))))
            @same subset(dated(), :e => ByRow(==(Date(2021, 1, 1))); skipmissing = true)
            @same combine(dated(), :d => minimum => :first_day, :t => maximum => :last_time, :h => maximum => :latest)
        end

        @testset "groupby" begin
            for sort in (true, false, nothing), key in (:d, :e, :t, :h)
                @eval @same combine(groupby(dated(), $(QuoteNode(key)); sort = $sort), :x => sum => :x)
            end
            @same combine(groupby(dated(), [:d, :k]; sort = true), nrow)
            @same combine(groupby(dated(), :e; skipmissing = true), :x => sum => :x)
            @same combine(groupby(dated(), :k), :d => maximum => :last_day, :h => minimum => :earliest)
            @same transform(groupby(dated(), :d), :x => sum => :total)
        end

        @testset "joins" begin
            for verb in (:innerjoin, :leftjoin, :rightjoin, :outerjoin, :semijoin, :antijoin)
                @eval @same $verb(dated(), later(); on = :d, makeunique = true)
                @eval @same $verb(dated(), later(); on = :e, matchmissing = :equal, makeunique = true)
            end
        end

        @check db = false max_examples = 100 function grouping_random_dates(
                days = Data.Vectors(Data.Integers(-3, 3); min_size = 1, max_size = 12),
                hours = Data.Vectors(Data.Integers(0, 2); min_size = 12, max_size = 12),
            )
            n = length(days)
            dates = [days[i] == 0 ? missing : Date(2024, 1, 10) + Day(days[i]) for i in 1:n]
            stamps = [DateTime(2024) + Hour(hours[i]) for i in 1:n]
            theirs = DFSide.DataFrame(d = Vector{Union{Missing,Date}}(dates), t = stamps)
            ours = TFSide.DatedFrame(d = Vector{Union{Missing,Date}}(dates), t = stamps)
            isequal(
                canonical(DFSide.DataFrames.combine(DFSide.DataFrames.groupby(theirs, [:d, :t]), DFSide.DataFrames.nrow)),
                canonical(combine(groupby(ours, [:d, :t]), nrow)),
            )
        end
    end

    @testset "display" begin
        df = frametype(Date, DateTime, Time; allowmissing = true)(
            d = Union{Missing,Date}[Date(2024, 3, 1), missing],
            t = [DateTime(2024, 1, 2, 3, 4, 5), DateTime(2021, 1, 1, 0, 0, 0, 5)],
            h = [Time(1, 2, 3), Time(0)],
        )
        @test sprint(show, df) == """
            2×3 Frame
             Row │ d           t                        h
                 │ Date?       DateTime                 Time
            ─────┼───────────────────────────────────────────────
               1 │ 2024-03-01  2024-01-02T03:04:05      01:02:03
               2 │ missing     2021-01-01T00:00:00.005  00:00:00"""
    end

    @testset "expected types of a type used as a function" begin
        df = TFSide.dated()
        @test select(df, :t => ByRow(Date) => :day).day == Date.(df.t)
        @test_throws "Date is restricted to Tuple{DateTime}" select(df, :k => ByRow(Date) => :day)
        @test only(Base.return_types(() -> TrimmableFrames.restrict(ByRow(Date), Val(1)), ())) ===
            ByRow{TrimmableFrames.Restricted{Type{Date},Tuple{DateTime}}}
    end

    @testset "errors" begin
        @test_throws "column :d" frametype(Int64)(d = [Date(2024)])
        @test_throws "element type Date, which is not among the allowed column types (Int64)" frametype(Int64)(d = [Date(2024)])
        @test_throws "(Date, Union{Missing, Date})" frametype(Date; allowmissing = true)(d = [1])
        @test_throws "element type Any" frametype(Date)(d = Any[1, "x"])
        df = frametype(Date)(d = [Date(2024)])
        @test_throws "column :e would have element type Int64" select(df, :d => ByRow(year) => :e)
    end
end
