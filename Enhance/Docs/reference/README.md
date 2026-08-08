# Reference sources

Original shader sources kept verbatim, for porting against.

`.wgsl` files are **not compiled** — they live under `Docs/` deliberately so Xcode's
synchronised group never picks them up as build inputs or bundle resources.

| File | Notes |
|---|---|
| `riso-print.wgsl` | The Riso Print effect, WebGPU/WGSL. The only shader in the catalog whose source we have. Kept because it went missing three times before arriving; the prose summary that stood in for it was wrong in two places (see EFFECTS.md). |
