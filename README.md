# TrimmableFrames.jl

Packages for working with tabular data in code compiled with `juliac --trim=safe` and
[WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

- [TrimmableFrames](TrimmableFrames/README.md): data frames with the verbs and mini-language of
  DataFrames.jl.
- [TrimmableFramesCSV](TrimmableFramesCSV/README.md): reads CSV text with a schema found at run
  time into those frames.
- [TrimmableFramesXPT](TrimmableFramesXPT/README.md): reads SAS transport files into those
  frames, with labels and formats as metadata.

Install a package from its subdirectory:

```julia
import Pkg
Pkg.add(url = "https://github.com/jkrumbiegel/TrimmableFrames.jl", subdir = "TrimmableFrames")
```

The packages are not registered, so `TrimmableFramesCSV` and `TrimmableFramesXPT` have to be
added together with `TrimmableFrames`:

```julia
url = "https://github.com/jkrumbiegel/TrimmableFrames.jl"
Pkg.add([
    Pkg.PackageSpec(; url, subdir = "TrimmableFrames"),
    Pkg.PackageSpec(; url, subdir = "TrimmableFramesCSV"),
])
```
