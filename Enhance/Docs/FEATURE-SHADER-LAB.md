# Shader Lab

> Status: shipped as scaffolding, 2026-08-30. A tuning bench, not a feature — same
> delete-on-graduation contract as the other labs.

## What it is

SETTINGS → LABS → SHADER LAB: a bench for auditioning the 41 SwiftUI Metal shaders vendored from
[SwiftUIShaders](https://github.com/krispuckett/SwiftUIShaders) (Kris Puckett, MIT — see
`THIRD_PARTY_NOTICES.md`) and dialling in the set Enhance should actually ship. Every parameter
of every shader is a live slider over a real showcase photo; the two interaction-driven shaders
(`bcsRefractLens`, `bcsTouchRipple`) aim by dragging the preview itself.

The workflow the lab is built around:

1. **Audition** — chips in the two-row strip, judged against showcase photos (NEXT PHOTO cycles).
2. **Star the keepers** — hold a chip (or tap ★ by the title). Starred shaders sort to the front
   of the strip on next open; the strip's left edge *is* the final set so far.
3. **Dial in** — sliders bound to the ranges upstream documents as sweet spots. Values persist
   per shader across launches.
4. **Graduate** — COPY MODIFIER writes the one line that reproduces the look, e.g.
   `.bcsHolographic(intensity: 0.62, scale: 14, speed: 1.10, angleOffset: 0)`, calling the typed
   wrappers in `ShaderPackEffects.swift`. Paste at the real call site; the lab is then done with
   that shader.

## Where things live

| File | Role | Fate on graduation |
|---|---|---|
| `Shaders/ShaderPack.metal` | The 41 `[[ stitchable ]]` functions, vendored verbatim | **Stays** — graduated effects render from it |
| `Components/ShaderPackEffects.swift` | Typed `View` wrappers (`.bcsGlitch(…)`), vendored with two mechanical adaptations | **Stays** — the paste target |
| `Models/ShaderLabCatalog.swift` | Generated catalog: names, ranges, defaults, time slots | Deleted |
| `Models/ShaderLabStore.swift` | Selection, per-shader values, favourites — one JSON blob under `shaderLabState` | Deleted (+ one `removeObject`) |
| `Views/ShaderLabView.swift` | The bench | Deleted |

## Gotchas worth keeping

- **`bcs_chromaticSplit` takes `time` fourth, not second.** Every other animated shader in the
  pack takes it right after `size`. The catalog carries a per-shader `timeSlot` for exactly this,
  and `ShaderLabTests.catalog_timeSlots_matchTheMetalSignatures` pins it — a flattened slot
  renders the shader with its spread driven by the clock, wrong but error-free.
- **The lab calls shaders generically** (`Shader(function:arguments:)` by Metal name); shipped
  code should use the typed wrappers instead. Both compile from the same `default.metallib` —
  the `*.ci.metal` build rule's `-fcikernel` scoping (ROADMAP §1c) deliberately does not reach
  plain `.metal` files, which is what keeps the pack loadable by `ShaderLibrary.default`.
- **`maxSampleOffset` is 64pt everywhere**, matching the wrappers' default. Far-reaching
  displacement at extreme values (`bcsMelt` at 100, `bcsEcho` at 50×8) can clip at the preview's
  edges; if a graduated effect needs more, raise it at the call site, not in the lab.
- **Upstream's tuned defaults are the source of truth**, including the one that overdrives its
  own documented range (`bcsNeonEdge.glowAmount`, default 4 against 0–2 — the catalog widens the
  slider rather than clamping the author's look).

## Refreshing the vendored pack

`ShaderLabCatalog.swift` is generated from upstream's `Docs/parameters.json` cross-checked
against the `.metal` signatures (vendored commit is recorded in `THIRD_PARTY_NOTICES.md`). To
refresh: re-copy the two vendored files (re-apply the two mechanical adaptations noted at the
top of `ShaderPackEffects.swift`), regenerate the catalog rather than hand-editing it, and let
`ShaderLabTests` catch what moved.

## Graduated 2026-09-02

The twelve starred shaders now ship: THERMAL, CHROMATIC SPLIT, DATAMOSH, HEAT SHIMMER, LIVE
RIPPLE, MELT, NEON EDGE, PIXEL STORM, SHOCKWAVE, SOLARIZE and WAVE POOL as IMAGE effects
(THERMAL and MELT also on the FACE tab, masked through `FaceVisualEffect`), and PULSE as
HEART BEAT on the ZOOM tab — the same kernel, appended to the effect list while that zoom card is
selected, with the shader's controls standing in for SPEED / PAUSE / MOTION.
Not via the typed wrappers (those are SwiftUI `layerEffect`s, and the editor's pipeline is
`CIImage` in, `CIImage` out) but as Core Image kernels: `Shaders/CI/ShaderPack.ci.metal` carries
the vendored bodies verbatim inside a `BCSLayer` frame that stands in for `SwiftUI::Layer`, and
`PackShaderEffect` drives them. The lab's tuned values landed in `EffectTuningTables.windows` as
each knob's opening position, so the editor's defaults are the lab's. The lab, the wrappers and
`ShaderPack.metal` stay for auditioning the other 29.
