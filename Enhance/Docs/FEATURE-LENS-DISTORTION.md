# Lens Distortion — analysis and implementation plan

> Status: proposed. No production code written.
>
> Scope: a new effect available in **both** the IMAGE and FACE carousels, delivered as a
> reference port of a Figma shader plus a separate Enhance interpretation.

---

## 1. Executive recommendation

Build it as a **graph of stock Core Image filters**, centred on **three `CIZoomBlur` passes —
one per colour channel, at slightly different amounts** — additively recombined. Do **not**
write a `CIKernel`.

That single choice collapses most of the risk. The observed effect is radial prismatic
streaking from a centre point; `CIZoomBlur` produces exactly that streak, and running it three
times at different strengths with the channels isolated produces the dispersion. The whole
effect is roughly eight nodes of stock filters, needs no Metal, and therefore does **not**
depend on the unbuilt Phase 17e kernel infrastructure — which is still the highest-risk change
in the project (the `-fcikernel` build rule would break the animated canvas border at runtime).

Build **one** `VisualEffect`. The face variant is then nearly free: `FaceVisualEffect`
(`Enhance/Services/Animators/FaceVisualEffect.swift`) already wraps any `VisualEffect` into a
`FaceEffect` by passing the face centre as `viewportCenter` and masking to the face region.
Six effects already ship in both carousels this way. A radially-centred effect is precisely the
shape that adapter expects.

Ship the **Enhance interpretation** as V1. The reference port is worth building as a throwaway
comparison fixture in Stage A, not as a shipped effect — see §7 for why.

---

## 2. Evidence summary

Obtained via the Figma MCP against `c6pLcnIn0n4OaAP3sa5TGF`, node `10200:4079`
("Shader Lab — IMG_1189 4 shader", generated 2026-08-09, seed 42).

**Tier 1 — shader source: NOT AVAILABLE.** The harness states this explicitly: *"Shader source
code is not available through the API."* Everything below about the algorithm is therefore a
**reconstruction from observed behaviour**, not the Figma implementation.

**Tier 2 — manifest metadata (authoritative):**

| Property ID | Type | Baseline | Harness "test range" |
|---|---|---:|---|
| `2769778894:1953405588` | NUMBER | 0 | 0.00…1.00 |
| `3216598804:1724965754` | NUMBER | 0.52 | 0.00…1.04 |
| `3600999727:2801904102` | NUMBER | 0.37 | 0.00…1.00 |
| `3889330245:2626552154` | POINT | `{x:50, y:50}` | swept `{0…1, 0…1}` |
| `3928918749:705940456` | NUMBER | 1 | 0.00…2.00 |

Property names are opaque numeric IDs — Figma exposes no semantic labels. **Every
`constraintSource` is `"assumed"`**: the ranges are the harness doubling each baseline, not API
constraints. Test sections: baseline, sweeps, resolution (256/600/1024), aspect (1:1, 3:5, 5:3),
spatial translation, and an 8-frame "animation" strip that merely sweeps property 1.

**Tier 3/4 — rendered images.** I downloaded the renders and measured them numerically rather
than eyeballing thumbnails (disc extent along centre lines, chroma = max−min RGB by radial band,
pairwise max/mean pixel difference).

---

## 3. Reconstructed effect pipeline

Stages, in observed order:

1. **Radial coordinate transform** about a centre point, in normalized UV.
2. **Per-channel radial displacement** — R, G and B sampled at different radial scales,
   accumulated along the radius. This is what produces streaks rather than a simple fringe.
3. **Radial falloff mask** — a smooth ramp that decides how far from the centre the dispersion
   reaches.
4. **Slight overall scale** of the sampled image, leaving the frame edge uncovered.
5. **Composite** back to the frame; uncovered area shows the backdrop.

Measured behaviour of each property:

| Property | Reconstructed meaning | Evidence |
|---|---|---|
| `1953405588` | **Dispersion strength.** Radial rainbow streaking from the centre. | At 0: fringing confined to the edges, centre sharp. At 1: the photo is unreadable, replaced by radial rainbow streaks. Centre chroma 40→67; disc 246→234 px. |
| `1724965754` | **Zoom / scale.** Higher shrinks the image. | At 1.04 the visible disc drops to 215/256 px from 246; chroma collapses to 0 by band 5 instead of band 7. |
| `2801904102` | **Effect reach / falloff radius.** | At 1 the corner pixel changes from neutral grey `(68,68,68)` to saturated yellow `(212,203,81)`, and corner chroma rises from 7 to 143 — the aberration now fills the frame. |
| `2626552154` | **Centre point** of the radial transform. | POINT type; swept across the corners. |
| `705940456` | **Inert in this configuration.** | Across its whole assumed 0→2 range, max pixel difference **6**, mean **0.40** — render noise. Real parameters move 176–243 max / 16–39 mean. |

**Coordinate space and anchoring — measured, not assumed:**

- **Resolution-invariant.** Same parameters at 256² and 1024²: disc 0.961 vs 0.965 of width;
  chroma-by-radius profiles agree within 2% across a 4× resolution change. So the effect is
  **normalized UV**, with no pixel-absolute term.
- **Anchored to the output frame, following its aspect.** Portrait 360×600 → disc spans 98.3% of
  width, 94.3% of height. Landscape 600×360 → exactly mirrored. The short edge always gets
  98.3%, the long edge 94.3%. So the pattern is **elliptical on non-square frames** — it is not
  aspect-corrected to a true circle, and it is not anchored to the source image.
- **Edges are not covered.** The disc reaches ~96% of the frame; the remainder shows backdrop.
  Alpha is **255 everywhere** in the exports, so the surround is opaque grey from the harness
  frame, not transparency — the shader's own edge behaviour cannot be determined from these
  renders.

---

## 4. Known facts vs hypotheses

**Known (tiers 2–4):** property count, types, baselines; that ranges are assumed rather than
declared; resolution invariance; frame anchoring and aspect-following; that `1953405588` is a
dispersion amount, `1724965754` a scale, `2801904102` a reach; that `705940456` is inert; that
the effect leaves frame edges uncovered.

**Reconstructed (tier 6 — my hypotheses):** that dispersion is implemented as accumulated
per-channel radial samples; the exact falloff curve; the sample count; the per-channel IOR
ratios; the blend used to recombine channels.

**Not determinable from this evidence:**
- Whether the effect animates. The harness says *"animation cannot be evaluated
  programmatically"*, and the "animation strip" only sweeps property 1 — it is **not** evidence
  of built-in motion.
- True parameter ranges. Every one is assumed.
- What `705940456` does. It may be gated behind a mode this fixture never enables.
- Genuine edge sampling (clamp / mirror / transparent), because the harness backdrop is opaque.

---

## 5. Recommended iOS rendering approach

**Chosen: a graph of stock Core Image filters.**

```
centre c (normalized → image coords)

R = CIZoomBlur(input, center: c, amount: a * 1.00)  → CIColorMatrix keep R
G = CIZoomBlur(input, center: c, amount: a * 0.62)  → CIColorMatrix keep G
B = CIZoomBlur(input, center: c, amount: a * 0.30)  → CIColorMatrix keep B
sum = CIAdditionCompositing(R, G) then with B
out = CIBlendWithMask(sum, background: input, mask: CIRadialGradient(c, r0, r1))
      .cropped(to: input.extent)
```

Why this and not the alternatives:

- **Single stock filter** — nothing in the catalog does radial dispersion alone.
- **`CIKernel`** — rejected. It would gate the effect behind unbuilt Phase 17e infrastructure
  and its runtime build-rule hazard, to reproduce something three `CIZoomBlur`s already give.
  The reference being "a shader" is not a reason to write one.
- **Direct Metal** — rejected outright. Nothing here needs cross-pixel dependency or compute.

The differing per-channel `amount` is what turns three identical zoom blurs into dispersion.
`CIRadialGradient` + `CIBlendWithMask` gives the reach control (`2801904102`) with a smooth
falloff and no extra sampling. **`CIZoomBlur` grows its extent**, so the final `.cropped(to:)`
is mandatory — this is the exact failure that produced a black band above the canvas for
FISHEYE, SWIRL and PIXELATE (LEARNINGS 2026-08-08).

---

## 6. Reference-port specification

Purpose: a Stage A comparison fixture only. Four controls mirroring the observed properties —
dispersion, scale, reach, centre — over the harness's assumed ranges, rendered against the same
photo at 256/600/1024 and 1:1/3:5/5:3, and diffed against the downloaded reference PNGs with the
same numeric method used in §3.

Two reference behaviours are deliberately **preserved** here and **dropped** in §7:

- **Frame-aspect ellipticity.** Faithful, but wrong for Enhance, whose canvas and GIF output are
  both square — so it is unobservable in the product anyway.
- **Uncovered frame edges.** Faithful, but in Enhance an uncovered edge is the black-band bug.

`705940456` is **not** ported. Reproducing a control with no measurable effect would be
reproducing a bug.

---

## 7. Enhance-specific variant (the one to ship)

What changes, and why:

| Change | Reason |
|---|---|
| **Drop the scale/zoom control** (`1724965754`) | Zoom is the app's central concept. A second, competing zoom inside an effect panel is confusing, and it is the parameter most likely to fight the animator. |
| **Drop the centre control** (`2626552154`) | Resolved automatically: `viewportCenter` for the image variant, the detected face centre for the face variant via `FaceVisualEffect`. This is exactly what FISHEYE and SWIRL already do. |
| **Drop `705940456`** | Inert. |
| **Full-frame coverage** | The reference lets edges fall away. Enhance must `.cropped(to: input.extent)` and keep the source as the blend background so no uncovered pixel can ever exist. |
| **Dispersion driven by zoom progress** | See §10. The reference is static; Enhance's signature is motion. |
| **Face variant masked to the face** | Free via the existing adapter. |

Result: **two sliders**, AMOUNT and REACH, which sits inside the real layout budget (§11).

---

## 8. Parameter table

| Label | Stable ID | Type | Default | Range | Mapping | Cost | Evidence | Budget |
|---|---|---|---:|---|---|---|---|---|
| AMOUNT | `EffectParameter.intensityID` (`intensity`) | slider | 0.5 | 0…1 → `CIZoomBlur` amount 0…~40px equivalent at 600² | **Geometric** — dispersion reads perceptually as a ratio, and the observed jump from "edge fringe" to "unreadable" across 0→1 is strongly non-linear | Regenerates on commit only | Sweep of `1953405588`; centre chroma 40→67, disc 246→234 | 1 row |
| REACH | `EffectParameter.sizeID` (`size`) | slider | 0.4 | 0…1 → radial-gradient `r0/r1` from a tight centre disc to full-frame | **Linear** — the observed corner-chroma response (7→143) is smooth | Regenerates on commit only | Sweep of `2801904102`; corner grey→yellow | 1 row |

Two genuinely independent qualities, deliberately not collapsed into one INTENSITY: strength and
reach were separately controllable in the reference, and REACH is what distinguishes a subtle
edge fringe from a full-frame prismatic wash.

**Spatial point: omit the control.** Automatic placement from the existing focal point is
strictly better here — the image variant already receives `viewportCenter`, and the face variant
receives the face centre. Direct manipulation is a new interaction concept the panel does not
have; presets would be arbitrary. Revisit only if users ask.

**No picker row**, so the one-picker budget is untouched, and no new `EffectParameter.Kind` is
needed — which also avoids updating `faceFilter_onlyLazerEyesDeclaresAPicker`.

---

## 9. Coordinate, colour-space and edge-handling rules

- **Coordinates:** normalized UV internally, resolved against `image.extent` at apply time.
  Matches the measured resolution invariance, and means preview (650px) and GIF (600px) agree
  with no scale compensation.
- **`FrameGeometry` is NOT required.** This is the interesting case: image effects are applied
  *post*-zoom to the output frame, which is why DITHER needed both `scale` and `contentOrigin`
  to stop crawling. But a lens aberration is **physically anchored to the lens, not the
  subject** — staying locked to the frame as the zoom pushes in is correct, not a bug. So the
  default `VisualEffect` overload (no geometry) is right, and this should be stated in the doc
  comment so nobody "fixes" it later.
- **Colour space:** the `CIContext` working space is **linear sRGB**. Dispersion here is
  *multiplicative and channel-selective* (`CIColorMatrix` masks, `CIZoomBlur` sampling), all of
  which are space-robust. **Do not** add an additive brightness or contrast term to sell the
  effect — that is the trap that made the retired brightness adjustment barely darken anything
  (LEARNINGS 2026-08-07).
- **Edges:** `CIAffineClamp` the input before the zoom blurs so radial sampling near the border
  has data, then `.cropped(to: image.extent)` at the end. Never leave an uncovered pixel.

---

## 10. Temporal behaviour

The reference is **static** — and the evidence cannot show otherwise, since the harness cannot
evaluate animation.

For Enhance, the best fit is **revealed by zoom progress, settling into a stable final frame**:
dispersion ramps from 0 toward AMOUNT over the animated frames and holds at the pause. It reads
as the lens straining as the camera pushes in, and it is the same shape as every other effect's
`progress` ramp.

Rejected: *continuously looping* (nothing to loop; would crawl during the pause) and *zoom
velocity–driven* (velocity is not available to `VisualEffect`, and would need the animator's
derivative threaded through — real work for a subtle gain).

**Pause-frame stability is already guaranteed by construction**: `addPauseFrames`
(`GIFGenerator.swift:141`) renders **one** image at `progress: 1.0` and appends it N times, so
identical pause frames need nothing from the effect. The effect must still be deterministic —
no `frameIndex`, no unseeded randomness — so preview, thumbnail and export agree.

---

## 11. Required architecture changes

**Almost none — this is the point of the chosen approach.**

- No new `EffectParameter.Kind`, no picker, no `EditorSnapshot` field, no change to
  `parameterValues` (`[String: Double]` holds both sliders).
- No `CIKernel` infrastructure, no build-rule changes.
- No changes to `FaceEffect`, `DetectedFace`, or the face factory beyond one enum case.

**Layout budget — the one real constraint.** `params.count <= 5` is a *declaration* assertion,
not a layout guarantee. Measured on iPhone SE 3 this session, the panel gets ~190–200pt:

- 3 rows → fits exactly (LAZER EYES today)
- 4 rows → clamps at the 34pt floor, needs ~234pt, **overflows ~40pt**, which re-enables the
  `ScrollView` — and `DragGesture(minimumDistance: 0)` then loses to it, so dragging a slider
  scrolls the panel

Two sliders is comfortably inside that. **Do not add a third control without re-measuring.**

---

## 12. File-by-file implementation plan

| File | Change |
|---|---|
| `Enhance/Services/Animators/LensDistortionEffect.swift` | **New.** `VisualEffect`. Honours `viewportCenter` (falls back to `extent` centre). Ends in `.cropped(to: image.extent)`. |
| `Enhance/Models/VisualEffectType.swift` | Add `case lensDistortion = "LENS"`; `parameters` returns INTENSITY + SIZE (relabelled AMOUNT / REACH); wire the factory. |
| `Enhance/Models/FaceFilterType.swift` | Add `case lensDistortion`; factory returns `FaceVisualEffect(effect: LensDistortionEffect(...), skipDelay: true)`. |
| `EnhanceTests/LensDistortionTests.swift` | **New.** §13. |
| `EnhanceTests/VisualEffectTests.swift` | Picks the new case up automatically via `allCases`. |
| `Enhance/Docs/EFFECTS.md` | Record the reconstruction and the "no `FrameGeometry` by design" rationale. |
| `Enhance/Docs/ROADMAP.md` | Tick, and note the reference-port fixture is disposable. |

No pbxproj edits — `fileSystemSynchronizedGroups`.

---

## 13. Test and visual-verification plan

**Automated:**
- Zero amount is pixel-identical to input; extent preserved at progress `0.0`, `0.5`, `1.0`
  (three values, because effects with delayed ramps are pass-throughs at the endpoints — this is
  how PIXELATE slipped through).
- Deterministic: two applies with identical inputs are byte-identical.
- Endpoints: amount 0 and 1 both render; monotonic — mean chroma rises with amount.
- Off-centre `viewportCenter` still preserves extent (the existing
  `allEffects_preserveInputExtentWithOffsetViewportCentre` covers this once the case is added).
- Portrait, square and landscape inputs all preserve extent.
- Face variant: masked result differs from input only inside the face region.
- **No `FrameGeometry` phase test** — deliberately, since this effect has no spatial grid. Note
  that in the test so its absence reads as a decision.

**Human visual review (cannot be automated):**
- Render to PNG against the rich fixture and *look* — structural tests passed while EDGES was
  cyan and the canvas had a black band.
- Numeric diff against the downloaded Figma references using the §3 method.
- GIF palettisation: smooth radial rainbow gradients are the **worst case** for a 256-colour
  table. Expect banding; inspect an encoded GIF, not the preview.
- Full zoom on device, not just the final frame; then Photos, Messages and the in-app gallery.

---

## 14. Performance risks and measurements

Cost per output frame: **3 × `CIZoomBlur` + 3 colour matrices + 2 composites + 1 masked blend**.
`CIZoomBlur` is a multi-tap filter and the most expensive node here; it also expands its ROI,
so the clamp-then-crop matters for cost as well as correctness.

Budget for a 600×600 GIF: **no more than 25% slower** than the same GIF with no visual effect.

Two project-specific risks:

- **Frame count is now variable.** `frameCount = max(12, Int(1/speed/0.04))`, so 0.25× playback
  produces **100 frames** — every one paying the full graph. Measure at 0.25×, not just 1×.
- **The face variant is worse.** `faceEffectedSource` calls `createCGImage` at full resolution
  **per frame** already. Measure the face variant separately, and fix that pre-existing cost
  before interpreting any Scrambler-style benchmark against it.

Measure before optimizing; record device and source resolution with every number.

---

## 15. Phased rollout with gates

- **Stage A — visual proof.** Throwaway playground: three `CIZoomBlur`s per channel against the
  Figma fixture photo. **Gate:** radial prismatic streaking is recognisably the reference look at
  matched settings, and survives GIF encoding.
- **Stage B — the effect.** `LensDistortionEffect` with AMOUNT and REACH, clamp + crop.
  **Gate:** extent preserved at three progress values; identity at zero.
- **Stage C — image carousel.** Enum case, factory, thumbnail. **Gate:** full product flow —
  select, edit, confirm, undo, reset, regenerate, save, re-edit.
- **Stage D — face carousel.** One line through `FaceVisualEffect`. **Gate:** effect stays locked
  to the face through zoom, Shake and Spiral.
- **Stage E — device + performance.** SE 3 layout, 0.25×/1×/4×, all three animators, palettisation.
  **Gate:** within budget; no banding that reads as broken.

---

## 16. Open product decisions

1. **Does this overlap CHROMA SHIFT too much?** CHROMA SHIFT already ships in *both* carousels
   and is linear-offset chromatic aberration. LENS is radial and streaked — related but
   distinct. Worth looking at them side by side before committing to both.
2. **Name.** "LENS DISTORTION" implies geometry (barrel/pincushion); what this actually does is
   dispersion. `LENS` or `PRISM` may describe it more honestly.
3. **Should AMOUNT ramp with zoom progress, or stay flat?** §10 recommends ramping; flat is more
   faithful to the reference. A judgment call about the app's identity, not a technical one.
4. **Is a two-slider effect too thin** for the drill-down panel, given the panel exists to
   support richer controls?

---

## 17. Explicitly do NOT build

- A `CIKernel` for this effect, or Phase 17e infrastructure as a prerequisite.
- The `705940456` control — inert.
- A user-facing centre control — automatic placement is better and free.
- A user-facing scale/zoom control — it competes with the app's core concept.
- Frame-aspect ellipticity — unobservable on a square canvas and square GIF.
- Uncovered frame edges — that is the black-band bug.
- A `FrameGeometry` implementation — frame-anchoring is correct for a lens.

---

## Appendix — remaining uncertainty and the experiment that resolves it

Only one question would change the design, and it is cheap to answer.

**Does `705940456` do anything under a different configuration?** It was measured inert while
`1953405588 = 0` (dispersion off). It may modulate something only visible once dispersion is
active.

**Experiment:** in Shader Lab, re-run a single sweep of `705940456` over `0, 0.5, 1, 1.5, 2` at
**256×256**, with `1953405588` held at **1.0** (not its baseline 0), `1724965754` at 0.52 and
`2801904102` at 0.37, on the same fixture and seed 42.

**Distinguishing result:** if the five renders again differ by a max of <10 per channel, the
property is inert and §17 stands. If they differ materially, capture which quality moves —
streak count, streak length, or hue separation — since that determines whether it becomes a
third control and forces the three-row layout re-measurement in §11.
