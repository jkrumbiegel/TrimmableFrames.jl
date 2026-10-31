function sorted_rows(result)
    rows = sort(collect(zip(result[4]...)); by = repr)
    return (result[1], result[2], result[3], rows)
end

macro samerows(ex)
    quoted = QuoteNode(ex)
    return quote
        let dataframes = outcome(DFSide, $quoted), trimmable = outcome(TFSide, $quoted)
            @test first(dataframes) === :frame
            @test first(trimmable) === :frame
            first(dataframes) === first(trimmable) === :frame &&
                @test isequal(sorted_rows(dataframes), sorted_rows(trimmable))
        end
    end
end

macro samefailure(ex)
    quoted = QuoteNode(ex)
    return quote
        @test outcome(DFSide, $quoted) == (:error, ArgumentError)
        @test outcome(TFSide, $quoted) == (:error, ArgumentError)
    end
end

macro samejoin(ex)
    wrapped = Expr(:let, Expr(:block, :(people = $(PEOPLE)), :(jobs = $(JOBS))), ex)
    return esc(:(@samerows $wrapped))
end

macro failedjoin(ex)
    wrapped = Expr(:let, Expr(:block, :(people = $(PEOPLE)), :(jobs = $(JOBS))), ex)
    return esc(:(@samefailure $wrapped))
end

const PEOPLE = :(DataFrame(id = [1, 2, 2, 4], name = ["a", "b", "c", "d"], age = [30, 40, 50, 60]))
const JOBS = :(DataFrame(id = [2, 2, 3, 1], job = ["x", "y", "z", "w"]))

@testset "join kinds" begin
    @samejoin innerjoin(people, jobs; on = :id)
    @samejoin leftjoin(people, jobs; on = :id)
    @samejoin rightjoin(people, jobs; on = :id)
    @samejoin outerjoin(people, jobs; on = :id)
    @samejoin semijoin(people, jobs; on = :id)
    @samejoin antijoin(people, jobs; on = :id)
    @samejoin crossjoin(people, jobs; makeunique = true)
    @same crossjoin(DataFrame(a = [1, 2]), DataFrame(b = ["x", "y", "z"]))
    @same semijoin(DataFrame(k = [3, 1, 2, 1]), DataFrame(k = [1, 2]); on = :k)
    @same antijoin(DataFrame(k = [3, 1, 2, 1]), DataFrame(k = [1, 2]); on = :k)
end

@testset "join column layout" begin
    @samerows innerjoin(DataFrame(a = [1], k = [1], b = [2]), DataFrame(c = [3], k = [1], d = [4]); on = :k)
    @samerows rightjoin(DataFrame(a = [1], k = [1]), DataFrame(c = [3, 4], k = [1, 2]); on = :k)
    @samerows outerjoin(DataFrame(a = [1], k = [1]), DataFrame(c = [3, 4], k = [1, 2]); on = :k)
end

@testset "join keys" begin
    @samejoin innerjoin(people, jobs; on = "id")
    @samejoin innerjoin(people, jobs; on = [:id])
    @samejoin innerjoin(people, rename(jobs, :id => :pid); on = :id => :pid)
    @samejoin rightjoin(people, rename(jobs, :id => :pid); on = :id => :pid)
    @samejoin outerjoin(people, rename(jobs, :id => :pid); on = :id => :pid)
    @samejoin innerjoin(people, rename(jobs, :id => :pid); on = [:id => :pid])

    left = :(DataFrame(a = [1, 1, 2], b = ["x", "y", "x"], v = [1, 2, 3]))
    right = :(DataFrame(a = [1, 2, 2], b = ["y", "x", "z"], w = [4.5, 5.5, 6.5]))
    @eval @samerows innerjoin($left, $right; on = [:a, :b])
    @eval @samerows outerjoin($left, $right; on = [:a, :b])
    @eval @samerows innerjoin($left, $right; on = [:a, :b => :b])
    @eval @samerows innerjoin($left, rename($right, :a => :c); on = [:a => :c, :b])

    @samerows innerjoin(DataFrame(k = ["a", "b"], x = [1, 2]), DataFrame(k = ["b", "c"], y = [3, 4]); on = :k)
    @samerows innerjoin(DataFrame(k = [true, false]), DataFrame(k = [true, true], y = [3, 4]); on = :k)
    @samerows innerjoin(DataFrame(k = [1.5, 2.5]), DataFrame(k = [2.5], y = [3]); on = :k)
    @samerows innerjoin(DataFrame(k = [typemax(Int), typemin(Int)]), DataFrame(k = [typemin(Int)], y = [3]); on = :k)
    @samerows innerjoin(DataFrame(k = Int[]), DataFrame(k = [1], y = [3]); on = :k)
    @samerows outerjoin(DataFrame(k = Int[]), DataFrame(k = [1], y = [3]); on = :k)
    @samerows leftjoin(DataFrame(k = [1]), DataFrame(k = Int[], y = String[]); on = :k)
end

@testset "join invalid arguments" begin
    @failedjoin innerjoin(people, jobs)
    @failedjoin innerjoin(people, jobs; on = :nope)
    @failedjoin innerjoin(people, jobs; on = :id => :nope)
    @failedjoin innerjoin(people, jobs; on = (:id, :id))
    @failedjoin innerjoin(people, jobs; on = [:id, :id])
    @failedjoin innerjoin(people, jobs; on = :id, order = :nope)
    @failedjoin innerjoin(people, jobs; on = :id, matchmissing = :nope)
    @failedjoin innerjoin(people, people; on = :id)
    @failedjoin outerjoin(people, jobs; on = :id, matchmissing = :notequal)
end

@testset "join missing keys" begin
    left = :(DataFrame(k = [1, missing, 2], a = [1, 2, 3]))
    right = :(DataFrame(k = [missing, 1], b = [4, 5]))
    for kind in (:innerjoin, :leftjoin, :rightjoin, :outerjoin, :semijoin, :antijoin)
        call(mode) = :($kind($left, $right; on = :k, matchmissing = $(QuoteNode(mode))))
        @eval @samefailure $(call(:error))
        @eval @samerows $(call(:equal))
        kind === :outerjoin || @eval @samerows $(call(:notequal))
    end

    @eval @samerows innerjoin(DataFrame(k = [1, 2], a = [1, 2]), $right; on = :k, matchmissing = :equal)
    @eval @samerows outerjoin(DataFrame(k = [1, 2], a = [1, 2]), $right; on = :k, matchmissing = :equal)
    @eval @samerows rightjoin(DataFrame(k = [1, 2], a = [1, 2]), $right; on = :k, matchmissing = :equal)
    @samefailure innerjoin(DataFrame(k = [1.0, NaN]), DataFrame(k = [1.0]); on = :k)
    @samefailure innerjoin(DataFrame(k = [1.0, -0.0]), DataFrame(k = [1.0]); on = :k)
end

@testset "join row order" begin
    left = :(DataFrame(k = [3, 1, 2], a = [1, 2, 3]))
    right = :(DataFrame(k = [2, 4, 3], b = [4, 5, 6]))
    for kind in (:innerjoin, :leftjoin, :rightjoin, :outerjoin), order in (:left, :right)
        @eval @same $kind($left, $right; on = :k, order = $(QuoteNode(order)))
        @eval @samerows $kind($left, $right; on = :k, order = $(QuoteNode(order)))
    end
end

@testset "join names" begin
    left = :(DataFrame(k = [1, 2], v = [1, 2], v_1 = [3, 4]))
    right = :(DataFrame(k = [1, 2], v = [5, 6]))
    @eval @samefailure innerjoin($left, $right; on = :k)
    @eval @samerows innerjoin($left, $right; on = :k, makeunique = true)
    @eval @samerows leftjoin($left, $right; on = :k, makeunique = true)
    @eval @samefailure crossjoin($left, $right)
    @eval @samerows crossjoin($left, $right; makeunique = true)
    @eval @samerows innerjoin($left, $right; on = :k, renamecols = "_l" => "_r")
    @eval @samerows outerjoin($left, $right; on = :k, renamecols = :_l => :_r)
    @eval @samerows leftjoin($left, $right; on = :k, renamecols = uppercase => lowercase, makeunique = true)
    @eval @samerows crossjoin($left, $right; renamecols = "_l" => "_r")
end

@testset "join source" begin
    left = :(DataFrame(k = [1, 2], a = [1, 2]))
    right = :(DataFrame(k = [2, 3], b = [3, 4]))
    @eval @samerows outerjoin($left, $right; on = :k, source = :from)
    @eval @samerows leftjoin($left, $right; on = :k, source = "from")
    @eval @samerows rightjoin($left, $right; on = :k, source = :from)
    @eval @samefailure outerjoin($left, $right; on = :k, source = :a)
    @eval @samerows outerjoin($left, $right; on = :k, source = :a, makeunique = true)
end

@testset "join validate" begin
    @failedjoin innerjoin(people, jobs; on = :id, validate = (true, false))
    @failedjoin innerjoin(people, jobs; on = :id, validate = (false, true))
    @failedjoin innerjoin(people, jobs; on = :id, validate = true => true)
    @samerows innerjoin(DataFrame(k = [1, 2]), DataFrame(k = [2, 3]); on = :k, validate = (true, true))
    @samefailure semijoin(DataFrame(k = [1, 1]), DataFrame(k = [1]); on = :k, validate = (true, false))
    @samerows innerjoin(DataFrame(k = [1, missing, missing]), DataFrame(k = [1]); on = :k, matchmissing = :notequal, validate = (true, false))
end

@testset "several frames" begin
    a = :(DataFrame(k = [1, 2, 3], x = [1, 2, 3]))
    b = :(DataFrame(k = [2, 3, 4], y = [4, 5, 6]))
    c = :(DataFrame(k = [3, 4, 5], z = [7, 8, 9]))
    @eval @samerows innerjoin($a, $b, $c; on = :k)
    @eval @samerows outerjoin($a, $b, $c; on = :k)
    @eval @samerows crossjoin($a, $b, $c; makeunique = true)
end

@testset "join outside the allowed types" begin
    Exact = frametype(String, Int64, Float64)
    Keyed = frametype(Int64, Float64; allowmissing = true)
    left = Exact(k = [1, 2], a = [1, 2])
    right = Exact(k = [2, 2], b = [1.5, 2.5])
    partial = Exact(k = [2, 3], b = [1.5, 2.5])

    @test_throws "leftjoin: column :b would have element type Union{Missing, Float64}" leftjoin(left, right; on = :k)
    @test_throws "rightjoin: column :a would have element type Union{Missing, Int64}" rightjoin(left, partial; on = :k)
    @test_throws "outerjoin: column :a would have element type Union{Missing, Int64}" outerjoin(left, partial; on = :k)
    @test_throws "outerjoin: column :from would have element type String" outerjoin(
        Keyed(k = [1]), Keyed(k = [2]); on = :k, source = :from)
    @test leftjoin(right, left; on = :k).a == [2, 2]
    @test leftjoin(right, left; on = :k).a isa Vector{Int64}

    @test_throws "key column :k in the left frame has element type Int64 and :k in the right frame has element type Float64" innerjoin(
        left, Exact(k = [1.0]); on = :k)
    @test_throws "key column :a in the left frame has element type String and :b in the right frame has element type Int64" innerjoin(
        Exact(a = ["x"]), Exact(b = [1]); on = :a => :b)

    Mixed = frametype(Int64, Float64; allowmissing = true)
    key_kinds = innerjoin(Mixed(k = [1, 2]), Mixed(k = Union{Missing,Int64}[2, missing], y = [1, 2]); on = :k, matchmissing = :notequal)
    @test key_kinds.k == [2]
    @test key_kinds.k isa Vector{Int64}
end
