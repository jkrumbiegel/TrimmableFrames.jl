# TrimmableFrames.jl

Packages for working with tabular data in code compiled with `juliac --trim=safe` and
[WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl).

- [TrimmableFrames](TrimmableFrames/README.md): data frames with the verbs and mini-language of
  DataFrames.jl.

Install a package from its subdirectory:

```julia
import Pkg
Pkg.add(url = "https://github.com/jkrumbiegel/TrimmableFrames.jl", subdir = "TrimmableFrames")
```
