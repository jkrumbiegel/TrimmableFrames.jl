# Agent notes

## Testing

- Do not eagerly run the full compile suite (`test/compile/runtests.jl`): it takes about 16 minutes. While iterating, run only the affected entries with `julia --project=test/compile test/compile/wasm.jl p_name1 p_name2`. Run the full suite only when the user asks or before finishing a change that needs real `juliac` verification.
