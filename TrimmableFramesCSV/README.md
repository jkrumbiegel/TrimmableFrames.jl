# TrimmableFramesCSV.jl

Reads CSV text into a [TrimmableFrames](../TrimmableFrames/README.md) frame. Column names and
types are found at run time, and the reader compiles with `juliac --trim=safe` and with
[WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

```julia
using TrimmableFrames, TrimmableFramesCSV

const DF = frametype(String, Int64, Float64, Bool; allowmissing = true)

df = readcsv(DF, read("data.csv", String))
df = readcsv(DF, bytes; delim = ';', strings = [:zip])
```

The input is a `String` or a `Vector{UInt8}`, so the package does no file access itself.

## Column types

The whole column is read before its type is chosen. Tests compare the result with CSV.jl.

- A column gets the narrowest of `Bool`, `Int64`, `Float64` and `String`, with `Missing` added
  if it has an empty field. A quoted empty field `""` is an empty string.
- `Int64` and `Float64` values in one column give `Float64`, as does an integer too large for
  `Int64`.
- `strings = [:zip]` keeps a column as text, for values such as `01234`.

## Supported

Quoted fields, `""` escapes, line breaks in quoted fields, LF, CRLF and CR line ends, a BOM, a
missing last line end, blank lines (skipped), and a one-byte delimiter. Duplicate header names
get a suffix (`a_1`), and empty ones become `Column3`, as in CSV.jl.

## Deviations from CSV.jl

- Text mixed with numbers or booleans, or numbers mixed with booleans, throws an `ArgumentError`
  naming the column and row. CSV.jl gives a `String` column. Use `strings` to get that.
- A row with the wrong number of fields throws an `ArgumentError` naming the row. CSV.jl warns
  and pads or drops fields.
- A type outside the allowed types of the frame throws a `ColumnTypeError`, naming the column.
- There is no delimiter detection, and only an empty field counts as missing.
- A column of only empty fields is the first allowed type with `Missing`, not `Vector{Missing}`.

## Input in WebAssembly

A WasmCodegen module keeps Julia arrays in the WasmGC heap, not in linear memory, so JavaScript
cannot copy bytes into a `Vector{UInt8}` directly. Pass them through an exported function
instead, 8 bytes per call as an `Int64`. `test/compile/Programs.jl` has this as `reset_input`,
`push_word` and `read_input`, and `test/compile/transfer.mjs` is the JavaScript side.

## Tests

`test/runtests.jl` is the native suite, and `test/compile/runtests.jl` needs WasmCodegen.jl
cloned next to this repository.

```
julia --project=test test/runtests.jl
julia --project=test/compile test/compile/runtests.jl
```
