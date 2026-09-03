# Effects Lab

> Status: shipped as scaffolding, 2026-09-02. A tuning bench, not a feature — same
> delete-on-graduation contract as the other labs.

## What it is

SETTINGS → LABS → EFFECTS LAB: a bench for editing down the effects the app already ships. Three
knobs per IMAGE effect and FACE filter, judged over the showcase photos (and any `DevFixtures/`
photos bundled in a dev build), with a MIN / DEFAULT / MAX / THUMB toggle above the preview so
what you see is the end of the range you are dialling:

1. **ON IN EDITOR** — hold a chip, or flip the row. The next photo opened in the editor shows
   exactly the chips that are on. Retired-in-code effects are in the strip too, off by default
   and marked RETIRED; switching one on puts it back in the carousel with a card.
2. **WINDOWS** — per slider, MIN / MAX / DEFAULT within today's 0…1 span. The editor's knob
   spans the window and opens at the default. Nothing inside any effect changes — the window is
   applied once, at the view model's choke point, before the effect is built.
3. **THUMBNAIL** — the slider values and progress the picker card renders at, with the card
   itself rendered by the editor's own code beside the rows.

COPY SWIFT hands back four pasteable blocks: the two `retired` literals and the two
`EffectTuningTables` tables. Graduation is paste → RESET ALL → delete the lab.

## Where things live

| File | Role | Fate on graduation |
|---|---|---|
| `Models/EffectParameterWindows.swift` | `ParameterWindow`, `ThumbnailPreset`, the `EffectTuningTables` paste target, and `EffectLabLookup` — the value the editor snapshots | **Stays** |
| `Services/EffectThumbnailRenderer.swift` | Renders the picker cards for both families; the editor and the lab call the same function | **Stays** |
| `Models/EffectLabStore.swift` | On/off, windows, presets, bench position — one JSON blob under `effectLabState` | Deleted (+ one `removeObject`) |
| `Views/EffectLabView.swift` | The bench | Deleted |
| `FaceFilterType.retired` / `.selectable` | The FACE twin of `VisualEffectType.retired`, filled by the lab's snippet (FADE TO B&W as of 2026-09-02) | **Stays** |

Production hooks, all reading `EditorViewModel.effectLab`:

- `EditorViewModel.resolvedValue(_:for:)` — the one translation from knob position to the
  number the effect's `init` reads. `activeVisualEffectList` and `activeFaceEffect` go through
  it, so the preview and the GIF agree by construction.
- `EditorView.parameterBinding` — an untouched knob opens at the window's default.
- `EditorView.visualEffectsGrid` / `faceFiltersGrid` and the two thumbnail loops iterate
  `effectLab.enabledVisualEffects` / `enabledFaceFilters` instead of `selectable` / `allCases`.

## Gotchas worth keeping

- **Lab state is snapshotted per editor session.** `EditorViewModel` takes an `EffectLabLookup`
  at construction (`allowsGenerationWithoutZoom` is the precedent). Settings is a sheet on the
  gallery and the editor is rebuilt per photo, so the two cannot be open together — and the GIF
  path evaluates the effect list off the main thread, where a value is safe and a shared
  `ObservableObject` is not. A change in the lab shows on the *next* photo opened, never the
  current one. If Settings ever becomes reachable over the editor, compare a store revision in
  `generateEffectThumbnails` rather than reading the store from the hot path.
- **Thumbnail values are slider-space and pass through the window.** "Thumbnail intensity 0.7"
  is what the user's knob at 0.7 produces. With no lab state the renderer's output is
  byte-identical to the loop `EditorViewModel` used to run inline — `EffectLabTests` pins it.
- **DEFAULT is edited on the lattice inside the window**, via `normalized(in: min…max)`, so the
  position you set is the position the editor's knob opens at. MIN and MAX are absolute.
- **A window can only narrow.** It lives inside today's 0…1 and the effect's `init` still clamps
  to it. If an effect's top is too weak, raise the constant in that effect — one line — and the
  lab keeps working.
- **Retired effects now carry BACKGROUND ONLY.** The `selectable` gate on the toggle was dropped
  so a re-enabled effect arrives with the same modifier as every other card. ECHO still opts out.
- **Switching off the effect you are mid-edit on does nothing until the next photo** — the
  editor already has its snapshot. Not a bug; do not add a live path for it.
- **Live preview progress is not tunable.** THUMB mode renders the preview at the preset's
  progress so you can see the card at full size; the editor's canvas keeps `previewProgress`,
  because the GIF ignores it and a knob there would tune something that never ships.
- **Face detection in the lab runs on the 650px working copy**, not the full-size photo the
  editor detects on, so a very small face the editor finds may read NO FACE here. Showcase 2 and
  5 are portraits; the bench opens FACE on showcase 2.
- **`String(describing:)` in the snippet** prints case names for the two String-backed enums;
  `snippet_retiredSetUsesCaseNames` fails loudly if either ever adopts `CustomStringConvertible`.

## Graduations so far

- **2026-09-02** — the user's first dial-in on device: STRETCH and FADE TO B&W off, windows on
  15 effects (e.g. HALFTONE intensity 0.10…0.75 opening at 0.10, BITMAP scale capped at 0.60,
  CHROMA SHIFT opening at 0.05), and thumbnail presets on 17. Pasted into
  `EffectTuningTables` and the two `retired` sets. The same day the twelve SHADER LAB
  favourites arrived as IMAGE effects with their tuned values as window defaults — see
  `FEATURE-SHADER-LAB.md`.
