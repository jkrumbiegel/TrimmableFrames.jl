# TrimmableFramesXPT.jl

Reads SAS transport files (`.xpt`) into a [TrimmableFrames](../TrimmableFrames/README.md) frame,
with labels and formats as metadata. It is plain Julia with no C library, and compiles with
`juliac --trim=safe` and with [WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

```julia
using TrimmableFrames, TrimmableFramesXPT

const DF = frametype(String, Float64; allowmissing = true, metadata = (String, Int64))

df = readxpt(DF, read("dm.xpt"))

colmetadata(df, :AGE, "label")
metadata(df, "file_label")
```

The input is a `Vector{UInt8}`, so the package does no file access itself. Only reading is
supported. To pass bytes in from JavaScript, see "Input in WebAssembly" in
[TrimmableFramesCSV](../TrimmableFramesCSV/README.md).

## Columns

- Numeric variables become `Float64`, or `Union{Missing,Float64}` if any value is missing.
- Character variables become `String`, without trailing blanks. An empty value is `""`.
- Each column type has to be allowed by `DF`, otherwise a `ColumnTypeError` names the column.

## Metadata

| Level | Key | Type |
|---|---|---|
| Table | `table_name`, `file_label`, `creation_time`, `modified_time` | `String` |
| Table | `file_format_version` | `Int64` |
| Column | `label`, `format` | `String` |
| Column | `storage_width`, `display_width`, `decimals` | `Int64` |

`String` has to be among the allowed metadata types. The `Int64` entries are left out if
`Int64` is not, as with the default `metadata = String`.

## Supported

Versions 5, 8 and 9, including long names and labels, variable descriptors of 136 and 140 bytes
and numeric widths from 2 to 8.

## Deviations from ReadStatTables

- Dates and times stay numbers, with their SAS `format` in the metadata: there is no date column
  type unless you add one. ReadStatTables converts them to `Date` and `DateTime`.
- All kinds of missing numbers (`.`, `._`, `.A` to `.Z`) become `missing`, so which one it was
  is lost.
- `creation_time` and `modified_time` are the text in the file, not `DateTime` values.
- Text is not decoded: bytes are taken as UTF-8. A file in another encoding gives invalid
  strings. There is no `file_encoding` option.
- A file with more than one data set throws an `ArgumentError`.
- `usecols`, `row_limit` and `row_offset` are not supported, and value labels do not exist in
  this format.
- `format` keeps its final period, as in current ReadStat (`BEST12.`). The ReadStat version in
  the released `ReadStat_jll` drops it.

As in ReadStat, a row of only blanks at the very end of a file narrower than 80 bytes per row
cannot be told from padding, so it is dropped unless the file declares its row count.

## Tests

`test/runtests.jl` compares results with ReadStatTables on its sample files and on generated
files of versions 5 and 8 from its writer. `test/compile/runtests.jl` needs WasmCodegen.jl cloned
next to this repository.

```
julia --project=test test/runtests.jl
julia --project=test/compile test/compile/runtests.jl
```
