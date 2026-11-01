# Agent notes

## Layout

- Each package lives in its own top-level directory with its own `Project.toml`, `src` and `test`. Paths below are relative to the package directory, and `TrimmableFramesCSV/` has the same `test/compile` setup (about 2 minutes).

## Testing

- Do not eagerly run the full compile suite (`test/compile/runtests.jl`): it takes about 16 minutes. While iterating, run only the affected entries with `julia --project=test/compile test/compile/wasm.jl p_name1 p_name2`. Run the full suite only when the user asks or before finishing a change that needs real `juliac` verification.
