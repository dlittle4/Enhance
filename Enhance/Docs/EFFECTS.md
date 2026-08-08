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

**The original WGSL is now in hand** — kept verbatim at
[`reference/riso-print.wgsl`](reference/riso-print.wgsl). Port from that, not from prose.

> **Two things the earlier prose summary got wrong**, both recorded here because they were in
> this document until the source arrived:
>
> 1. **It is tonal-band separation, not CMYK ink separation.** There is no absorption matrix
>    and no C/M/Y/K. Luminance is split into shadow / midtone / highlight bands, and each band
>    is assigned one user-chosen spot colour. That is a different architecture, and a much
>    better fit for this app (see below).
> 2. **Grain is additive and post-composite**, not a perturbation of density before screening.

#### Pipeline

1. **Misregistration** — three samples of the input at slightly different UVs, simulating
   plate misalignment. Offsets are fixed fractions of the `misreg` parameter: A `(0.7, 0.3)`,
   B `(-0.5, 0.6)`, C `(0, 0)`. **C is the reference plate** and never moves.
2. **Contrast** — per sample, `clamp((lum - 0.5) * contrast + 0.5, 0, 1)`.
3. **Tonal separation** — three masks over the contrasted luminance:
   ```
   shadow    = smoothstep(0.5, 0.0, lumA)      // dark end
   midtone   = 1.0 - abs(lumB - 0.5) * 2.0     // triangular peak at 0.5
   highlight = smoothstep(0.5, 1.0, lumC)      // bright end
   ```
4. **Halftone** — each band gets its own screen. Angles are the classic moiré-avoiding set, in
   radians: **0.2618 (15°)**, **1.309 (75°)**, **0.7854 (45°)**.
   ```
   rotUv  = rotate(pixelCoord, angle)
   local  = fract(rotUv / scale) - 0.5
   radius = sqrt(1.0 - clamp(lum, 0, 1)) * 0.5
   dot    = smoothstep(radius + 0.02, radius - 0.02, length(local))
   ```
   Note the call sites pass `1.0 - mask`, so a strong mask yields a large dot. The `sqrt` is
   what makes dot **area** track density rather than radius.
5. **Subtractive compositing** onto warm off-white paper:
   ```
   paper  = (0.96, 0.94, 0.92)
   ink_i  = mix(white, colour_i, dot_i)
   result = paper * inkA * inkB * inkC
   ```
6. **Grain** — `result += (hash2(pixelCoord * 1.7 + (42, 17)) - 0.5) * grain * 0.3`, then clamp.
   Alpha passes through from the unshifted sample.

#### It fits the existing parameter budget — but only just

Four scalars (`scale`, `misreg`, `grain`, `contrast`) plus three colours. Declared naively that
is seven rows and three pickers, which **breaks both panel invariants**:
`parameters.count <= 5` and `pickers.count <= 1`.

**The three colours are shadows / midtones / highlights — which is exactly `GradientStops`
(`dark` / `mid` / `light`).** Reuse it and the whole effect declares four sliders plus one
`gradientStops` picker: five rows, one picker, both caps satisfied with nothing to spare. The
picker row and its `ColorPicker` wells already exist and need no new UI.

#### Porting notes

- WGSL → Metal is mechanical: `textureSample(tex, samp, uv)` → `inputTex.sample(samp, uv)`,
  `vec4f` → `float4`, `@group/@binding` → Core Image kernel arguments. The math is unchanged.
- As a `CIKernel` there is no vertex stage and no explicit sampler — `dest.coord()` replaces
  `uv * dims`, and the input arrives as a `coreimage::sampler`.
- **Luminance: use the source's Rec.601 weights here, deliberately.** The section above tells
  you to standardise on Rec.709, and that stands for new effects — but this is a port of a
  specific look, and the tonal band edges were tuned against 601. Switching to 709 weights
  green ~22% higher, pushing green-heavy regions from the midtone band toward the highlight
  band. Match the source and leave a comment saying why, rather than "fixing" it into a
  different look.
- **`misreg` is normalised by width only** (`params.y / dims.x`) and applied to both axes, so
  the vertical offset is proportionally smaller on a landscape image. Almost certainly
  unintentional in the original; reproduce it if matching exactly, but normalising per-axis is
  defensible.
- The reference's `halftone()` computes `cell` and never uses it. Drop it.
- It is a **grid effect** — needs `FrameGeometry` for both scale and phase, or the screens will
  crawl across the subject exactly as DITHER did.
- Early-out **before** touching the kernel. Three input samples plus three screens makes this
  the most expensive effect in the app.

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

---

## Specifications for the build candidates

Distilled from the Figma shader reference. Only the effects we intend to build are written
out — the rejected ones are listed above with reasons, and copying their math here would
just invite re-litigating those decisions.

> ### Read the snippets as directional, not prescriptive
>
> These describe **the look we are after and which parameters matter**. They are not an
> implementation to transcribe, and they are not a contract.
>
> Concretely:
>
> - **Prefer the stock filter if it gets the look.** The snippets are written as
>   fragment-shader UV math because that is the form the reference came in. That does not
>   mean a kernel is required. `CIEdgeWork` may cover Hatching; strip compositing may cover
>   Slice shift. "Rule zero" above still governs — the snippet is a description of the
>   destination, not the route.
> - **The numbers are starting points.** Frequencies, thresholds, falloff radii and IOR
>   values were tuned for a different renderer at a different resolution. Expect to
>   re-tune against a 600×600 GIF frame and a 650px preview.
> - **Do not trust the constants.** The Rec.601-labelled-as-Rec.709 error below is the
>   proof: this material has at least one transcription mistake in it, so verify anything
>   load-bearing against a primary source rather than assuming.
> - **Our conventions win where they conflict.** Progress ramps, early-out guards, extent
>   cropping, `frameIndex`-seeded randomness and `FrameGeometry` are project rules; none of
>   them appear in the reference, and all of them still apply.

### First: use one definition of luminance

The source reference labels `(0.299, 0.587, 0.114)` as "Rec.709". **It is not** — those are
Rec.601 (NTSC) weights. Rec.709 is `(0.2126, 0.7152, 0.0722)`.

The difference is not academic: 601 weights green at 0.587 and 709 at 0.7152, so the same
pixel yields a visibly different luminance, which shifts every threshold built on top of it.
`GradientMapEffect` already uses **Rec.709**, so use Rec.709 everywhere and treat the
reference's constants as a transcription error.

```
L = 0.2126 * r + 0.7152 * g + 0.0722 * b
```

### Hatching

Luminance-driven line density, layered at multiple angles for cross-hatch.

```
rotUV  = rotate(pixelCoord / density, angle)
pattern = abs(sin(rotUV.x * PI * frequency))          // straight lines
```

Line style variants substitute the argument to `sin`:

| Style | Argument |
|---|---|
| Wave | `rotUV.x + sin(rotUV.y * waveFreq) * waveAmp` |
| Zigzag | `rotUV.x + (abs(fract(rotUV.y * zigFreq) - 0.5) * 2) * zigAmp` |
| Circle | `length(rotUV - center)` — concentric rings |

Darkness adds layers, each at its own angle:

```
hatch1 = smoothstep(softness, 0, pattern1 - (1 - L * 1.33))   // appears below L 0.75
hatch2 = smoothstep(softness, 0, pattern2 - (1 - L * 2.00))   // below L 0.50
hatch3 = smoothstep(softness, 0, pattern3 - (1 - L * 4.00))   // below L 0.25
mask   = max(hatch1, max(hatch2, hatch3))
result = mix(paperColour, inkColour, mask)
```

**Grid effect** — needs `FrameGeometry` for both scale and phase. Try `CIEdgeWork` /
`CIComicEffect` first; if they get close enough, this needs no kernel at all.

### Slice shift

Bands displaced along a direction, with per-band jitter.

```
dir        = vec2(cos(angle), sin(angle))
perpDir    = vec2(-dir.y, dir.x)
sliceCoord = dot(pixelCoord - centre, perpDir)
sliceIndex = floor(sliceCoord / sliceWidth)

shift  = (sliceIndex mod 2 == 0) ? +amount : -amount
shift += (hash(sliceIndex) - 0.5) * jitter          // seed from sliceIndex, never random()
newUV  = uv + dir * shift / textureSize
```

Soften the band edges rather than hard-cutting them, or the boundaries alias badly:

```
local = fract(sliceCoord / sliceWidth)
blend = smoothstep(0, softness, local) * smoothstep(0, softness, 1 - local)
final = mix(uv, newUV, blend)
```

Animate by feeding `frameIndex` into the hash. **Strip compositing may avoid a kernel
entirely** — this was previously in the project as `GlitchEffect`, doing exactly that.

### Pixel stretch

Smears pixels along a line segment.

```
ab       = B - A
t        = clamp(dot(uv - A, ab) / dot(ab, ab), 0, 1)
closest  = A + t * ab
perpDist = length(uv - closest)

lineDir  = normalize(ab)
perpDir  = vec2(-lineDir.y, lineDir.x)
falloff  = smoothstep(falloffRadius, 0, perpDist)
newUV    = mix(uv, closest + perpDir * offset, falloff * strength)
```

Pixels near the line all sample from roughly the same perpendicular position, which is what
produces the smear. `smoothness` widens the `smoothstep` band.

### Pattern refraction

Procedural height → normal → UV offset, with per-channel dispersion.

Height functions, all in UV space:

| Pattern | Height |
|---|---|
| Lenticular | `0.5 + 0.5 * sin(uv.x * freq * 2PI)` |
| Zigzag | `abs(fract(uv.x * freq) - 0.5) * 2 * amp` |
| Waves | `sin(uv.x * freqX + sin(uv.y * freqY) * bend) * amp` |
| Circular | `sin(length(uv - centre) * freq * 2PI) * amp` |
| Dome grid | `max(0, 1 - length(fract(uv * grid) - 0.5) * curvature)` |

Then finite differences for the normal, and Snell's law approximated as a UV offset:

```
dhdx   = (h(uv + [eps,0]) - h(uv - [eps,0])) / (2 * eps)
dhdy   = (h(uv + [0,eps]) - h(uv - [0,eps])) / (2 * eps)
normal = normalize(vec3(-dhdx, -dhdy, 1))

R = sample(uv + normal.xy * (IOR_R - 1) * strength)   // IOR_R > IOR_G > IOR_B
G = sample(uv + normal.xy * (IOR_G - 1) * strength)
B = sample(uv + normal.xy * (IOR_B - 1) * strength)
```

Frost perturbs the normal before refracting:
`normal.xy += (hash2(pixelCoord) - 0.5) * frostAmount`.

Clamp or mirror out-of-bounds UVs, and set the **ROI callback** to outset by the maximum
possible displacement — this is precisely the effect where too tight an ROI produces black
seams at Core Image's tile boundaries.

### Halftone — richer than `CICMYKHalftone`

The shipped HALFTONE uses `CICMYKHalftone`, which is fixed. A kernel would add BW and RGB
modes, arbitrary screen angles, and ordered-dither blending. Only worth building if the stock
filter proves limiting.

```
rot    = rotate(pixelCoord, screenAngle) / cellSize
offset = fract(rot) - 0.5
radius = sqrt(1 - L) * 0.5                       // darker = bigger dot
dot    = smoothstep(radius + softness, radius - softness, length(offset))
```

Classic screen angles — **C 15°, M 75°, Y 0°, K 45°** — are what avoid moiré; do not pick
arbitrary ones. Composite subtractively, which is how ink behaves:

```
result = paper * (1 - C*cyan) * (1 - M*magenta) * (1 - Y*yellow) * (1 - K*black)
```

The `sqrt` on the radius is the detail that matters: it makes dot **area** proportional to
density rather than dot radius, so the tonal ramp is linear.

### Bokeh — the face-aware version

`CIBokehBlur` exists, so a kernel is only worth it for the brightness weighting, which is what
makes bokeh read as bokeh rather than as blur:

```
weight = 1 + max(0, luminance - brightnessThreshold) * bloomIntensity
```

Sample on a golden-angle spiral for even disc coverage:
`angle = i * 2.399963`, `radius = sqrt(i / N) * blurRadius`.

**The interesting version here is not in the reference.** The app already detects faces, so
blurring *everything except* the detected face gives real portrait-mode depth of field —
something the source effect cannot do because it has no notion of a subject.

---

## Control audit — effects with hidden parameters

The detail panel removed the two-slider cap, but **no existing effect was revisited afterwards.**
Every effect below still collapses several independent qualities into one INTENSITY slider, or
hardcodes a value the user would reasonably want to change. Each is a data change now: declare
the parameter, thread it through `init`, done.

Findings from reading the effects, not speculation — file and value named. Ordered by how much
the extra control would actually change what a user can make.

| Effect | Hidden today | Candidate controls |
|---|---|---|
| **DITHER** | `levels = 12 - 9 * amount` is coupled to intensity; output is always colour | **LEVELS** (posterisation depth, independent of dither amplitude) and **MONO** — 1-bit B&W dither is the most legibly "dithered" look and the most on-brand |
| **MOTION BLUR** | `angle = .pi / 4`, a hardcoded 45° | **ANGLE**. A directional blur whose direction cannot be set is half a feature |
| **SWIRL** | `radius = max(w, h) * 0.4` | **SIZE**. Straight parity gap — FISHEYE already exposes exactly this, and both wrap distortion filters with a radius |
| **HALFTONE** | `kCIInputSharpnessKey: 0.7`; `inputAngle` and `inputGCR` never set at all | **SHARPNESS** (dot hardness) and **ANGLE** (screen rotation). `CICMYKHalftone` supports both already |
| **HEAT HAZE** | `frequency = 0.015` and `phase = frameIndex * 0.35` | **FREQUENCY** (wave scale) and **SPEED** (how fast it shimmers across frames) |
| **CHROMA SHIFT** | Shift direction is fixed in the per-channel offsets | **ANGLE**. Horizontal vs vertical fringing are visually distinct looks |
| **GRADIENT** | Midpoint fixed at 0.5; no tiling mode | **MIDPOINT** (where `mid` sits on the ramp) and possibly repeat/mirror tiling |
| **PIXELATE** | Rectangular cells only | **SHAPE** — `CIHexagonalPixellate` already exists, so hex is nearly free |
| **RAINBOW** | No animation control | **SPEED**. The *face* variant already has one; the image variant does not |

### Watch the budget

`parameters.count <= 5` and `pickers.count <= 1` are enforced by
`EffectParameterTests`, and they exist because the browse state has no scroll. Most of the
above adds one or two rows, which is fine. If an effect genuinely needs more than five, raise
the cap deliberately and confirm the panel still scrolls correctly on a short device — do not
just relax the assertion.

### Prefer separating coupled qualities over adding new ones

The pattern in most of these is one slider driving two independent things — DITHER's amplitude
and posterisation, EDGES' sensitivity and line thickness. Splitting those is more valuable than
inventing new parameters, because it makes a range of looks reachable that currently is not,
without changing what the effect *is*.
