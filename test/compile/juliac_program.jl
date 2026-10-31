using TrimmableFrames

include("Programs.jl")

report(result) = println(Core.stdout, "RESULT ", result)

call_all(f::F, ::Tuple{}, ::Val{true}) where {F} = report(f())
call_all(f::F, ::Tuple{}, ::Val{false}) where {F} = nothing
function call_all(f::F, args::Tuple, ::Val) where {F}
    report(f(first(args)))
    return call_all(f, Base.tail(args), Val(false))
end

# Base.tail of a tuple this long is rejected by the verifier.
@generated function run_entries(entries::Tuple)
    calls = [:(call_all(entries[$i][1], entries[$i][2], Val(true))) for i in 1:fieldcount(entries)]
    return Expr(:block, calls..., :(return nothing))
end

function (@main)(::Vector{String})::Cint
    run_entries(Programs.ENTRY_POINTS)
    return 0
end
