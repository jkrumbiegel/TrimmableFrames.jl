module DFSide
using DataFrames, Dates, Statistics
const DatedFrame = DataFrame
end

module TFSide
using TrimmableFrames, Dates, Statistics
const DataFrame = frametype(String, Int64, Float64, Bool; allowmissing = true, metadata = (String, Int64, Float64))
const DatedFrame = frametype(String, Int64, Float64, Date, DateTime, Time; allowmissing = true)
end

canonical(df::DFSide.DataFrames.AbstractDataFrame) =
    (:frame, names(df), [string(eltype(c)) for c in DFSide.DataFrames.eachcol(df)], [collect(c) for c in DFSide.DataFrames.eachcol(df)])
canonical(df::TrimmableFrames.Frame) =
    (:frame, names(df), [string(eltype(c)) for c in eachcol(df)], [collect(c) for c in eachcol(df)])
canonical(x) = x

function outcome(side::Module, ex)
    try
        return canonical(Core.eval(side, ex))
    catch e
        e isa LoadError && rethrow()
        return (:error, typeof(e))
    end
end

"""
    @same expr

Runs the same source text in a module that uses DataFrames and in one that uses
TrimmableFrames, and asserts that names, eltypes and values agree. A thrown exception
agrees when both sides threw one of the same type.
"""
macro same(ex)
    quoted = QuoteNode(ex)
    return quote
        @test isequal(outcome(DFSide, $quoted), outcome(TFSide, $quoted))
    end
end
