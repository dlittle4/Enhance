# Enhance — Effects Reference

> How to build a new effect, and what is still worth building.
>
> **ROADMAP.md** tracks *what and when* — Phase 17e is the tracked item for the custom-kernel
> work below. **LEARNINGS.md** records rules discovered in retrospect. **This file** is the
> forward-looking *how*: the triage, the build mechanics, and per-effect specifications.

---

## Current state

**11 effects live**, in carousel order:

`CHROMA SHIFT` · `HALFTONE` · `FISHEYE` · `SWIRL` · `PIXELATE` · `RAINBOW` · `HEAT HAZE` ·
`MOTION BLUR` · `GRADIENT` · `EDGES` · `DITHER`

**6 retired** (compiled and tested, hidden from the picker — remove from
`VisualEffectType.retired` to bring one back): Monotone, Duotone, Bloom, Inversion,
Vintage Grain, Pop Art.

**13 face filters**, all shipped.

Every effect so far is composed from stock `CIFilter`s. **There is no custom Core Image
kernel infrastructure in the project** — the only `.metal` file, `Shaders/Pixellate.metal`,
is a SwiftUI `[[stitchable]]` shader used for the animated canvas border, and it cannot
render GIF frames (see the hazard below).

---

## Rule zero: check Core Image before writing a kernel

Most named effects are one or two stock filters. These were all verified present on the
device runtime — if you are reaching for a kernel, check this list first.

| Want | Use |
|---|---|
| Colour grade / film look | `CIColorMatrix`, `CIToneCurve`, `CIColorControls`, `CIVibrance`, `CITemperatureAndTint`, `CIPhotoEffect*`, `CISepiaTone` |
| Luminance → colour ramp | `CIColorCubeWithColorSpace` *(not `CIColorCube` — see below)* |
| Edge detection | `CIEdges`, `CIEdgeWork`, `CILineOverlay`, `CIComicEffect` |
| Ordered dithering | `CIDither` |
| Posterise | `CIColorPosterize` |
| Mosaic | `CIPixellate`, `CIHexagonalPixellate`, `CICrystallize`, `CIPointillize` |
| Distortion | `CIBumpDistortion`, `CITwirlDistortion`, `CIPinchDistortion`, `CIGlassDistortion`, `CIDisplacementDistortion` |
| Blur | `CIGaussianBlur`, `CIMotionBlur`, `CIZoomBlur`, `CIBokehBlur` |
| Glow | `CIBloom`, `CIGloom` |
| Halftone | `CICMYKHalftone` |
| Thermal / X-ray | `CIThermal`, `CIXRay` |
| Kaleidoscope | `CIKaleidoscope`, `CITriangleKaleidoscope` |

Two traps that have already cost time here:

- **`CIColorCubeWithColorSpace`, never plain `CIColorCube`.** The plain filter works in the
  `CIContext`'s working space, which is *linear* sRGB. sRGB-authored colours come out washed
  out and midtone-heavy.
- **`applyingFilter` fails silently on an unknown name** — it returns the image unchanged
  rather than throwing. `requiredFilterNames_exist` guards every name the project uses; add
  to it when you add a filter.

---

## Writing an effect

### The protocol

```swift
func apply(to: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage
func apply(to: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage
func apply(to: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage
```

Defaulted overloads, so implement only what you need:

- **`viewportCenter`** — the preview passes the viewport centre in image coordinates so
  spatially-centred effects track what the user is looking at. The GIF pipeline passes nil.
- **`geometry`** — how the frame relates to the source. Only effects with their own *spatial
  grid* need it (see "Grid effects" below).

### Non-negotiables

1. **Early-out.** `guard amount > 0.01 else { return image }`. Skips GPU work on frames where
   the effect is imperceptible.
2. **`.cropped(to: image.extent)`** at the end, unless you have a specific reason not to.
   Distortion, blur and pixelate filters all *grow* the extent; generators are infinite. An
   effect returning a larger image letterboxes the editor canvas and changes GIF frame
   dimensions. `allEffects_preserveInputExtent` enforces this.
3. **Bake `intensity` into `let` properties in `init`.** `apply` never sees the raw value.
4. **Ramp `progress`.** Linear-with-clamp (`min(1, progress * 1.5)`) for colour grades,
   `progress²` for moderate ease-in, `progress³` for aggressive. Invert (`1 - progress`) for
   effects that should *resolve* rather than accumulate.
5. **Seed randomness from `frameIndex`**, never `random()` — GIF playback must be reproducible
   and the preview must match the export.

### Wiring checklist

New effects are not auto-discovered:

1. New file in `Services/Animators/`.
2. `Models/VisualEffectType.swift` — add the case, a line in `effect(intensity:options:)`, and
   the controls in `parameters`. Must **not** be in `retired` to appear.
3. `EnhanceTests/VisualEffectTests.swift` — the standard pair plus anything effect-specific.
   `visualEffectType_allCasesProduceOutput` and the extent tests enrol it automatically.
4. Face-filter availability is a **separate** opt-in in `Models/FaceFilterType.swift`.

Cards and the detail panel come free — the gallery renders from `selectable`, and the panel
renders a row per declared parameter.

### Grid effects

An effect whose output has a characteristic size in pixels — dither cells, halftone screens,
hatching lines — must use `FrameGeometry`, because the GIF applies effects *after* the zoom
transform while the preview applies them *before*.

- **`geometry.scale`** — multiply your cell size by it, so the grid stays the same size
  relative to the subject rather than the frame.
- **`geometry.contentOrigin`** — offset your grid by this modulo the cell size. **Scale alone
  is not enough**: the animation pans as it zooms, so a grid anchored to the frame corner
  still slides across the subject.

`DitherEffect` is the worked example. Verify with the periodicity property: at fixed scale,
shifting `contentOrigin` by exactly one cell must render **byte-identical** output, and a
half-cell shift must not. Use a gradient fixture — a solid colour posterises flat and passes
trivially.

### Verify by looking

Structural tests cannot see a wrong-looking effect. `output.extent == input.extent` and
`createCGImage != nil` both passed while EDGES rendered cyan instead of green and while the
canvas had a black band across the top.

Render every effect to PNG against a fixture with a **luminance sweep, colour patches and hard
edges**, and look at them. A solid-colour fixture shows nothing.

---

## Phase 2 — custom Core Image kernels

Everything above is stock Core Image. The effects below have no built-in equivalent and need a
kernel. **This infrastructure does not exist yet.**

### The hazard, and the resolution

Setting `MTLCOMPILER_FLAGS = -fcikernel` / `MTLLINKER_FLAGS = -cikernel` at **target scope
would break the app's animated canvas border.** Those flags hit every `.metal` file in the
target, including `Shaders/Pixellate.metal` — a SwiftUI `[[stitchable]]` shader used at
`EditorView` and `GradientViews`. `-cikernel` makes `metallib` emit a Core Image kernel
library, which cannot serve `ShaderLibrary.default`, so `.layerEffect` fails to find the
function. **At runtime, in visible chrome — not at build time.**

**Resolution: a custom build rule scoped to `*.ci.metal`.** Custom rules take precedence over
Xcode's built-in Metal rule *for matching files only*, so `Pixellate.metal` continues through
the stock path untouched.

1. Kernels go in `Shaders/CI/` (auto-added — the project uses `fileSystemSynchronizedGroups`).
2. Add the rule via the **Xcode UI** (Target → Build Rules → +), not by hand-editing the
   pbxproj — `objectVersion 77` `PBXBuildRule` entries are easy to malform.
   - Match `*.ci.metal` → Custom script:
     ```
     xcrun -sdk $PLATFORM_NAME metal -c -fcikernel "$INPUT_FILE_PATH" \
       -o "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.air"
     xcrun -sdk $PLATFORM_NAME metallib -cikernel "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.air" \
       -o "$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/$INPUT_FILE_BASE.metallib"
     ```
   - Output: `$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/$(INPUT_FILE_BASE).metallib`
3. **`$INPUT_FILE_BASE` strips only the last extension**, so `Riso.ci.metal` becomes
   `Riso.ci.metallib`. Load with `forResource: "Riso.ci"`. Getting this wrong yields a silent
   nil kernel.
4. Load once via `static let` — effect `init` runs on every preview frame, and kernel
   construction parses the library. Guard `else { return image }` so a missing metallib
   no-ops rather than crashes.

**Fallback if the rule doesn't work:** a dedicated Metal Library target with the flags at
*that* target's scope. Cleaner conceptually, but needs a
`PBXFileSystemSynchronizedBuildFileExceptionSet` to keep the kernel folder out of the app
target's Sources phase.

### Do the gate first

Before writing any effect math: add the build rule plus a passthrough kernel
(`extern "C" float4 riso(coreimage::sample_t s) { return s; }`) and verify

- (a) `Riso.ci.metallib` appears in the app bundle,
- (b) **the animated border still renders** in both `EditorView` and `GradientViews`,
- (c) `CIKernel(functionName:fromMetalLibraryData:)` returns non-nil in a unit test — tests are
  hosted, so `Bundle.main` is `Enhance.app`.

A negative result means falling back, and that is worth knowing before the algorithm work.

### Two things that make hand-ported shaders look wrong

- **Colour space.** The kernel runs in the context's working space — *linear* sRGB. Constants
  sampled from a reference image are sRGB. Convert **inside the kernel** (`pow(c, 1/2.2)` in,
  `pow(c, 2.2)` out) rather than changing `workingColorSpace`, which would silently alter every
  existing effect.
- **ROI callback.** Outset by however far you sample away from the destination coordinate, plus
  a couple of pixels. Too tight gives black seams at Core Image's internal tile boundaries —
  visible only on large images, so not in a small test fixture.

---

## Candidate effects

### Riso Print — the first kernel

Risograph emulation. The most distinctive look available and the best fit for the app's
pixel-art identity, which is why it is first.

> **The original WGSL source was never available.** It was referenced but never provided, so
> this is implement-from-description. Budget iteration. Prototyping with a string-based
> `CIKernel(source:)` in CIKL converges on the look faster, then port to Metal — but do not
> ship CIKL; it is deprecated and unchecked at compile time.

A general `CIKernel` (not `CIColorKernel`) — per-channel misregistration and rotated screens
both sample away from the destination coordinate.

1. **Misregistration** — each ink samples at `uv + offset_i`, fixed unit directions scaled by a
   `misreg` parameter. Animate subtly off `frameIndex` for a live-print feel.
2. **Separation** — `dens_i = saturate(dot(1.0 - rgb, absorb_i))` with a fixed 3×3 absorption
   matrix approximating the spot inks. Linearise first.
3. **Screening** — rotate `uv` by the ink's screen angle (15° / 45° / 75°, the classic
   moiré-avoiding offsets), then `cell = fract(rot/cellSize) - 0.5`, `r = sqrt(dens_i) * 0.5`,
   `cov_i = smoothstep(r + aa, r - aa, length(cell))`. **The `sqrt` matters** — it makes dot
   *area* proportional to density rather than dot radius.
4. **Compositing** — `color = paper; for each ink: color *= mix(1.0, ink_i, cov_i)`.
   Multiplicative, which is how ink on paper actually behaves.
5. **Grain** — perturb density *before* screening; it reads as paper texture rather than
   post-hoc noise.

Swift wrapper: intensity → `cellSize` (12→4px), `misreg` (0→3px), `grain` (0→0.35);
`frameIndex` → seed; dissolve ramp; early-out **before** touching the kernel, since this is the
most expensive effect in the app.

It is a grid effect — it needs `FrameGeometry` for both scale and phase.

### Also worth building

| Effect | Approach | Notes |
|---|---|---|
| **Hatching** | Luminance-driven line density: `sin(rotatedUV * frequency)` thresholded against luminance, layered at multiple angles for cross-hatch | `CIEdgeWork` / `CIComicEffect` get part-way without a kernel — try those first |
| **Slice shift** | Horizontal bands, per-band displacement with a `frameIndex`-seeded hash | Was previously in the project as `GlitchEffect` and deleted; animates well across frames. Strip compositing may avoid a kernel entirely |
| **Pixel stretch** | Project each pixel onto a line segment, replace one UV component with the projection, `smoothstep` falloff | No built-in equivalent |
| **Pattern refraction** | Procedural height → normal via finite differences → offset UV by `normal.xy * (IOR - 1)`; per-channel IOR for dispersion | `CIGlassDistortion` needs a texture; procedural normals are better |
| **Water caustic** | Animated caustic pattern composited over the photo | The one *fill* from the catalog that works on a photo rather than as a background |

### Deliberately not building

- **Outlines (Jump Flood)** — log₂(n) compute passes *per frame*, ~25 frames per GIF.
- **Gooey merge** — operates on vector alpha; meaningless on a photo.
- **Floyd–Steinberg / Atkinson / Riemersma dither** — sequential error diffusion needs compute
  shaders with cross-pixel dependencies. `CIDither` gets 90% of the look for 2% of the work.
- **Chromatic metal** — needs environment/normal mapping; expensive and looks odd on faces.
- **Warp** — needs control-point UI, which does not fit a one-tap card.
- **Channel mixer / Colour adjust** — utilities, not creative effects. They belong in a settings
  panel, not the effects gallery.
- **The remaining fills** (mesh gradient, nebula, clouds, fractal noise, pattern grid,
  concentric, glowing wave) — they *generate* content rather than transform a photo.
