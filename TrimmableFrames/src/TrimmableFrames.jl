module TrimmableFrames

export Frame, GroupedFrame, frametype, columnunion, ColumnTypeError, expected_types
export ncol, nrow, proprow
export All, AsTable, Between, ByRow, Cols, Not
export antijoin, crossjoin, innerjoin, leftjoin, outerjoin, rightjoin, semijoin
export combine, groupby, groupcols, groupindices, insertcols, insertcols!, rename, rename!
export select, select!, subset, subset!, transform, transform!
export colmetadata, colmetadata!, colmetadatakeys, deletecolmetadata!, deletemetadata!
export emptycolmetadata!, emptymetadata!, metadata, metadata!, metadatakeys

public fitcolumn

using Dates: Dates, Date, DateTime, Time, hour, millisecond, minute, second, yearmonthday

include("columns.jl")
include("frame.jl")
include("celltext.jl")
include("selectors.jl")
include("groupedframe.jl")
include("output.jl")
include("operations.jl")
include("verbs.jl")
include("vcat.jl")
include("join.jl")
include("metadata.jl")

end
