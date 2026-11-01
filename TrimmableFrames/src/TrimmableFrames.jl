module TrimmableFrames

export Frame, GroupedFrame, frametype, columnunion, ColumnTypeError, expected_types
export ncol, nrow, proprow
export All, AsTable, Between, ByRow, Cols, Not
export antijoin, crossjoin, innerjoin, leftjoin, outerjoin, rightjoin, semijoin
export combine, groupby, groupcols, groupindices, insertcols, insertcols!, rename, rename!
export select, select!, subset, subset!, transform, transform!

include("columns.jl")
include("frame.jl")
include("selectors.jl")
include("groupedframe.jl")
include("output.jl")
include("operations.jl")
include("verbs.jl")
include("vcat.jl")
include("join.jl")

end
