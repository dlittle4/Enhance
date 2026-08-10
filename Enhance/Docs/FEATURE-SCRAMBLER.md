# Feature Scrambler — Product and Implementation Plan

> Status: proposed
>
> Scope: a new face effect for rearranging copied regions of a detected face.
> This document specifies the first shippable version and the groundwork it should leave behind.

## Summary

Feature Scrambler copies recognizable parts of a face and places them in deliberately wrong
positions. The first shippable version is intentionally narrow:

- **V1 — THIRD EYE:** copy one eye to the forehead, with SIZE and INTENSITY controls.
- **Follow-up layout pack:** MOUTH EYES, EYE MOUTH, and SHUFFLE, selected from a preset row.

The layout pack is a separate feature stage, not part of the V1 acceptance gate. It introduces a
new picker kind, typed layout state, additional landmark requirements, and unavailable-layout
behavior; bundling it into V1 would make the UI/state work larger than the compositor itself.

The effect animates into its final arrangement during the GIF's zoom and stays stable during the
pause. It uses the selected face when a photo contains several faces.

V1 should be built as a landmark-aware Core Image compositor, not a custom kernel. Region
extraction, affine transforms, feathered masks, and compositing are all supported by the existing
lazy `CIImage` pipeline. A kernel would add build and sampling risk without improving the core
effect.

---

## Research basis — Snapchat Face Inset

Feature Scrambler is an iOS interpretation of the **Face Inset** technique documented by Snap,
not a claim to reproduce Lens Studio's private implementation. Snap's effect copies a live facial
region such as an eye, mouth, nose, or entire face and renders it at another face-relative
location. Snap explicitly uses examples such as placing an eye on the forehead and replacing eyes
with mouths — the two clearest starting layouts for this feature.

The primary research sources are:

- [Face Inset guide](https://developers.snap.com/lens-studio/features/ar-tracking/face/face-inset) —
  product behavior and controls: source face region, inner/outer border radius, subdivision count,
  source scale, offset, horizontal/vertical flipping, material blend mode, alpha, and mask texture.
- [FaceInsetVisual API](https://developers.snap.com/lens-studio/api/lens-scripting/classes/Built-In.FaceInsetVisual) —
  the programmatic model behind Face Inset, including `faceRegion`, `faceIndex`, `sourceScale`,
  `subdivisionsCount`, `innerBorderRadius`, `outerBorderRadius`, and flip controls.
- [Face Effects overview](https://developers.snap.com/lens-studio/features/ar-tracking/face/face-effects-overview) —
  distinguishes copied-region Face Inset from Face Liquify, Face Stretch, Face Mask, and Face Mesh.
  That distinction is why V1 is a compositor rather than a deformation shader.
- [Tracking Scope](https://developers.snap.com/lens-studio/features/ar-tracking/tracking-scope) —
  demonstrates that Face Inset can operate on a photo or video selected from the camera roll, not
  only a live camera feed. This is the closest reference for Enhance's still-photo workflow.
- [Distort template](https://developers.snap.com/lens-studio/features/ar-tracking/face/face-templates/distort) —
  documents local Face Liquify points that bulge or pucker regions. This is research for a later
  Scrambler version, not part of the V1 copied-region implementation.
- [Face Mesh template](https://developers.snap.com/lens-studio/4.55.1/references/templates/face/face-mesh) —
  includes an extrusion example made by duplicating a face mesh. It informs the follow-on Face
  Extrude idea but is not required for Scrambler V1.

### What the Snap examples imply technically

The visual trick is not a sticker overlay. It is a live sample from the original face texture,
bounded by a soft mask, transformed into a new position, and composited back onto the face. The
mask and sampled image must share the same coordinate transform or their edges separate during
scale and rotation.

Snap exposes two border concepts:

- **Outer border radius** controls how much source area surrounds the copied feature.
- **Inner border radius** controls the transition from fully opaque feature to feathered edge.

Enhance V1 does not expose either border as a control. Stage A tunes **padding** and **feather
width** independently against encoded GIF output, then ships them as separate internal constants.
This preserves Snap's distinction and leaves both values exposable later without rewriting the
mask builder.

Snap's subdivision setting reflects the fact that the copied region is represented as deformable
geometry rather than only a rectangular crop. Enhance can approximate the same visible boundary
with an elliptical or landmark-polygon mask in V1. If rotation or profile faces expose the
approximation, the next step is a triangulated 2D region mesh — not an arbitrary increase in mask
blur.

### Source-to-Enhance mapping

| Snapchat Face Inset concept | Enhance implementation | V1 decision |
|---|---|---|
| Camera/screen texture | Immutable `CIImage` received by `FaceEffect.apply` | Every placement samples this original input |
| Face Region | `FaceRegion` resolving Vision landmark polygons | Left eye, right eye, and mouth |
| Face Index | Existing selected face and `selectedFaceIndex` | One target face at a time |
| Original Face Index | Separate source face from target face | Deferred to Identity Shuffle |
| Inner Border Radius | Opaque core of the alpha mask | Tuned internal feather-width constant |
| Outer Border Radius | Padded source bounds and mask falloff extent | Tuned internal padding constant |
| Source Scale | Region-local affine scale | Driven by SIZE and layout defaults |
| Offset | Source and destination center offsets | Fixed per layout in V1 |
| Flip X / Flip Y | Negative local transform scale | Used by presets only if visual testing justifies it |
| Inset rotation | Region-local affine rotation | Fixed per layout; no V1 control |
| Subdivision Count | Mask/mesh boundary resolution | Ellipse or landmark polygon first; mesh if needed |
| Material Alpha | Mask opacity | Driven by INTENSITY |
| Blend Mode | Core Image blend/composite filter | Normal alpha blend by default; prototype alternatives |
| Mask Texture | Generated finite `CIImage` alpha mask | Built from landmarks; no bundled face texture |
| Tracking Scope for imported media | Vision detection on the selected `UIImage` | Native to Enhance's existing flow |

### Intentional differences from Snapchat

- Enhance operates on a still source and generates a deterministic GIF; it does not follow live
  expressions or head pose.
- Placement animation is driven by GIF progress rather than camera-frame tracking.
- V1 offers one curated THIRD EYE layout instead of a freeform Face Inset editor. Additional
  curated layouts are a separately gated follow-up.
- V1 uses Vision's 2D landmarks and Core Image rather than Lens Studio's tracked face geometry and
  material system.
- Normal alpha compositing is the shipping baseline. Multiply, Overlay, and Soft Light are
  research candidates, not assumed defaults.
- Enhance's final target is a 600×600, 256-color GIF. Mask edges must be judged after GIF encoding,
  not only in a full-color live preview.

### Claims we cannot make from the public research

Snap does not publish the internal source code for Face Inset. The public guides describe the
behavior and property surface, not the precise sampling, tessellation, antialiasing, or mask
implementation. Consequently:

- Do not label Enhance's Core Image implementation as a direct port.
- Do not copy property ranges unless the public API documents them.
- Treat matching screenshots as visual validation, not proof of algorithmic equivalence.
- Record every deviation made for GIF legibility or the existing editor's control budget.

---

## Product goals

1. The result should read immediately at effect-card size and after GIF palettisation.
2. Copied features must remain attached to the face throughout zoom, pan, Shake, and Spiral.
3. The final pause frame must be crisp and deterministic.
4. The effect must tolerate partial or estimated landmarks without crashing or exposing hard crop
   edges.
5. The implementation should create reusable face-region extraction and compositing primitives
   for future effects such as Galaxy Eyes, Identity Shuffle, Riso Makeup, and Face Portal.

## Non-goals for V1

- MOUTH EYES, EYE MOUTH, SHUFFLE, and a layout picker; these belong to the follow-up layout pack.
- Dragging features directly on the canvas.
- Arbitrary user-created arrangements.
- Copying features between different people.
- Live-camera expression tracking.
- 3D face-mesh deformation.
- Balloon, cube, or liquify geometry.
- Animal-specific layouts. Estimated animal faces should fall back conservatively rather than
  receiving a mouth-based layout with unreliable geometry.

---

## User experience

### Picker

Add `SCRAMBLE` to the face-effect carousel. Its thumbnail should use **THIRD EYE**, which remains
legible at small size and needs only one reliable eye region.

Like RAINBOW and HEART VIGNETTE, SCRAMBLE requires a single selected face. When multiple faces are
detected, selecting the effect should use the existing face-selection interaction.

### Detail panel

V1 exposes two rows:

| Control | Type | Default | Meaning |
|---|---|---:|---|
| INTENSITY | slider | 0.75 | Final opacity and exaggeration of the placement |
| SIZE | slider | 0.5 | Scale of the copied eye relative to its source size |

Padding and feather are tuned constants, not V1 controls. The current `parameters.count <= 5`
assertion is a declaration cap, not a short-device layout guarantee. With the current 34pt row
floor, a four-row panel needs roughly 234pt on an iPhone SE 3 but receives only about 190–200pt.
That overflow re-enables scrolling, whose gesture then competes with the sliders. Two V1 rows fit
without introducing that failure mode.

The follow-up layout pack adds a third `LAYOUT` row. It must use a general preset/enum parameter
kind rather than a Scrambler-only branch in `EditorView`; the same control will be useful for
Pixelate shape and Hatching style.

### Missing landmarks

- If only one eye is usable, V1 THIRD EYE uses that eye.
- If neither eye is usable, SCRAMBLE is unavailable for that face.
- The effect must no-op safely if a landmark disappears between preview preparation and export.

The follow-up layout pack must not assume that `EffectDetailPanel` or `ParameterPickerRow` can
show disabled choices or explanatory copy; neither affordance exists today, and extra text would
consume the same constrained panel height. Its smallest viable behavior is:

- With precise lip landmarks, show all layouts.
- Without precise lips, show only THIRD EYE.
- If changing the selected face makes the stored layout unavailable, normalize the visible typed
  selection to THIRD EYE before rendering. Do not preserve a hidden invalid layout.

---

## Visual behavior

### Region treatment

Copied features should look like pieces of the original photograph, not stickers:

- Sample from the unmodified input passed into `FeatureScramblerEffect.apply`.
- Preserve the source feature's original color and texture.
- Use an elliptical or landmark-derived alpha mask with a tuned feather.
- Slightly enlarge the mask beyond the landmark bounds so eyelashes and lip edges are retained.
- Transform the sampled image and its mask identically.
- Composite every placement from the same original input. Later placements must not sample an
  earlier placement and recursively duplicate it.

### Animation

The animation is a timeline-driven reveal, not perpetual motion:

1. `0.00...0.15` — original image unchanged.
2. `0.15...0.75` — the copy travels from its source center to the forehead while scaling from
   roughly 0.65 to its final size with one simple eased settle.
3. `0.75...1.00` — stable final arrangement.

Use a deterministic easing function based on `progress`. Do not use frame-rate-dependent state or
unseeded randomness. `frameIndex` is unnecessary for V1. Avoid a multi-oscillation spring: at 4×
speed the generator emits its 12-frame floor, leaving only about seven frames in the reveal window.

The intended behavior is tied to normalized GIF time, not instantaneous zoom scale:

- ZOOM IN assembles the eye as the camera moves toward the subject.
- ZOOM OUT assembles it as the camera pulls away.
- PULSE assembles it monotonically across the pulse cycle rather than reversing with scale.

Stage A must judge all three explicitly at the 12-frame fast-speed floor. Pause-frame stability
needs no Scrambler mechanism: `GIFGenerator` renders the final face-effected image once and appends
that same image for every pause frame.

### Placement geometry

All placements are derived from face-relative coordinates so they scale across resolutions:

- **Forehead:** face center X; Y between the eyebrows and top of the face bounding box.
- **Source eye:** prefer the more complete precise eye polygon; fall back to the available pupil
  and eye width.

The follow-up layouts add eye destinations, a mouth destination derived from the outer-lip
centroid, and swapped-eye destinations. They are not V1 geometry requirements.

Destination offsets and sizes should be expressed as fractions of `faceWidth`, `faceHeight`, or
the source region bounds. Avoid absolute pixel values except for a final one-pixel mask safety
margin.

---

## Landmark model changes

`DetectedFace` currently retains pupil centers, eye widths, eyebrow points, and contour points,
but discards the full eye and lip regions already returned by Vision. Introduce a grouped model
instead of continuing to add unrelated flat fields:

```swift
struct FaceRegions {
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    var outerLips: [CGPoint]
    var innerLips: [CGPoint]
    var nose: [CGPoint]
}

enum LandmarkQuality {
    case precise
    case estimated
}
```

Add `regions: FaceRegions` and `landmarkQuality: LandmarkQuality` to `DetectedFace`. Keep the
existing pupil, eyebrow, and contour properties during this feature so current effects do not
need to migrate at the same time.

### Detection paths

- **Vision landmarks:** retain `leftEye`, `rightEye`, `outerLips`, `innerLips`, and `nose` via the
  existing `convertPoints` helper. Mark `.precise`.
- **Vision rectangle fallback:** provide empty regions and mark `.estimated` initially. Do not
  pretend proportional rectangles are precise facial regions.
- **CIDetector fallback:** populate eye centers as today; keep regions empty unless a real region
  is supplied. Mark `.estimated`.
- **Animal detection:** mark `.estimated` for V1. THIRD EYE may work when a pupil and eye width are
  credible; mouth layouts remain unavailable.

Update `DetectedFace.scaled(x:y:)` to scale every new region. A dedicated test must enumerate all
stored coordinates so a future field cannot be forgotten silently.

---

## Reusable rendering primitives

Add these types under `Services/Animators/FaceRegions/` (names are recommendations, not API
contracts):

### `FaceRegion`

An enum describing the logical source region:

```swift
enum FaceRegion {
    case leftEye
    case rightEye
    case mouth
}
```

It resolves to a polygon, bounds, center, and availability from a `DetectedFace`.

### `FaceRegionMaskBuilder`

Build a finite grayscale `CIImage` mask for a region.

V1 may use a transformed elliptical mask fitted to the landmark bounds. A polygon mask is a later
quality improvement if the ellipse includes too much surrounding skin. The mask builder owns:

- Region padding.
- Feather mapping.
- Finite extents.
- Safe behavior for empty and degenerate polygons.

### `FaceRegionCompositor`

Given an input image, region, destination center, scale, rotation, opacity, and feather:

1. Resolve and pad source bounds.
2. Clamp the source before sampling near image edges.
3. Crop the source image and mask to the same finite extent.
4. Translate them to a local origin.
5. Apply the identical scale/rotation transform to both.
6. Translate both to the destination.
7. Composite with `CIBlendWithAlphaMask`.
8. Crop the result to the original input extent.

The compositor should return the original image when the region is unavailable or any extent is
non-finite. It must not create a `CIContext` or call `createCGImage`; rendering stays lazy until
the existing shared context evaluates the completed graph.

---

## Effect integration

### New types

- `FeatureScramblerEffect: FaceEffect`
- `FaceFilterType.scramble = "SCRAMBLE"`

`FeatureScramblerEffect` receives resolved immutable options in its initializer:

```swift
init(
    size: Double,
    intensity: Double
)
```

Padding and feather remain separately named constants chosen in Stage A. The effect creates the
THIRD EYE placement instruction, interpolates it from source to destination using progress, then
sends it to `FaceRegionCompositor`.

The follow-up layout pack adds `ScrambleLayout: String, CaseIterable` and makes the placement list
layout-dependent.

### Parameter plumbing

V1 fits the current face-effect factory without adding positional arguments:

- Reuse `EffectParameter.intensityID` for INTENSITY.
- Reuse `EffectParameter.secondaryID` for SIZE, matching every current two-control face filter.

Do **not** introduce Scrambler-specific `"intensity"` or `"size"` literals, and do not use
`EffectParameter.sizeID` without a deliberate migration: the current face-filter convention and
tests reserve `sizeID` for visual effects and route the face filter's second slot through
`secondaryID`.

The follow-up layout pack must follow the codebase's established typed-state pattern for
nonnumeric values:

- `var scrambleLayout: ScrambleLayout = .thirdEye` on `EditorViewModel`.
- `let scrambleLayout: ScrambleLayout` on `EditorSnapshot`.
- Capture it in `currentSnapshot`, restore it in `restore`, and reset it in `resetEffects`.
- `EffectParameter.Kind` only tells the view to draw a preset row; layout does not belong in
  `parameterValues: [String: Double]`.

Never encode layout as a numeric case index. Reordering `ScrambleLayout.allCases` would silently
reinterpret existing state. If layouts are persisted in the future, persist the enum's stable raw
value.

### Multiple faces

Set `requiresSingleFace` for SCRAMBLE. The generator should receive only the chosen target face,
matching current single-face effects. Cross-person source sampling is deliberately deferred.

### Preview and export

Use the same `FeatureScramblerEffect` for:

- Face-card thumbnails at final progress.
- The editor preview.
- Generated GIF frames.

No SwiftUI-only shader implementation is permitted. Preview/export mismatches would be especially
obvious when copied features land in different positions.

---

## Delivery stages

### Stage A — Visual proof

- Capture reference images from Snap's published Face Inset examples for THIRD EYE and MOUTH EYES.
  Keep source URLs and capture dates beside the local research artifacts.
- Build a disposable Core Image prototype using fixed rectangles on one known portrait.
- Prove crop → mask → transform → composite produces convincing edges.
- Compare ellipse and landmark-polygon masks against the visible boundary treatment in the Snap
  examples. Do not claim pixel parity; compare crop shape, feather behavior, and feature scale.
- Test padding and feather independently, reflecting Snap's separate outer and inner border
  controls.
- Test source scale, offset, horizontal flip, and rotation even if some remain preset-only in V1.
- Compare Normal, Multiply, Overlay, and Soft Light compositing on skin. Ship Normal unless another
  mode produces consistently cleaner integration without altering the copied feature's identity.
- Render through GIF encoding to confirm feathering survives the 256-color palette.
- Choose final V1 padding and feather constants from the rendered output, not the live preview.
- Record a short parity worksheet for THIRD EYE and the exploratory MOUTH EYES prototype:
  reference behavior, Enhance result, deliberate differences, unresolved differences, and chosen
  parameter defaults.

**Gate:** THIRD EYE and MOUTH EYES reproduce the recognizable Face Inset behavior, read cleanly in
a 600×600 GIF without rectangular seams, and have every deliberate difference recorded.

### Stage B — Landmark groundwork

- Add `FaceRegions` and `LandmarkQuality`.
- Retain Vision eye, lip, and nose points.
- Update every constructor and scaling path.
- Add model and coordinate-conversion tests.

**Gate:** precise regions align with a rendered landmark debug overlay on upright, rotated, and
mirrored photos.

### Stage C — Reusable compositor

- Implement region resolution, mask building, and compositing.
- Add finite-extent and missing-data guards.
- Verify lazy rendering through the shared `CIContext`.

**Gate:** colored-fixture tests prove pixels came from the requested source region and landed at
the requested destination.

### Stage C2 — Generation performance prerequisite

Fix or materially reduce the existing full-resolution render in
`GIFGenerator.faceEffectedSource` before integrating SCRAMBLE into the product flow. At 0.25×,
the current duration/frame-delay formula produces 100 animation frames, so a face effect can force
roughly 100 full-resolution `createCGImage` evaluations before pause handling. Scrambler's lazy
composites would be added inside each of those renders.

- Downscale or otherwise normalize the face-effect source to the resolution actually needed by
  the 600×600 output before applying the effect.
- Preserve landmark alignment by scaling `DetectedFace` through its centralized `scaled(x:y:)`.
- Benchmark a no-face-effect GIF and at least one existing face effect before and after the change.
- Re-run visual extent and face-placement tests; performance work must not shift landmarks.

**Gate:** 0.25× no longer performs full-source-resolution face renders for every one of its 100
animation frames, and existing face effects remain visually aligned.

### Stage D — THIRD EYE vertical slice

- Add the enum case, effect factory wiring, card thumbnail, INTENSITY, and SIZE.
- Ship tuned padding and feather as constants from Stage A.
- Add SCRAMBLE to the literal face-label parity table in `EffectParameterTests` and keep the
  existing `secondaryID` convention.
- Verify single-face selection, undo/redo, reset, regeneration, save, and re-edit behavior.

**Gate / V1 ship boundary:** THIRD EYE works through the full product flow with two rows and no
layout-specific UI.

### Stage D2 — V1 device and performance verification

- Test at 0.25×, 0.5×, 1×, and 4× playback.
- Test Zoom In, Zoom Out, Pulse, Shake, and Spiral.
- Test front-facing, profile, partially occluded, glasses, small-face, multi-face, and animal
  photos.
- Measure generation time with the selected face. SCRAMBLE is single-face, so several detections
  should not multiply rendering work.
- Inspect GIFs in Photos, Messages, and the in-app gallery.

**Gate / V1 release:** no visible crawling, crop seams, black borders, stale preview, or
short-device gesture regression; all V1 acceptance criteria are satisfied.

### Stage E — Follow-up layout pack

- Add the reusable enum/preset parameter row.
- Implement MOUTH EYES, EYE MOUTH, and SHUFFLE.
- Add the dedicated typed `scrambleLayout` property and `EditorSnapshot` field; capture, restore,
  reset, and undo it explicitly.
- Filter the preset row to available layouts; do not add explanatory copy until the panel has a
  designed, height-budgeted affordance for it.
- Update `faceFilter_onlyLazerEyesDeclaresAPicker`. A new non-slider `.preset` kind counts as a
  picker under that test, so its expected picker owners become LAZER EYES and SCRAMBLE.
- Add a short-device assertion for the actual three-row layout. Do not treat the five-parameter
  declaration cap as proof that the panel fits.
- Repeat Stage D2's device matrix for every layout, including the 12-frame floor.

**Gate:** switching layouts creates one undo entry per confirmed panel visit and never discards a
layout-specific value during regeneration; all layouts pass device verification and the panel
remains non-scrolling on iPhone SE 3.

---

## Test plan

### Model and detection

- Vision regions convert from normalized face coordinates into CIImage coordinates correctly.
- Mirrored and rotated images preserve left/right placement as shown to the user.
- `DetectedFace.scaled` scales every pixel-coordinate region point and deliberately leaves
  `normalizedBoundingBox` unchanged because it is already resolution-independent.
- Estimated faces report missing precise regions honestly.

### Rendering

- Zero progress returns the original image unchanged.
- THIRD EYE preserves input extent; Stage E adds the same assertion for every layout.
- Empty, one-point, zero-area, and out-of-bounds regions safely no-op.
- A source feature near the image edge does not create transparent or black seams.
- Every placement samples from the original input rather than an earlier composite.
- Final output is deterministic for identical inputs.
- Intensity zero is visually identical to the input.

Use a diagnostic fixture with uniquely colored eye and mouth regions. Solid-white fixtures only
prove that rendering succeeded; they cannot prove the correct feature was copied.

### State and UI

- SCRAMBLE participates in `FaceFilterType.allCases` output tests.
- V1 size and intensity round-trip through undo/redo using the existing numeric parameter store.
- Cancel restores the entry snapshot; confirm keeps one undo entry.
- Reset clears SCRAMBLE and all of its parameter values.
- Multi-face photos require an explicit selected face.
- Stage E adds separate typed-state tests proving `scrambleLayout` is captured, restored, reset,
  and normalized when a newly selected face cannot support a mouth layout.
- Stage E updates the existing picker-ownership assertion and verifies the three-row panel stays
  non-scrolling at the iPhone SE 3 height.

### Visual QA

Inspect, do not only assert:

- Feathering against light and dark skin, facial hair, glasses, and high-contrast makeup.
- Small thumbnails and 600×600 export.
- GIF palettisation around soft mask edges.
- The full zoom, not only the final frame.
- THIRD EYE on faces near all four image edges; repeat for all layouts in Stage E.

---

## Performance budget

V1 adds a lazy crop, transform, mask, and composite per frame. It should still render through one
`CIContext` evaluation per output frame.

Initial target on supported physical hardware:

- THIRD EYE: no more than 15% slower than a no-face-effect GIF.
- Stage E MOUTH EYES / SHUFFLE: no more than 30% slower.
- No additional full-resolution `createCGImage` call inside the effect.
- No per-frame `CIContext`, `CGContext`, or random-number generator construction.

These are provisional gates. Record the device and source resolution with every measurement. The
existing full-resolution `GIFGenerator.faceEffectedSource` issue is a Stage C2 prerequisite, not a
late benchmarking caveat.

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Rectangular or haloed crop edges | Overscan the source region; transform the mask identically; tune feather after GIF export |
| Left/right eyes swap on mirrored photos | Test oriented and mirrored fixtures through the actual Vision orientation path |
| Features drift during zoom | Keep Scrambler in the pre-zoom `FaceEffect` pipeline |
| Profile faces provide only one eye | V1 THIRD EYE uses the available eye; Stage E filters mouth layouts by landmark availability |
| Estimated landmarks create uncanny mouth copies | Stage E exposes mouth layouts only with precise lip landmarks |
| Repeated composites become expensive | Keep the graph lazy, cap V1 placements, render once, benchmark on device |
| A four-row panel overflows on short devices | V1 ships two rows; Stage E has three; feather remains a tuned constant |
| Layout has no valid numeric storage | Stage E uses a dedicated typed view-model property and snapshot field |
| New picker kind breaks picker-ownership test | Update the explicit expected owners in Stage E |
| Soft alpha breaks under GIF quantisation | Validate encoded GIFs and provide a minimum feather that survives palettisation |
| Face selection changes during editing | Treat target-face selection as part of the effect snapshot and regeneration input |

---

## Acceptance criteria

Feature Scrambler V1 is ready to ship when:

1. THIRD EYE works on a clear, front-facing human face and degrades gracefully to one visible eye.
2. Copied regions have no rectangular seams in the exported GIF.
3. The feature remains attached during every zoom and modifier combination.
4. Its timeline reveal reads deliberately in Zoom In, Zoom Out, and Pulse at the 12-frame floor.
5. Preview, thumbnail, final frame, and exported GIF agree on placement.
6. The detail panel has only INTENSITY and SIZE and remains non-scrolling on iPhone SE 3.
7. Undo, cancel, confirm, reset, save, and re-edit behave like existing effects.
8. The effect preserves input extent and never creates a context or forces rendering internally.
9. Stage C2's face-effect generation prerequisite is complete.
10. The suite is green and visual QA has been completed on a physical device.
11. The reusable face-region compositor is documented well enough to support the next effect
    without copying Scrambler-specific code.

The Stage E layout pack has its own ship gate: all four layouts work on precise landmarks, layout
state round-trips through `EditorSnapshot`, unavailable layouts normalize visibly to THIRD EYE,
the picker-ownership tests are updated, and the three-row panel remains non-scrolling on the
shortest supported device.

---

## Follow-on opportunities

Once V1 is stable, the same infrastructure can support:

- **IDENTITY SHUFFLE** — copy regions between different faces in one photo.
- **FEATURE SWARM** — orbit multiple eye or mouth copies around the face.
- **FACE PORTAL** — render a transformed image inside the contour mask.
- **RISO MAKEUP** — apply print patterns to precise face regions.
- **GALAXY EYES** — replace eye regions with procedural animated materials.
- **FREEFORM SCRAMBLE** — drag copied regions on the canvas and persist normalized placements.
- **LOCAL WARP** — add a bounded Metal Core Image kernel for melting or stretching a copied
  region after placement.

Cross-person copying should be designed before freeform persistence: source face identity,
missing faces during re-edit, and saved landmark coordinates all become durable data concerns.
