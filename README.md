# TrimmableFrames.jl

Packages for working with tabular data in code compiled with `juliac --trim=safe` and
[WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

- [TrimmableFrames](TrimmableFrames/README.md): data frames with the verbs and mini-language of
  DataFrames.jl.
- [TrimmableFramesCSV](TrimmableFramesCSV/README.md): reads CSV text with a schema found at run
  time into those frames.

Install a package from its subdirectory:

```julia
import Pkg
Pkg.add(url = "https://github.com/jkrumbiegel/TrimmableFrames.jl", subdir = "TrimmableFrames")
```

The packages are not registered, so `TrimmableFramesCSV` has to be added together with
`TrimmableFrames`:

```julia
url = "https://github.com/jkrumbiegel/TrimmableFrames.jl"
Pkg.add([
    Pkg.PackageSpec(; url, subdir = "TrimmableFrames"),
    Pkg.PackageSpec(; url, subdir = "TrimmableFramesCSV"),
])
```
