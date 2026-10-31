using WasmCodegen, NodeJS_24_jll, Test
using TrimmableFrames

include("Programs.jl")

const RUNNER = joinpath(@__DIR__, "run.mjs")

capture_native(f, args) = mktemp() do path, io
    redirect_stdout(io) do
        for arg in (isempty(args) ? (nothing,) : args)
            result = arg === nothing ? f() : f(arg)
            println(Core.stdout, "RESULT ", result)
        end
    end
    close(io)
    read(path, String)
end

function run_wasm(name, bytes, args)
    path = joinpath(mktempdir(), string(name, ".wasm"))
    write(path, bytes)
    node = NodeJS_24_jll.node()
    return read(`$node --disable-warning=ExperimentalWarning $RUNNER $(WasmCodegen.JS_HOST) $path $name $(string.(args))`, String)
end

function compile_entry(f, args; verify = :error)
    argtypes = isempty(args) ? () : (Int,)
    return WasmCodegen.compile(f, argtypes; config = WasmCodegen.Config(; verify))
end

function check_entry(f, args)
    name = nameof(f)
    native = capture_native(f, args)
    seconds = @elapsed compiled = compile_entry(f, args)
    wasm = run_wasm(name, compiled.bytes, args)
    println(rpad(name, 28), lpad(length(compiled.bytes), 8), " bytes ", lpad(round(seconds; digits = 1), 6), "s")
    return native, wasm
end

selected() = isempty(ARGS) ? Programs.ENTRY_POINTS : filter(e -> string(nameof(e[1])) in ARGS, Programs.ENTRY_POINTS)

@testset "WasmCodegen" begin
    @testset "$(nameof(f))" for (f, args) in selected()
        native, wasm = check_entry(f, args)
        @test wasm == native
    end
end
