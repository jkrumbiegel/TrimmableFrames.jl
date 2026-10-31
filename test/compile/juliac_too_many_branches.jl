using TrimmableFrames

include("Programs.jl")

function (@main)(::Vector{String})::Cint
    println(Core.stdout, Programs.p_too_many_branches())
    return 0
end
