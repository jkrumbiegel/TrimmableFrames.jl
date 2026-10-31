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
end
