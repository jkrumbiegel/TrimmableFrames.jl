# TrimmableFrames.jl

Data frames with the verbs and mini-language of DataFrames.jl that compile with
`juliac --trim=safe` and with [WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

You pick the column types once, at compile time. Column names, column count and which
allowed type each column has remain run-time data.

```julia
using TrimmableFrames

const DataFrame = frametype(String, Int64, Float64, Bool; allowmissing = true)

df = DataFrame(city = ["ber", "ham", "ber"], qty = [1, 2, 3], price = [1.5, missing, 2.5])

gd = groupby(df, :city)
combine(gd, :qty => sum => :total, nrow, :price => (x -> sum(skipmissing(x))))
transform(gd, :qty => cumsum => :running)
subset(df, :qty => ByRow(>(1)))
vcat(df, select(df, :city); cols = :union)
```

`frametype` returns a `Frame{C,M}`, where `C` is the union of the allowed `Vector` types and `M`
the union of allowed metadata types. Each
column operation is an explicit chain of `isa` tests over the members of `C`, generated for
any `C`, with your function called in each branch. Your function therefore gets compiled once
per allowed column type, and no dynamic dispatch remains.

An operation that would leave the allowed types throws a `ColumnTypeError` that names the
operation and the column, also in compiled code:

```
vcat: column :a combines element types Int64 and String into Any, which is not among the
allowed column types (Bool, Float64, Int64, String, ...)
```

## Supported

- Column types: any concrete element type, such as `Date`, `DateTime` and `Time` from Dates.
  Tests compare them with DataFrames in the verbs, `groupby` and joins.
- Construction: `DF(a = 1:3, b = "x")`, `DF(:a => v, "b" => w)`, `DF(pairs_vector)`,
  `DF(namedtuple)`, `DF(cols, names)`, `copycols`. Scalars are recycled.
- Columns: `df.a`, `df[!, :a]`, `df[:, :a]`, `df[rows, cols]`, `df.a = v`, `df[!, :a] = v`,
  `insertcols!`, `insertcols`, `select!(df, Not(:a))` to delete, `select!(df, :c, :)` to move,
  `rename`, `rename!`, `names`, `propertynames`, `nrow`, `ncol`, `size`, `first`, `last`,
  `copy`, `==`, `isequal`, `show`.
- Selectors: `Symbol`, `String`, `Int`, ranges and vectors of those, `:`, `All()`, `Not`,
  `Between`, `Cols`.
- Verbs: `select`, `select!`, `transform`, `transform!`, `combine`, `subset`, `subset!`, on
  frames and on groups, and `vcat` (`cols`, `source`) and `reduce(vcat, frames)`.
- `groupby(df, cols; sort, skipmissing)` with the group order of DataFrames, also for
  `sort=nothing`. `GroupedFrame` has `length`, indexing, iteration, `parent`, `groupcols`,
  `groupindices`.
- Joins: `innerjoin`, `leftjoin`, `rightjoin`, `outerjoin`, `semijoin`, `antijoin`, `crossjoin`
  with `on` (names, `left => right` pairs and vectors of both), `makeunique`, `validate`,
  `renamecols`, `matchmissing`, `order`, `source`, and more than two frames for `innerjoin`,
  `outerjoin` and `crossjoin`.
- Metadata: `metadata`, `metadata!`, `metadatakeys`, `deletemetadata!`, `emptymetadata!` and
  `colmetadata`, `colmetadata!`, `colmetadatakeys`, `deletecolmetadata!`, `emptycolmetadata!`,
  following the `:note` propagation rules of DataFrames through verbs, `vcat` and joins.
- Mini-language: `:a`, `:a => :b`, `:a => f`, `:a => f => :b`, `[:a, :b] => f => :c`,
  `:a => ByRow(f)`, `f => AsTable`, `f => [:x, :y]`, `nrow`, `nrow => :n`, `proprow`,
  `[:a, :b] .=> sum .=> [:x, :y]`, a function of the group (`combine(sdf -> ..., gd)`, also as
  a `do` block), default output names, `renamecols`, `keepkeys`, `copycols`.

## Deviations from DataFrames

Each of these follows from what can be compiled without dynamic dispatch.

- `AsTable` as a source needs its names in the type: `AsTable(Val((:a, :b)))` instead of
  `AsTable([:a, :b])`, which throws an error saying so. A `NamedTuple` with run-time names
  cannot be compiled. `=> AsTable` as a target is unchanged, since a function's return type
  carries the names.
- A vector source, `[:a, :b] => f`, supports at most 3 columns, because its length is only
  known at run time and every length up to the limit has to be compiled. For more, use a
  tuple, `(:a, :b, :c, :d) => f`, which has its length in the type. Larger sources throw an
  error saying so. See "Cost of multi-column sources".
- Exceptions: `ColumnTypeError` is new. Read `msg` of an `ArgumentError` in compiled code as
  `e.msg::String`, since its field is an `AbstractString`.
- A column of only `missing` with no declared type (`[missing]`, or a function returning
  `Vector{Missing}`) becomes a member of the set that allows `Missing`, as `Vector{Missing}`
  is not an allowed type. `vcat` treats such a column as gaps when its declared type cannot
  be promoted with the others.
- No `Vector{Any}` columns. Input of element type `Any` is narrowed to an allowed type or
  rejected, and `vcat` of `Int64` and `String` throws instead of producing `Vector{Any}`.
- With no groups, `f` is not called, while DataFrames calls it on an empty vector and may
  throw (`maximum`).
- `groupby` copies nothing, but `gd[i]` and the argument of a frame function are copies, as
  there are no frame views. `subset(...; view=true)` throws. Column functions still receive
  views of the group's rows, as in DataFrames.
- `sort` of `groupby` takes `true`, `false` or `nothing`, not a `NamedTuple`. `keys(gd)` is
  not implemented: `TrimmableFrames.groupkeys(gd)` returns a frame of the keys.
- `df.x` has the type of the whole column union, so with more than a few allowed types a
  call like `sum(df.x)` does not compile. Narrow it first, with `df.x::Vector{Float64}` or
  `isa`, or use `combine(df, :x => sum)`, which narrows by itself.
- Joins need the same allowed column types in all frames, and each pair of key columns needs
  the same element type apart from `Missing`. Joining `Int64` to `Int64?` works, joining
  `Int64` to `Float64` throws an `ArgumentError`, which DataFrames matches by value. A join
  that needs `missing` in a column without an allowed `?` type throws a `ColumnTypeError`.
- `validate` errors do not list the duplicate keys, and the deprecated `indicator` keyword is
  not supported: use `source`.
- `threads` is accepted and ignored: everything runs on one task. `ungroup` is not
  implemented, because it would make the return type depend on a run-time value.
- `frametype` returns `Frame{C,M}`. Methods that take a frame type name both parameters.
- Regular expressions are not selectors: PCRE is a C library, unavailable under WasmCodegen.
- A list of different functions, `[:a => sum, :b => maximum]`, has a non-concrete element
  type, as `Pair{Symbol,Function}`. It works natively, but the verifier rejects it. Pass the
  pairs as separate arguments, or pick from a tuple of functions at run time.
- Metadata values have the types you allow with `frametype(...; metadata = (String, Int64))`,
  `String` by default. Others throw a `ColumnTypeError`. Reading gives the union of those types,
  so with more than one, narrow it with `::T` or `isa`.
- Only `:note`-style metadata exists, and it is the default style, unlike in DataFrames. Other
  styles throw an `ArgumentError`, and `style=true` is not accepted when reading.
- `metadatakeys` and `colmetadatakeys` return sorted vectors, not key sets.
- Not implemented yet: `leftjoin!`, `sort`, `unique`, `stack`, `dropmissing`, `eachrow`, `Tables.jl`.

## Writing compilable code

The set of allowed types is closed, but `f` is compiled for each of them. So:

- `f` must be trim-safe for every member of the column set its signature accepts, even if no
  such column exists at run time. A method error is fine (`sum` of a `String` column compiles to a
  throw), a dynamic call is not. For instance `sum(skipmissing(x))` is rejected by the juliac
  verifier for every `x::Vector{Union{Missing,T}}`, independently of this package: Base's
  `_mapreduce` for `skipmissing` has its `f::Function` widened and calls `mapreduce_empty`
  with it. Write the loop instead. Plain `:x => sum` and
  `:x => prod` are handled: for text columns they throw the `MethodError` directly.
- A value of a column union has a concrete type only after `splitcolumn`-style narrowing.
  `df.a` in your own code is a `Union` of all allowed vectors: assert it (`df.a::Vector{Int}`),
  or do the work inside a transformation.
- WasmCodegen cannot build a `NamedTuple` from values of a union type ("apply_type of types
  not known at compile time"), so `x -> (low = minimum(x),)` is rejected there when the
  column set has `Missing` variants of the column's type. juliac accepts it.
- A constructor used as a function is compiled for every column too: `ByRow(Date)` on a
  `String` column parses text, which is not trim-safe. Declare
  `TrimmableFrames.expected_types(::ByRow{Type{Date}}, ::Val{1}) = ((DateTime,),)`.
- Columns from run-time data go through `columnunion(DF)[col1, col2]`. A plain
  `[[1, 2], ["x", "y"]]` is a `Vector{Vector}`, whose elements have no concrete type.
- More than 16 verb arguments lose the specialization on plain functions (`nrow`, `:`), which
  natively means a dynamic call. Pairs are not affected.

## Cost of multi-column sources

With `n` allowed column types, a source of `k` columns has `n^k` combinations of types, since
each column's type is a run-time value. That also holds for a tuple source. A vector source
does this for each arity that `f` has, up to 3.

A combination counts as a branch if `f` can run for it, which inference decides. A source may
have at most 30 branches (`MAX_BRANCHES`), and more than that does not compile: the verifier
reports an unresolved call from `too_many_branches`. Natively it still works, by dynamic
dispatch on the combination that occurs.

So annotate functions of several columns with the types you expect:

```julia
(:qty, :flag) => ByRow((a, b) -> 1)                                   # 64 branches, rejected
(:qty, :flag) => ByRow((a::Int64, b::Bool) -> 1)                      # 4 branches
(:qty, :flag) => ((a::AbstractVector{Int64}, b::AbstractVector{Bool}) -> 1)  # 1 branch
```

For your own functions, annotate the element type of a `ByRow` function, or `AbstractVector` for a whole-column one:
a group's column is a `SubArray`, not a `Vector`. An element annotation also matches the
non-missing part of a `Union{Missing,T}` column, and a `Union{Missing,T}` annotation matches
the missing part of every such column. A column that does not fit the annotation gives a
`MethodError` at run time, which does not name the column.

Combinations with no method do not call `f`, but the code around that call is still compiled.
With 8 column types, a 3-column source compiled with WasmCodegen gives 267 KB with element
annotations and 159 KB with whole-column ones (a plain one-column `select` is 120 KB). Without
annotations it was 480 KB, in about 35 s, before this limit existed. `[:a, :b] => ByRow(+)` is
over the limit with 8 column types, unless `+` declares its types:

```julia
TrimmableFrames.expected_types(::ByRow{typeof(+)}, ::Val{2}) =
    ((Float64, Float64), (Int64, Int64))

select(df, [:x, :y] => ByRow(+) => :z)
```

`expected_types(f, Val(N))` lists the combinations of types `f` may run for with `N` sources,
so the call stays as in DataFrames. Dispatch on `ByRow{typeof(f)}` for element types and on
`typeof(f)` for whole columns. Each combination is exact: the declaration above excludes
`(Float64, Int64)`, and the non-missing part of a `Union{Missing,T}` column is matched as `T`.
Other types throw a `ColumnTypeError` at run time, natively as well. A vector source skips the
arities a function does not declare, a tuple source does not. The declaration holds for every
use of `f` in the session and is not applied to `AsTable` sources.

`vcat` has `n^2` type pairs, of which only pairs that promote to an allowed type compile to
copies. The others throw the `ColumnTypeError`.

## Known issues

A trimmed executable can segfault at startup, before any program code runs, in the method
cache lookup of `ijl_apply_generic`: from the dynamic call of `Base.Sys.__init__`, or from
`jl_finish_task` on another thread. The build succeeds and each executable behaves the same on
every run, but small source changes turn the crash on or off. Unrelated padding functions in
`src/` did so for `p_vcat` compiled alone, the integer path of `groupby` turned it off for the
full test program, joins turned it on again, and metadata off. In the current state the full
test program of this package and of TrimmableFramesXPT run, and the one of TrimmableFramesCSV
crashes this way. A passing build therefore says nothing about the next change. `JULIA_NUM_THREADS=1` does not help. The cause is not known. Eight plain Julia
programs without this package did not crash. WasmCodegen output is not affected.

## Tests

`test/runtests.jl` is the native suite. Most tests run the same source text against DataFrames
and TrimmableFrames and compare names, element types and values, and `test/property_tests.jl`
does so on frames generated by [Supposition.jl](https://github.com/Seelengrab/Supposition.jl).

`test/compile/runtests.jl` needs [WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl)
cloned next to this repository. It compiles every verb with WasmCodegen under `verify=:error`,
runs it in Node and compares the output with native Julia, and builds all of them with real
`juliac --trim=safe` through JuliaC.jl.

```
julia --project=test/compile -e 'import Pkg; Pkg.instantiate()'
julia --project=test/compile test/compile/runtests.jl
```
