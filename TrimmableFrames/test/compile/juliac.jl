using Test

const PROGRAM = joinpath(@__DIR__, "juliac_program.jl")
const JULIA = Base.julia_cmd()

@testset "juliac --trim=safe" begin
    build = mktempdir()
    @test success(pipeline(
        `$JULIA --project=$(@__DIR__) -m JuliaC --output-exe trimmed --bundle $build --trim=safe --project=$(@__DIR__) $PROGRAM`;
        stdout = stdout, stderr = stderr,
    ))

    executable = joinpath(build, "bin", "trimmed")
    @test isfile(executable)

    native = read(`$JULIA --project=$(@__DIR__) $PROGRAM`, String)
    @test read(`$executable`, String) == native

    too_many = joinpath(@__DIR__, "juliac_too_many_branches.jl")
    log = tempname()
    rejected = run(pipeline(
        ignorestatus(`$JULIA --project=$(@__DIR__) -m JuliaC --output-exe rejected --bundle $(mktempdir()) --trim=safe --project=$(@__DIR__) $too_many`);
        stdout = log, stderr = log,
    ))
    @test !success(rejected)
    @test occursin("too_many_branches", read(log, String))
end
