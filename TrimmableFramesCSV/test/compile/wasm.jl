using WasmCodegen, NodeJS_24_jll, Test

include("Programs.jl")

const RUNNER = joinpath(@__DIR__, "..", "..", "..", "TrimmableFrames", "test", "compile", "run.mjs")
const TRANSFER = joinpath(@__DIR__, "transfer.mjs")

function capture_native(f)
    path, io = mktemp()
    redirect_stdout(io) do
        println(Core.stdout, "RESULT ", f())
    end
    close(io)
    return read(path, String)
end

function write_module(name, bytes)
    path = joinpath(mktempdir(), string(name, ".wasm"))
    write(path, bytes)
    return path
end

function run_wasm(f)
    compiled = WasmCodegen.compile(f, (); config = WasmCodegen.Config(; verify = :error))
    println(rpad(nameof(f), 20), lpad(length(compiled.bytes), 8), " bytes")
    path = write_module(nameof(f), compiled.bytes)
    node = NodeJS_24_jll.node()
    return read(`$node --disable-warning=ExperimentalWarning $RUNNER $(WasmCodegen.JS_HOST) $path $(nameof(f))`, String)
end

function run_transfer()
    entries = [
        WasmCodegen.Entry(Programs.reset_input, (Int,)),
        WasmCodegen.Entry(Programs.push_word, (Int64,)),
        WasmCodegen.Entry(Programs.read_input, (Int,)),
    ]
    path = write_module("transfer", WasmCodegen.compile(entries).bytes)
    node = NodeJS_24_jll.node()
    return read(`$node --disable-warning=ExperimentalWarning $TRANSFER $(WasmCodegen.JS_HOST) $path`, String)
end

selected() = isempty(ARGS) ? Programs.ENTRY_POINTS : filter(f -> string(nameof(f)) in ARGS, Programs.ENTRY_POINTS)

WasmCodegen.with_trim_patches() do _, _
    @testset "WasmCodegen" begin
        @testset "$(nameof(f))" for f in selected()
            @test run_wasm(f) == capture_native(f)
        end
        @testset "input from JavaScript" begin
            report = run_transfer()
            print(report)
            @test occursin("rows 100000", report)
        end
    end
end
