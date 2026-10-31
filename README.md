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

`frametype` returns a `Frame{C}`, where `C` is the union of the allowed `Vector` types. Each
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
- `threads` is accepted and ignored: everything runs on one task. `ungroup` is not
  implemented, because it would make the return type depend on a run-time value.
- Regular expressions are not selectors: PCRE is a C library, unavailable under WasmCodegen.
- A list of different functions, `[:a => sum, :b => maximum]`, has a non-concrete element
  type, as `Pair{Symbol,Function}`. It works natively, but the verifier rejects it. Pass the
  pairs as separate arguments, or pick from a tuple of functions at run time.
- Not implemented yet: joins, `sort`, `unique`, `stack`, `dropmissing`, `eachrow`, `Tables.jl`.

## Writing compilable code

The set of allowed types is closed, but `f` is compiled for each of them. So:

- `f` must be trim-safe for every member of the column set it can reach, even if no such
  column exists at run time. A method error is fine (`sum` of a `String` column compiles to a
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
- Columns from run-time data go through `columnunion(DF)[col1, col2]`. A plain
  `[[1, 2], ["x", "y"]]` is a `Vector{Vector}`, whose elements have no concrete type.
- More than 16 verb arguments lose the specialization on plain functions (`nrow`, `:`), which
  natively means a dynamic call. Pairs are not affected.

## Cost of multi-column sources

With `n` allowed column types, a source of `k` columns compiles `f` for `n^k` combinations of
types, since each column's type is a run-time value. That also holds for a tuple source.
A vector source compiles each arity that `f` has, up to 3. Methods are looked up at compile
time, so a 2-argument `f` costs `n^2`, while a vararg function like `+` costs `n + n^2 + n^3`.
With 8 column types, `[:a, :b] => ByRow(+)` and a 3-column tuple source each compile in about 40 s
with WasmCodegen, against 3 to 20 s for the other entries in `test/compile/Programs.jl`, and the
tuple source gives the largest module (480 KB, against 120 to 380 KB for most others). To reduce
this, allow fewer column types.

`vcat` has `n^2` type pairs, of which only pairs that promote to an allowed type compile to
copies. The others throw the `ColumnTypeError`.

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
