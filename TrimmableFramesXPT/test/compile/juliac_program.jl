include("Programs.jl")

report(f::F) where {F} = println(Core.stdout, "RESULT ", f())

@generated function run_entries(entries::Tuple)
    calls = [:(report(entries[$i])) for i in 1:fieldcount(entries)]
    return Expr(:block, calls..., :(return nothing))
end

function (@main)(::Vector{String})::Cint
    run_entries(Programs.ENTRY_POINTS)
    return 0
end
