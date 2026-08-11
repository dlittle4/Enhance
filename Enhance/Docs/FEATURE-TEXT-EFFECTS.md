# Animated text overlays — product and implementation plan

> Status: **approved. Stages A–C written but never compiled; D–G not started.**
>
> The headless renderer exists on `feature/text-overlay-renderer` and is unverified — it was
> written without a macOS toolchain, and the repo has no CI. Stage A's gate is that the tile
> partition invariant is *proven* (§12.2), and that gate cannot be met by inspection. **§18 is the
> handoff for the first Xcode session**; §17 is the full file manifest.
>
> **Revision 2 (2026-08-10).** Revision 1 deferred rotation and pinch-to-resize; both are now V1,
> which reopens the gesture-conflict question the first revision answered with a size slider. That
> change cascaded further than expected — into the renderer, the undo contract, and the canvas
> lifecycle — so this is a rewrite rather than an amendment. §2 lists every substantive change and
> the reason for it, including three defects in revision 1 that were found while re-checking it
> against the source.
>
> Scope: let a user add one text overlay to a photo; position, scale and rotate it directly on the
> canvas; style it; and animate its entrance in sync with the existing zoom animation when the GIF
> is generated.

---

## 1. Executive recommendation

Ship a deliberately small first version: **one text layer, five entrance presets, direct
manipulation (drag, pinch, rotate), and a two-phase editor reached from the preset carousel**. Text is anchored to the 600×600
output frame rather than to source-image pixels, so it remains readable while the photo moves
beneath it. Every preset consumes the same normalized `progress` value as the zoom animator,
settles by roughly 70% of the moving portion, and remains fully visible during the pause.

Treat text as its own overlay pass, not as a `VisualEffect`. The current generator has a useful
three-stage order:

1. face effects on the source image;
2. zoom transform and frame crop;
3. visual effects on the transformed frame.

Animated text becomes stage 4. This gives it predictable coordinates, keeps it crisp, prevents
image filters from degrading the lettering, and avoids changing any existing effect protocol.
`applyVisualEffects` already returns a `CGImage` at both splice points, so stage 4 is a
`CGImage → CGImage` insertion that touches neither the `VisualEffect` protocol nor its eighteen
implementations.

Two decisions carry most of the risk, and both are settled here rather than left to
implementation:

- **One CoreText layout, one master raster, non-overlapping tiles.** Preview and export share a
  resolution-independent layout and one transform function, and each rasterizes at its own native
  resolution. Parity becomes a property of the structure rather than a list of invariants two
  drawing paths are asked to honour (§7).
- **First-touch gesture routing.** The photo keeps its pan and zoom at all times, exactly as under
  every other category. A gesture whose first touch lands on the text drives the text; anywhere
  else it drives the photo. The routing is locked for the duration of a touch sequence, which is
  what makes a two-finger gesture straddling the text boundary unambiguous (§8).

The first release optimizes for the quick, preset-led interaction used by social creation apps
rather than exposing keyframes or a timeline. Instagram's implementation is especially relevant:
it pairs text styles with decorated variants and includes word- and character-level reveals, while
explicitly accounting for emoji, ligatures, and right-to-left languages. Canva, Adobe Express, and
CapCut similarly lead with named animation presets and offer style controls after selection.

Sources:

- [Meta Engineering — Building text animations for Instagram Stories](https://engineering.fb.com/2022/07/18/developer-tools/building-text-animations-for-instagram-stories/)
- [Canva — Text animations](https://www.canva.com/features/text-animations/)
- [Adobe Express — Animate designs](https://helpx.adobe.com/express/web/audio-and-animation/animate-design.html)
- [CapCut — Add text to video](https://www.capcut.com/tools/add-text-to-video)

---

## 2. What changed in revision 2, and why

### Scope

| Change | Reason |
|---|---|
| **Pinch-to-resize and free rotation are in V1.** Revision 1 deferred both and used a size slider. | Product decision. The slider's stated justification — "this avoids gesture conflict with the already pinchable photo canvas" — was a real constraint, not a preference, so §8 answers it directly instead of working around it. |
| **Gesture arbitration is first-touch routing.** The photo pans and zooms exactly as it does under every other category, always. A gesture whose *first* touch lands on the text drives the text; anywhere else drives the photo. | The canvas is a `UIScrollView` that owns pinch, pan and double-tap-to-zoom, so something has to arbitrate. Routing on first touch is deterministic, needs no modal state, and is the behaviour every sticker editor has trained users on. §8.3 handles the one case it does not answer by itself — a two-finger gesture straddling the text boundary. |
| **Rotation is a static resting orientation** with haptic snap detents near 0°, ±90° and 180°. Presets animate on top of it. | Keeps the animation contract at one composition step. Users almost never land exactly level, and near-level crooked text reads as a bug in an exported GIF. |
| **Still exactly one text layer.** | Unchanged from revision 1. Pinch and rotate are gesture fidelity, not scope: they add two model fields and a gesture layer, with no layer list, z-ordering, per-layer timing or selection management. |
| **Size, angle and position get accessibility adjustable actions, not panel rows.** | Pinch and rotate are affordances VoiceOver cannot perform, so an equivalent is mandatory. Sliders were the first answer, but the panel holds three rows (§10) and spending two of them mirroring gestures would leave no room for style or animation. An adjustable action with a rotor to pick the axis is the better VoiceOver design anyway, and costs no panel height. |
| **The editor is two-phase, entered from the preset carousel.** No ADD TEXT card: selecting a preset creates the overlay, opens the keyboard, and DONE hands off to a three-row settings panel. | Matches how every other category already works — an effect card is what applies an effect — so there is no new interaction concept to teach. |

### Defects found in revision 1

| # | Defect | Resolution |
|---|---|---|
| 1 | **§7 required snapshot/reference-image tests** at four progress values for every preset. The repo has 232 tests and no snapshot infrastructure, and `FEATURE-THEMES.md` §9 explicitly declines to build one. This was the plan's largest unstated cost. | Removed. §12 uses the house idiom instead: pixel *measurement* on structured fixtures (the `LensDistortionTests` pattern) plus assertions on layout and state data. The master raster is computed in-process and *is* the reference, so there is nothing to check in. |
| 2 | **"A text-only edit can generate at 1× zoom"** appeared in §5 and the acceptance criteria. ROADMAP records "Zoom is always on… **Consequence: effects-only GIFs at 1× are impossible**" as *deliberately unreachable, not removed*; `selectedAnimatorType` is never `nil` in the shipped UI. | The plumbing is wired for consistency with the dormant `nil`-animator path — in `hasEffectsWithoutZoom` **and** in `regenerateGIF`'s `canRegenerate`, in the same edit — but the claim is dropped from the acceptance criteria and recorded as an open decision in §15. |
| 3 | **No answer for the post-ENHANCE canvas.** Once a GIF exists, `EditorView.canvasSection` swaps `ImageCanvasView` for `GIFPreviewView`. Revision 1 listed "drag end" as a regeneration commit point while also saying not to stack a live overlay on the baked GIF — which left the overlay uneditable exactly when a user would want to adjust it. | The TEXT category keeps the live canvas, following the existing face-filters precedent. The exception is needed in **both** `canvasSection` branches: `.existingGif` already has a `.faceFilters` case, `.newImage` has none. |

### Architecture

| Change | Reason |
|---|---|
| **Preview and export no longer share rendered bitmaps** — they share a resolution-independent `PreparedTextLayout` and one transform function, and each rasterizes at its own native resolution. | Rasterizing at 600 px and displaying at 325 pt is a 0.5417× non-integer downscale. Silkscreen is a pixel font; that downscale is the single most visible thing in the feature. Sharing the *layout* keeps parity structural and gains crisp text on both sides. |
| **Reveal units are shaping-safe**, merged so no unit ever splits a glyph. | Per-cluster tiling forces isolated Arabic/Persian forms (`س ل ا م` instead of `سلام`) and splits Latin ligatures. The failure is silent, and every structural test passes while it happens — exactly the class LEARNINGS 2026-08-07 warns about. |
| **Tiles are non-overlapping cuts of one master raster**, never independent renderings. | Makes decoration continuous by construction, removes double-composite seams, and yields one decisive test: compositing every tile at rest must be byte-identical to the master. |
| **FLICKER loses its chromatic offset**, keeping deterministic opacity pulses and a small scale twitch. | A per-channel offset is not expressible as alpha + affine; supporting it would add a field to the state type and colour-matrix compositing to both paths, for one preset. The CIImage effects (LENS, CHROMA SHIFT) already own that look, one pipeline stage earlier. |
| **`TextAnimationType.state(at:)` becomes `tileStates(at:layout:)`** returning one state per tile. | A single state cannot express TYPE or WORD DROP. |
| **The `regenerateIfNeeded` P1 is a prerequisite, not a neighbour.** | `guard !isRegenerating else { return }` silently drops edits. Today that bites on an occasional slider commit; with direct manipulation it will bite whenever a user adjusts twice inside ~800 ms, and it reads as "the app ignored me". §8.7 fixes it first, on its own commit. |

---

## 3. Product principles

- **Preset first.** A user should be able to type, place, choose an effect, and generate in under
  20 seconds.
- **Direct manipulation.** Position, size and angle are set by touching the text, not by hunting
  for sliders. The sliders exist, but as the precise and accessible path rather than the primary
  one.
- **The text and zoom feel choreographed.** They share time, but text is not scaled by the image
  transform. The image can rush toward the viewer while the title independently pops, rises, or
  types into place.
- **The final message is readable.** All entrance motion finishes before the pause frames, and the
  pause always contains the complete text.
- **Preview and export cannot disagree.** Not because they are carefully kept in step, but because
  they consume the same layout and the same transform function and differ only in raster size.
- **Language correctness is part of V1.** Never split a Swift `String` by UTF-16 offsets or plain
  spaces, and never re-shape a substring in isolation. Emoji, composed characters, ligatures,
  multiline text, and right-to-left layout must remain intact.
- **No hidden timeline.** Duration is derived from the GIF's moving portion. Expose an `ENTRANCE`
  timing control only after the presets feel good at their defaults.

---

## 4. V1 user experience

### Entry point

Add a fourth editor category, **TEXT**, beside Zoom, Face, and Image, with a bundled template `T`
icon matching the existing monochrome category icons. The tab row is currently a hardcoded
`HStack(spacing: 48)` of three icons; derive the spacing from measured width rather than adding a
fourth 48 — the SE 3 layout budget is the recurring theme of this project's layout bugs.

The carousel is **five animation preset cards and nothing else** — the same shape as the visual
effects and face filters carousels, with no ADD TEXT card in front of it. Selecting a preset is
what creates the overlay, exactly as selecting an effect card is what applies an effect. There is
no separate "add" step to explain, and preset cards can show their own animated preview (§10).

### The editing flow

Selecting a preset opens a single edit session with two phases:

```text
tap TEXT icon
   → carousel of five preset cards
      → tap a preset            ── creates the overlay, opens the editor
         → keyboard, type the word
            → DONE              ── keyboard collapses, text is committed
               → settings panel ── COLOR, STYLE, and one animation control
                  → CONFIRM     ── one undo entry for the whole visit
```

**Phase 1, the keyboard.** A multiline field limited to 120 extended grapheme clusters. (Three
rendered lines is a field-sizing guideline, not a renderer constraint.) DONE dismisses the keyboard
rather than closing the session. On a 4.7" screen the field and its DONE affordance must both clear
the keyboard — the recurring short-device constraint in this project.

**Phase 2, the settings panel.** The existing `EffectDetailPanel`, with `<` to cancel and the
mint check to confirm, so the whole visit records exactly one undo entry. Cancelling a *newly
created* overlay removes it, since the preset tap and the edit are one session.

Reopening is symmetric: **double-tapping the text returns to phase 1** with the keyboard up;
tapping a preset card again returns to phase 2.

The panel holds three rows (§10). The five-row cap enforced elsewhere in the app is the ceiling,
not the budget: `parameterRowHeight(forPanelHeight:rowCount:)` divides the panel by `rowCount + 1`
and floors at 34 pt, and past that floor `needsScroll` flips on — at which point, per LEARNINGS
2026-08-08, a slider drag scrolls the panel instead of moving the knob. The zoom category's
hardcoded three rows is the honest budget.

### Canvas interaction

While the TEXT category is active and an overlay exists, the text renders directly over
`ImageCanvasView`, and **the photo behaves exactly as it does under every other category** — pan,
pinch-zoom and double-tap-to-zoom all work, always, with no mode to leave first.

Arbitration is on **first touch**:

| Gesture | First touch on the text | First touch elsewhere |
|---|---|---|
| Single tap | Selects (idempotent — never deselects) | Deselects |
| Double tap | Reopens the keyboard | Zooms the photo, as today |
| One-finger drag | Moves the text | Pans the photo, as today |
| Pinch | Scales the text | Zooms the photo, as today |
| Rotate | Rotates the text, with haptic detents near 0°, ±90° and 180° | — |

The routing decision is made once, on the first touch of a sequence, and **held until every touch
lifts** (§8.3). That is what makes a two-finger pinch with one finger on the text and one finger
off it unambiguous — it scales the text, because that is where the gesture started.

Selection is a visual state, not a mode. It draws a light outline that never enters the GIF and
widens the touch region a little, but it does not change what any gesture does — an unselected
overlay can be dragged, pinched and rotated directly. The text always presents at least a 44 pt
touch target, selected or not, so small text is never hard to grab.

RESET clears the overlay, and the settings panel offers an explicit delete.

### Regeneration behavior

Typing and direct manipulation update the local preview immediately but do not regenerate a GIF on
every event. Regenerate only on meaningful commit points:

- confirming the settings panel;
- **gesture session end** — the point at which the last of a simultaneous drag/pinch/rotate ends,
  not the end of each individual recognizer;
- animation preset selection;
- undo, redo, reset, or delete.

For an already-generated or existing GIF, use the current regeneration guard — as repaired in
§8.7 — and show the existing regenerating overlay. For a new image before ENHANCE, no background
GIF work is needed.

---

## 5. Entrance preset set

All curves consume normalized moving-frame progress `p` from `0...1`. Define a shared entrance
window `q = min(1, p / 0.70)` so every preset is complete before the final 30% of motion and
before all pause frames.

| Preset | Behavior | Granularity | Default curve | Panel control | Why it belongs in V1 |
|---|---|---|---|---|---|
| **POP** | Fade from 0, scale 0.55 → 1.08 → 1 | whole | spring-like overshoot | **BOUNCE** — overshoot amount | The expressive default; complements zoom without duplicating it |
| **RISE** | Move upward ~48 output pixels while fading in | whole | cubic ease-out | **DISTANCE** — travel | Familiar, legible, and works for multiline text |
| **TYPE** | Reveal by shaping-safe unit with a blinking block cursor | unit | stepped reveal | **SPEED** — units per unit time | Direct Instagram inspiration and a strong fit for the pixel font |
| **WORD DROP** | Reveal linguistic word tokens in sequence with a short downward settle | word | staggered ease-out | **STAGGER** — inter-word delay | More energetic than TYPE while still readable |
| **FLICKER** | Resolve from 2–3 deterministic opacity pulses and a ±0.02 scale twitch | whole | damped deterministic pulses | **INTENSITY** — pulse depth | Matches Enhance's glitch/pixel personality |

Each preset declares exactly one tunable parameter, occupying the panel's third row (§10). The
label changes per preset; the storage is the existing `parameterValues` dictionary keyed by
`EffectParameter.key(_:for:)`, so nothing new is needed to persist or snapshot it. Whatever the
parameter is set to, the entrance window `q` still closes by 70% — the control shapes the curve
inside that window, it does not extend it.

The effects are entrance-only. Do not add a looping wiggle or pulse in V1: motion during the pause
makes the message harder to read, increases GIF entropy and file size, and complicates the promise
that the final state is stable.

Use deterministic functions of `progress` and a stable overlay seed. Never call random APIs in the
frame loop, or preview and export will disagree and repeated generations will differ.

---

## 6. Data model

Under `Enhance/Models/Text/`:

```swift
struct TextOverlay: Equatable, Sendable {
    var text: String
    var center: CGPoint          // normalized 0…1 of the output frame, (0,0) top-left
    var fontSize: CGFloat        // normalized against output height
    var angle: CGFloat           // radians, resting orientation, (−π, π]
    var font: TextFont
    var color: TextColorChoice
    var alignment: TextAlign
    var decoration: TextDecoration
    var animation: TextAnimationType
    var seed: UInt64             // stable per overlay; FLICKER determinism
}

enum TextAnimationType: String, CaseIterable, Identifiable, Sendable {
    case pop, rise, type, wordDrop, flicker

    var granularity: TextTileGranularity   // .whole | .unit | .word
    var peakScale: CGFloat                 // greatest scale the preset reaches; POP = 1.08
    func tileStates(at progress: CGFloat, layout: PreparedTextLayout) -> [TextTileState]
}
```

Colours are a small semantic enum with UIKit and SwiftUI projections, as `LaserColor` does today.
Never store a `SwiftUI.Color` in a snapshot; LEARNINGS 2026-08-07 records the equality and
persistence problems that creates for `GradientStops`, and the workarounds it forced.

`fontSize` is normalized and **does not appear in the composition matrix** — it is consumed at
layout time as `resolvedPointSize = fontSize × outputSide`, so changing size re-lays-out and
re-wraps. This is why a live pinch needs the transient handling in §7.5 rather than being a pure
transform forever.

Wrap width is a constant fraction of the frame, not a model field. Pinch changes `fontSize`, and
more lines falling out of a larger size is the natural behaviour.

Add `textOverlay: TextOverlay?` to `EditorSnapshot` (a 13th field) and `EditorViewModel`. Include
it in `currentSnapshot`, `restore`, `resetEffects`, `hasNonDefaultSettings`, the
generate/regenerate calls, and `hasEffectsWithoutZoom`. An empty or whitespace-only string is not
an active overlay.

Use a draft copy while the editor is open. Cancel restores the entry snapshot; Done records
one undo entry for the entire visit. Direct manipulation uses gesture sessions (§8.6), which
record one entry per session regardless of how many recognizers participated.

V1 retains the app's current baked-GIF behavior: after leaving the editor and reopening a saved
GIF, the original editable recipe is not reconstructed. The first frame of every entrance must
therefore contain no visible text, which also prevents a baked title from being duplicated when
that frame is later used as the source image. §12 turns this from a prose commitment into a
compiled assertion. Full recipe persistence should be designed for all effect families together,
not added as a text-only metadata format.

---

## 7. Rendering architecture

### 7.1 One layout, one master raster, non-overlapping tiles

Three stages, one invariant.

> **Tiles are never rendered independently. One CoreText layout produces one fully decorated
> master raster, and tiles are non-overlapping *cuts* of that raster.**

That single rule is what makes shaping, ligatures, decoration continuity and seam-free
compositing correct simultaneously, and it collapses into one decisive test (§12.2).

**Stage 1 — layout.** `TextLayoutEngine.layout(overlay:outputSize:)` runs exactly one
`CTFramesetter` pass and returns a resolution-independent value type:

```swift
struct PreparedTextLayout: Equatable, Sendable {
    let units: [TextUnit]          // reveal units, in logical (typing) order
    let lines: [TextLine]
    let inkBounds: CGRect          // tight, local space, origin at the text's centre, y down
    let resolvedPointSize: CGFloat
    let baseDirection: TextBaseDirection
    let lineCount: Int
}

struct TextUnit: Equatable, Sendable {
    let order: Int                 // ascending == typing order, in both LTR and RTL
    let stringRange: Range<Int>    // UTF-16; diagnostics and accessibility only
    let glyphIDs: [Int]            // used to prove disjointness
    let inkRect: CGRect            // local space
    let advanceEnd: CGPoint        // direction-aware trailing edge; where the cursor sits
    let lineIndex: Int
    let isWhitespace: Bool
}
```

It holds no CF objects, so it is `Sendable` and crosses to the generator's background queue
freely.

**Stage 2 — one master raster.** `TextRasterizer.prepare(overlay:pixelSize:)` draws the whole
decorated text once into an explicit `CGContext` — not `UIGraphicsBeginImageContextWithOptions`,
because this runs off the main queue and an explicit colour space is worth having. Decoration
order inside that one pass: BLOCK fill → SHADOW → glyph fill → OUTLINE stroke. All continuous, all
correct, once.

**Stage 3 — cutting.**

```swift
struct RasterizedText: Sendable {
    let layout: PreparedTextLayout
    let master: CGImage            // kept alive; every tile is a view onto it
    let tiles: [TextTile]          // non-overlapping
    let pixelSize: CGSize
    let granularity: TextTileGranularity
}

struct TextTile: Sendable {
    let unitOrder: Int             // index into layout.units; −1 for synthetic
    let image: CGImage             // master.cropping(to:) — shares the parent's backing store
    let pixelRect: CGRect
    let localCentre: CGPoint       // this tile's own rotation/scale pivot
    let origin: TileOrigin         // .cut | .synthetic
}
```

Because cuts are non-overlapping and every tile's resting state is (alpha 1, identity),
**compositing all tiles at rest reproduces `master` byte for byte**. That is the whole safety
property and it is one assertion.

It also disposes of a complication: with non-overlapping cuts, alpha-0/1 tiles *are* a clip mask,
so TYPE needs no second code path.

**Rasterize through a coverage mask, even though V1 does not need to.** The planned follow-ons —
animated gradients, static gradients, sparkle (§16) — are all *fills* that vary per frame while the
glyph geometry stays fixed. If `TextRasterizer` produces the master as a glyph **coverage mask**
and then applies the fill, a per-frame fill later means drawing a different fill through the same
static mask, with the tiles and every transform unchanged. If instead the colour is fused into the
rasterizer's only output, that extension has to re-cut tiles per frame and the invariant in §12.2
stops holding.

V1 still bakes its solid colour into the master and blits opaque tiles, because that is the fast
path and colour changes are commit points rather than per-frame events. The requirement is only
that the mask survives as a distinct step inside `prepare`, so the seam is in the right place. This
is cheap now and expensive to retrofit.

**Memory.** `CGImage.cropping(to:)` returns a view sharing the parent's backing store, so 120
tiles cost approximately nothing beyond the master. A 600² RGBA master is 1.44 MB; the preview
master at 975² is 3.8 MB. The real cost is CALayers in the preview and small blits per exported
frame, both microsecond-scale. No pooling or tile budget is needed. The 120-cluster cap exists for
layout sanity, not memory.

### 7.2 Shaping-safe units

Units start from extended grapheme cluster boundaries and then **merge any clusters that fall
under a single glyph**. After `CTFramesetterCreateFrame`, walk `CTFrameGetLines` →
`CTLineGetGlyphRuns` → `CTRunGetStringIndices` (one string index per *glyph*) and
`CTRunGetPositions`; a glyph whose next-glyph string index skips more than one cluster covers all
the clusters in between.

Results:

- Latin `ffi` → one unit, so it types in whole rather than as half a ligature.
- Arabic `سلام` → four units, one per *shaped* glyph, each in its correct initial/medial/final form.
- `لا` (lam-alef) → one unit: two clusters, one glyph.
- ZWJ family emoji, regional-indicator flags, `e` + U+0301, skin-tone modifiers → one unit each.

Positions come from `CTLineGetOffsetForStringIndex` and `CTRunGetPositions`, which map *logical*
indices to *visual* positions — so TYPE reveals in typing order and RTL works with no
special-casing. WORD DROP tokenizes with `NLTokenizer(unit: .word)`, never
`split(separator: " ")`.

This follows the failure modes documented by Meta's Instagram team: character offsets and space
splitting break ligatures, emoji, and right-to-left text. The subtler trap is that laying out a
substring *in isolation* also breaks joining, silently, while every structural test still passes.

### 7.3 Seams

The seam between units *i* and *i+1* is the vertical line at the **midpoint between unit *i*'s ink
right edge and unit *i+1*'s ink left edge** — mirrored for RTL, computed per line. Not the advance
boundary: the ink midpoint, so any outline or shadow bleed crossing it was genuinely ambiguous.
Line boundaries cut horizontally at the midpoint of the interline gap.

Two cases are not cuts:

- **BLOCK** is a continuous plate behind the whole text. Sliced across word tiles under staggered
  alpha it becomes a ladder of abutting rectangles. It is its own tile, animating as a unit.
- **The TYPE cursor** is the one synthetic tile, rasterized separately and positioned at
  `units[revealed − 1].advanceEnd` — direction-aware, so in RTL it sits to the *left* of the last
  revealed glyph. Its position is baked in at prepare time and its state is a pure alpha blink, so
  no per-quantity exception leaks into the animation contract. Excluded from the partition test
  via `origin == .synthetic`.

### 7.4 Two rasters, one layout

Preview and export **must not share rendered bitmaps**. Export needs 600×600 at scale 1, matching
`UIGraphicsBeginImageContextWithOptions(outputSize, false, 1.0)`. The preview needs
325 pt × screen scale — 650 or 975 px. Rasterizing at 600 and displaying at 325 pt is a 0.5417×
non-integer downscale of a pixel font, and Silkscreen turns to mush.

So the shared artifacts are one level up: **the resolution-independent `PreparedTextLayout`, the
`tileStates(at:)` evaluator, and one `TextComposer.transform` function**. Each side rasterizes at
its own native resolution. Parity is then guaranteed by the layout being resolution-independent
and by a resolution-independence test (§12.5) — cheaper, more precise and less brittle than any
snapshot suite, and it fails loudly if anyone reintroduces a resolution-dependent constant such as
a hardcoded shadow offset in pixels.

Neither compositor may compute its own matrix. The preview converts the shared
`CGAffineTransform` with `CATransform3DMakeAffineTransform`.

### 7.5 Rasterization scale and the live pinch

**Scale.** The master is rasterized at `resolvedPointSize × animation.peakScale`, so POP's 1.08
overshoot frame is 1:1 and never an upscale. `peakScale` is declared on the preset, so a future
preset that overshoots further widens the raster automatically. The resting transform therefore
carries a compensating `1/peakScale` term (§7.6) — the raster is deliberately oversized and scaled
*down* at rest, which is the safe direction.

**During a live pinch**, do not re-rasterize per gesture frame. Re-running CoreText at 60 Hz is
exactly the per-frame work that LEARNINGS 2026-03-13 records as having killed the old SwiftUI
canvas. Three rules:

1. **Per gesture frame, transform only.** One extra uniform term `S(fontSizeLive /
   fontSizeCommitted)` about the text centre, on the layer stack. No CPU cost.
2. **`layer.magnificationFilter = .nearest` whenever the resolved font is Silkscreen.** A pixel
   font magnified with nearest-neighbour stays *blocky*, which is its correct look, so the
   transient reads as intentional rather than soft. This is what makes rule 1 acceptable; the
   default bilinear filter would make the transient mushy and the snap-back jarring.
3. **Coalesced re-raster on a 100 ms trailing timer during the gesture, and unconditionally on
   session end.** One layout plus one 600² raster is on the order of a millisecond, so the preview
   catches up within a tenth of a second and the committed size is exact.

The export path never uses rules 1–2: `fontSizeLive == fontSizeCommitted` always, so the extra
term is exactly identity in the GIF. §12.4 asserts it.

### 7.6 Composition order

Resting state is the user's `center` (normalized), `fontSize` (normalized) and `angle`. The preset
composes on top, with **translation in output space and scale/rotation in the text's local space**
— a 90°-rotated title that RISEs should still move up the *screen*, because gravity is a screen
metaphor, but should scale about *itself*, because scale is a typographic property.

```swift
struct TextTileState: Equatable, Sendable {
    var alpha: CGFloat
    var scaleDelta: CGFloat        // local, about the tile's own centre
    var rotationDelta: CGFloat     // local, about the tile's own centre
    var translationDelta: CGPoint  // output/screen space, applied last
}
```

Per-tile deltas pivot on **the tile's own centre**, not the text's. A per-word scale about the text
centre would also translate the words outward, turning WORD DROP's settle into an explosion. For
`.whole` granularity the single tile's centre *is* the text centre, so one rule covers both cases
with no branch.

Coordinates: output space, top-left origin, y down, side `S` (600 for export, 325 × screen scale
for preview). Local space: origin at the text's ink-bounds centre, y down. Given tile `t`, state
`st`, and the raster's oversize factor `k = animation.peakScale`:

```swift
var m = CGAffineTransform(translationX: -t.localCentre.x, y: -t.localCentre.y)
m = m.concatenating(CGAffineTransform(scaleX: st.scaleDelta, y: st.scaleDelta))
m = m.concatenating(CGAffineTransform(rotationAngle: st.rotationDelta))
m = m.concatenating(CGAffineTransform(translationX: t.localCentre.x, y: t.localCentre.y))
m = m.concatenating(CGAffineTransform(scaleX: liveScale / k, y: liveScale / k))
m = m.concatenating(CGAffineTransform(rotationAngle: overlay.angle))
m = m.concatenating(CGAffineTransform(translationX: overlay.center.x * S,
                                      y: overlay.center.y * S))
m = m.concatenating(CGAffineTransform(translationX: st.translationDelta.x,
                                      y: st.translationDelta.y))
```

`CGAffineTransform` is row-vector, so `a.concatenating(b)` means "apply a, then b" and the code
reads top to bottom in application order. `liveScale` defaults to 1.0 and the GIF path never
passes it.

Properties that fall out, each of which becomes a test:

- At θ = π/2 with RISE at p = 0.5, translation is applied after `R(θ)`, so the text moves up the
  screen regardless of its rotation.
- At POP's peak, `scaleDelta` pivots on `t.localCentre`, which for `.whole` is the text centre, so
  the box grows 8% about itself and does not drift, at any θ.
- At p = 1 with all deltas identity, `m` reduces to `S(1/k) · R(θ) · T(center · S)`, so the
  composite of all tiles is the master raster placed at rest — for every preset.

### 7.7 Pipeline splice

Extend `GIFGenerating.generateGIF` with `textOverlay: TextOverlay?`. Update both test stubs in the
same change — `EnhanceTests/EditorViewModelTests.swift` and `EnhanceTests/SaveGIFTests.swift` —
they are intentionally compile-time witnesses for this boundary.

In `GIFGenerator`, prepare once before either frame loop:

```swift
let textRaster = TextRasterizer.prepare(overlay: textOverlay, pixelSize: context.outputSize)
```

Then each path changes from:

```text
source → face effects → zoom/crop → visual effects → GIF frame
```

to:

```text
source → face effects → zoom/crop → visual effects → text overlay → GIF frame
```

At both splice points — in `addAnimatedFrames` after `applyVisualEffects`, and the same in
`addPauseFrames`:

```swift
let outputImage = applyVisualEffects(…)
let framed = textRaster.map {
    TextTileCompositor.composite($0, overlay: overlay, progress: frameProgress, over: outputImage)
} ?? outputImage
CGImageDestinationAddImage(destination, framed, frameProperties as CFDictionary)
```

`addPauseFrames` already renders one image and appends it `pauseFrameCount` times, so compositing
once at `progress = 1.0` gives pause stability for free: the text is at its final state and byte
identical across every pause frame, so it cannot shimmer and costs nothing.

Do not rebuild attributed strings, tokenize words, or measure lines inside the frame loop. The
prepared pass is immutable and safe to use from the generator's background queue.

### 7.8 Coordinate contract

The text renderer works only in output-frame coordinates:

- `center`, `fontSize` and the wrap width are normalized and resolved against the raster size;
- `(0, 0)` is top-left in the editor, the renderer and the layer stack;
- text is composited after the zoom transform, so it never uses `visibleRect`, `drawRect`, or
  `FrameGeometry`;
- the live overlay uses the same normalized values against the 325-point canvas.

There is **no CIImage in the text pass, and therefore no Y-flip**. LEARNINGS records two separate
Y-flip bugs (2026-03-10, 2026-08-07); state this in the file header so nobody "fixes" it.

Everything the LENS and DITHER entries warn about — preview and export applying effects in
different spaces, image-anchored quantities looking wrong under zoom — is structurally inapplicable
here *because* the text is frame-anchored rather than image-anchored. That is only true because
the overlay is a sibling of the scroll view rather than a subview of the zooming image view (§8.2).
The rendering decision and the view-hierarchy decision are the same decision.

---

## 8. Gesture architecture

### 8.1 UIKit, not SwiftUI

Four independent reasons, any one of which decides it:

1. **LEARNINGS 2026-03-13** — SwiftUI gesture-driven transforms re-evaluate the whole view body
   per frame. `EditorView`'s body holds the canvas, the animated `AngularGradient` border, the
   carousel and the panel. Driving drag/pinch/rotate through `@State` re-evaluates all of it at
   60 Hz, which is the exact regression the `UIScrollView` rewrite existed to remove.
2. **LEARNINGS 2026-03-08** — `.scaleEffect` expands the gesture hit-test area. Our overlay is
   scaled *and* rotated. A `UIView` overriding `point(inside:)` with an inverse-transform test
   gives exact rotated-rect hit testing and a guaranteed 44 pt minimum target.
3. **LEARNINGS 2026-03-09** — a `MagnificationGesture` over a scroll view never fires without
   `.simultaneousGesture`, and `.simultaneousGesture` is the wrong tool here: the deselected state
   needs *exclusion*, not coexistence.
4. `require(toFail:)` and `shouldRecognizeSimultaneouslyWith` have no SwiftUI equivalent across a
   representable boundary.

### 8.2 Structure: one representable, two siblings

Restructure `ImageCanvasView`'s representable so its root is a plain container `UIView`:

```text
CanvasContainerView (UIViewRepresentable) → UIView (root, 325×325)
   ├── UIScrollView          (existing configuration, moved verbatim)
   └── TextOverlayHostView   (added only when an overlay exists)
```

One representable rather than two, because **routing needs a common ancestor that sees the touch
before either sibling does** (§8.3), and because two sibling representables have no defined
`makeUIView` ordering within a SwiftUI update pass. The container is not decorative — it is where
the arbitration lives.

**The scroll view's setup moves verbatim.** `configureContentSize` stays in the make path only, and
`updateUIView` still touches nothing but `imageView.image` and the face boxes. LEARNINGS 2026-03-13
("image swap must not reset scroll state") lives in that method; do not refactor it while in there.

`TextOverlayHostView` is a **sibling, not a subview of the zooming `UIImageView`**. Face boxes are
subviews of the image view so they track the photo; text must not. Two consequences: text stays put
while the photo pans beneath it, which is the product intent; and the 325 pt ↔ 600 px mapping is a
single uniform scale with no aspect handling, because both are square and both are the *output*
frame. That is why parity is cheap here.

### 8.3 First-touch routing, held for the sequence

The photo's recognizers are **never disabled**. Routing happens in the container's `hitTest`, which
picks a destination on the first touch of a sequence and holds it until every touch lifts:

```swift
private enum Route { case text, photo }
private var activeRoute: Route?

override func hitTest(_ p: CGPoint, with event: UIEvent?) -> UIView? {
    if activeRoute == nil {
        activeRoute = textHost.hitRegion.contains(p) ? .text : .photo
    }
    return activeRoute == .text ? textHost : scrollView
}
// activeRoute = nil once no touch in `event.allTouches` is still in
// .began/.moved/.stationary — i.e. the sequence is fully over.
```

**Holding the route is the whole point.** Without it, UIKit hit-tests each touch independently, so
a two-finger pinch with one finger on the text and one finger off it would deliver one touch to the
host and one to the scroll view. Neither recognizer would ever see two touches, and the pinch would
silently do nothing — a bug that only reproduces when a finger straddles an invisible boundary, and
which would be miserable to diagnose from a bug report. Locking the route on first touch makes the
straddling case behave the way the user's hand intends: the gesture started on the text, so it
scales the text.

The mirror case is covered by the same rule. A gesture that starts on the photo keeps the photo for
its whole life, so a second finger landing on the text joins the photo's pinch rather than
splitting the gesture in half.

`hitRegion` is the text's rotated bounds inverse-transformed into canvas space, inflated to a 44 pt
minimum on each axis, and widened slightly while selected. It does not depend on selection for
*routing* — an unselected overlay is draggable directly, which is what makes selection a visual
state rather than a mode.

### 8.4 What this removes

An earlier revision suspended the scroll view's recognizers while text was selected, and needed a
guarded setter to do it safely: `syncBindings` writes `parent.visibleRect` on every scroll delegate
callback, which re-evaluates the SwiftUI body, which runs `updateUIView` — continuously, during a
pan. Disabling a recognizer mid-recognition transitions it to `.cancelled`, so an unconditional
write there was a latent "the pan randomly stops" bug presenting as jank.

Routing deletes that machinery entirely. **Never** reach for `minimumZoomScale = maximumZoomScale`
(it mutates `zoomScale` and destroys the user's framing), `isUserInteractionEnabled` (it kills
`FaceBoxView` touches), or `isScrollEnabled` (blunt, with `contentInset` and delegate side effects,
and `centerContent` already writes `contentInset` on every zoom). The scroll view is configured once
and left alone, which is also what LEARNINGS 2026-03-13 asks of `updateUIView`.

### 8.5 The recognizer graph

| Tag | Recognizer | Attached to |
|---|---|---|
| SV-PAN / SV-PINCH / SV-DT | pan, pinch, double-tap-to-zoom | `UIScrollView` |
| TX-ST | single tap — select / deselect | `TextOverlayHostView` |
| TX-DT | double tap — reopen the keyboard | `TextOverlayHostView` |
| TX-PAN / TX-PINCH / TX-ROT | move / scale / rotate | `TextOverlayHostView` |

UIKit delivers a touch to recognizers on the hit-test view **and its ancestors**. Because routing
returns one sibling or the other and nothing is attached to the container, the two sets never see
each other's touches. In particular **SV-DT never sees a double tap that lands on the text**, and
TX-DT never sees one that lands on the photo — so double-tap-to-zoom and double-tap-to-edit
coexist with no `require(toFail:)` between them.

TX-PAN, TX-PINCH and TX-ROT are pairwise `shouldRecognizeSimultaneouslyWith`.
`TX-PAN.maximumNumberOfTouches = 2`, so a two-finger drag translates while scaling — the sticker
idiom users already know.

**Do not add `TX-ST.require(toFail: TX-DT)`.** It costs ~350 ms of dead time on every selection,
which would be the most-felt latency in the feature. Instead define TX-ST on the text as
**idempotent select**:

- TX-ST on the text: select if not selected; no-op if already selected. **Never deselects.**
- TX-ST on the photo: deselect.
- TX-DT on the text: reopen the keyboard.

A double-tap on an unselected overlay then fires TX-ST on tap 1 — the outline appears, which reads
as feedback — and TX-DT on tap 2. The editor wants a selected overlay anyway, so tap 1's effect is
not merely harmless, it is required state. There is no wrong state to recover from, so there is
nothing to serialize, so there is no reason to pay the delay. The non-deselecting rule is what makes
this safe: without it, tap 1 on an already-selected overlay would deselect and tap 2 would
re-select, producing a visible flicker. It also prevents accidental deselection while nudging.

Residual latency: **zero on selection**, ~350 ms on reopening the keyboard — unavoidable and
universal to double-tap, and acceptable because it is a deliberate act.

### 8.6 Gesture sessions and undo

A **counter**, not a boolean, because pinch and rotate begin and end independently and in either
order.

```swift
// Enhance/Components/TextGestureSession.swift — no UIKit import, so it is directly testable
final class TextGestureSession {
    /// Called from every recognizer's `.began`. Only the 0→1 transition captures.
    func begin(current: TextOverlay, capture: (TextOverlay) -> Void)

    /// Called from `.ended` / `.cancelled` / `.failed`. Only the →0 transition commits,
    /// and commits nothing if the overlay is unchanged — a cancelled or no-op gesture
    /// must not litter the undo stack or trigger a regeneration.
    func end(final: TextOverlay, commit: (_ preGesture: TextOverlay) -> Void)

    /// Force-drain. Idempotent. For backgrounding and view teardown.
    func abort(final: TextOverlay, commit: (_ preGesture: TextOverlay) -> Void)
}
```

`capture` calls `viewModel.beginTextGesture()`, which stores an `EditorSnapshot` exactly as
`beginEditing()` does. `commit` calls `viewModel.endTextGesture()`, which pushes that snapshot —
pre-change discipline, matching `commitEditing` — and then requests regeneration.

**The view model owns the history; the view owns only the counter.** LEARNINGS 2026-08-08 records
that a child pushing its own undo inside a container with a history contract produces double
entries and an undo that steps the user *forward*. So no individual pan, pinch or rotate handler
may call `pushUndo()`. That is a grep-able invariant, not a convention.

Global undo and redo are disabled while a session is active, mirroring `isEditingEffect`.

`.cancelled` decrements like `.ended`; the unchanged-overlay check distinguishes "nothing happened"
from "the user did something and a system event cancelled it," and one rule handles both. UIKit
cancels recognizers on resign-active so the counter drains naturally; belt and braces, observe
`UIApplication.willResignActiveNotification` and call `abort`, which is idempotent so the two paths
cannot double-push. Same call from `willMove(toSuperview: nil)` for a category switch mid-gesture.

### 8.7 Prerequisite: repair the regeneration guard

`regenerateIfNeeded()`'s `guard !isRegenerating else { return }` silently drops edits — an open P1.
Today it bites on the occasional slider commit. With direct manipulation it will bite whenever a
user adjusts twice inside ~800 ms, and the second position is silently absent from the GIF, which
reads as the app ignoring them.

```swift
private var regeneratePending = false

func regenerateIfNeeded() {
    guard !isRegenerating else { regeneratePending = true; return }
    …
}
// at every completion path of regenerateGIF — success and both error paths:
if regeneratePending { regeneratePending = false; regenerateIfNeeded() }
```

Small and contained, it retires an open P1, and it lands on its own commit with the suite green
before and after — LEARNINGS 2026-08-07 on confirming a baseline before changing it.

### 8.8 Live preview loop

A `CADisplayLink` inside the host view drives `tileStates(at:)` onto the tile layers. Paused when
TEXT is not the active category, while the keyboard phase is up, and under Reduce Motion, which
shows the settled state.

Two CALayer hazards to write into the code as comments:

- Set `anchorPoint = .zero`, `position = .zero`, `bounds = CGRect(origin: .zero, size:
  tile.pixelRect.size)`. The default `anchorPoint` of (0.5, 0.5) silently relocates every rotation
  pivot — invisible at θ = 0, obvious at θ = 90°.
- Wrap every per-frame write in `CATransaction.begin()` / `setDisableActions(true)` /
  `commit()`. Implicit CALayer animations default to 0.25 s and will smear a 60 Hz explicit
  animation into mush. That failure *looks* like an easing bug in `tileStates(at:)` and will eat an
  afternoon.

---

## 9. Geometry limits

Clamping measured bounds to a fixed margin — revision 1's rule — does not survive free rotation:
the axis-aligned bounding box grows as the text rotates, up to √2× for a wide block at 45°, so
legally placed text gets shoved sideways *while the user is rotating it*. That is the worst possible
moment to move something under a finger.

Instead: **hard clamp always, rubber-band while tracking, settle on release.** This is the
`UIScrollView` bounce idiom the canvas already uses (`bounces`, `bouncesZoom`), so it feels native
beside the photo. It never fights mid-gesture, and it always ends legible.

```swift
// Enhance/Models/Text/TextLayoutLimits.swift — pure value maths, no UIKit
enum TextLayoutLimits {
    static let centreRestInset: CGFloat     = 0.10   // where it settles
    static let centreHardInset: CGFloat     = 0.05   // absolute floor, even mid-gesture
    static let rubberBandRange: CGFloat     = 0.15

    static let minFontSize: CGFloat         = 0.035  // Silkscreen legibility floor
    static let maxFontSizeAbsolute: CGFloat = 0.30
    static let lineHeightMultiple: CGFloat  = 1.25
    static let verticalBudget: CGFloat      = 0.92
    static let pinchOvershoot: CGFloat      = 1.15

    static let layoutWidth: CGFloat         = 0.86   // local space, so rotation never reflows

    static let snapEnter: CGFloat           = 0.0698 // 4°
    static let snapRelease: CGFloat         = 0.1396 // 8° — hysteresis band

    /// Derived, not a constant: three lines at 0.30 would need 1.125 of the frame.
    static func maxFontSize(lineCount: Int) -> CGFloat {
        min(maxFontSizeAbsolute,
            verticalBudget / (CGFloat(max(1, lineCount)) * lineHeightMultiple))
    }

    static func clampCentre(_ c: CGPoint, phase: GesturePhase) -> CGPoint
    static func clampFontSize(_ f: CGFloat, lineCount: Int, phase: GesturePhase) -> CGFloat
    static func snapAngle(_ radians: CGFloat, current: Int?) -> (angle: CGFloat, detent: Int?)
}
```

Rubber band, standard form, applied per axis beyond `centreRestInset` and then hard-clamped at
`centreHardInset`: `band(x, range) = (1 − 1/(x/range + 1)) × range`. Tracking uses the rest inset
plus the band; settling clamps into `[centreRestInset, 1 − centreRestInset]`, animated with the
app's existing spring.

The rotated bounding box is deliberately allowed to bleed off-frame — running oversized text off the
edge is a legitimate design, and a centre inside the safe rect is the guarantee that actually
matters.

Detents sit at 0, ±π/2 and π with the angle normalized to (−π, π]. Track the **raw** accumulated
angle separately from the committed snapped angle, so continuing to rotate past a detent escapes
cleanly instead of sticking. `snapAngle` takes the currently latched detent and returns the new one;
the caller fires `HapticService.light()` only when it changes. The 4°/8° hysteresis is what stops
the haptic machine-gunning on the boundary.

---

## 10. Editor and state integration

- **Fourth `EffectCategory` case**, `text`, with a bundled template icon
  (`template-rendering-intent: template`, no baked `fill-opacity` — LEARNINGS 2026-03-12/13).
- **The TEXT category keeps the live canvas after ENHANCE**, following the face-filters precedent.
  The exception belongs in **both** `canvasSection` branches: `.existingGif`, which already has a
  `.faceFilters` case, and `.newImage`, which has none today. Text cannot be positioned against a
  `GIFPreviewView`.
- **The settings panel is the existing `EffectDetailPanel` with three rows**, and
  `editingRowCount` gains a `.text` case returning 3, alongside zoom's hardcoded 3:

  | Row | Control | Notes |
  |---|---|---|
  | **COLOR** | swatch row | Reuses the existing `EffectParameter.Kind.tintColor` machinery. White, black, mint, pink, yellow, blue. |
  | **STYLE** | `SegmentedBar` | NONE / SHADOW / BLOCK / OUTLINE. Same component the zoom category uses for MOTION. |
  | *per-preset* | slider | BOUNCE / DISTANCE / SPEED / STAGGER / INTENSITY (§5). Label varies, storage is `parameterValues`. |

  **Font choice does not ship in V1.** The overlay defaults to Silkscreen Bold — the app is
  entirely Silkscreen, so one font is a coherent V1 rather than a gap. `TextFont` still carries all
  five cases and the renderer resolves them, so adding the picker later is a UI-only change.
  Alignment defaults to centred; with one freely positioned block it only matters for multiline.
- **Size, angle and position have no panel rows.** They are direct manipulation, and their
  accessible equivalent is an `accessibilityAdjustableAction` on the selected text with a rotor to
  switch axis — which is the better VoiceOver design regardless, and costs no panel height.
- **The edit session spans both phases.** `beginEditing` on preset selection, keyboard, DONE,
  settings, then `commitEditing` — one undo entry per visit. `cancelEditing` on a newly created
  overlay removes it, because the preset tap and the edit are the same session.
- **`hasEffectsWithoutZoom` and `regenerateGIF`'s `canRegenerate` are loosened in the same edit.**
  LEARNINGS 2026-03-13 records exactly this divergence shipping as a silent regression for
  effects-only existing GIFs.
- Text renders in the GIF regardless of which category is active, and shows at rest on the canvas
  under other categories — inert, deselected, display link paused.
- Animation preset cards can render their own preview by compositing the shared tiles at a fixed
  mid-animation progress, reusing `EffectCardView`'s still-thumbnail initializer.

---

## 11. Implementation stages

Six, not five: the gesture layer earns its own gate, and the regeneration repair is sequenced
before it. Steps 1–4 are the risky half and are all headless and fully testable, so the gesture work
sits on a renderer that is already proven.

### Stage A — layout and raster foundation

`TextLayoutEngine`, `TextRasterizer`, the partition invariant, and the language tests. Nothing else
can be trusted until the invariant holds — no editor, no GIF, no gestures.

**Gate:** tiles partition the master for every granularity and decoration; Arabic joining, Latin
ligatures, and grapheme clusters all verified; layout is resolution-independent.

### Stage B — composition

`TextComposer.transform`, `TextTileCompositor`, endpoint and transform-algebra tests. Still
headless.

**Gate:** a static base image plus any overlay renders correctly at arbitrary progress, angle and
size, with no editor and no generator.

### Stage C — animation presets

The five `tileStates` evaluators, reviewed on a prototype grid using one short phrase over the same
zooming photo, at slow/default/fast zoom and 0/1/5-second pauses. Measure representative GIF sizes
against the same image without text and set the performance budget from that evidence.

**Gate:** approved preset curves and names; deterministic output; first frame has zero text; no
preset fights the photo zoom.

### Stage D — GIF pipeline

Extend `GIFGenerating` and both stubs; prepare one raster per generation; composite in animated and
pause frames; pass overlay state through `generateGIF` and `regenerateGIF`.

**Gate:** every preset renders in a real GIF, the full text holds through the pause, and
`textOverlay == nil` is byte-identical to the pre-change generator.

### Stage E — regeneration repair

§8.7, alone, with the suite green before and after.

**Gate:** a queued edit during regeneration is applied rather than dropped; the open P1 is closed.

### Stage F — gestures and editor UX

The container restructure with first-touch routing (no behaviour change to the photo, suite green),
then `TextOverlayHostView` and `TextGestureSession`, then the TEXT category, icon, preset carousel,
two-phase editor, three-row settings panel, canvas exception, Reduce Motion and VoiceOver.

**Gate:** a user can add, edit, move, scale, rotate, preview, undo, delete, reset, generate, save
and share text without losing existing zoom or effect settings; the photo's pan, zoom and
double-tap-zoom are unchanged from every other category; a straddling two-finger pinch follows the
finger it started under; one undo entry per gesture session.

### Stage G — hardening and release

Full suite; 1×/maximum zoom; every animator, modifier, visual and face effect; every pause speed;
short/long/multiline text, emoji, combining marks, Arabic/Persian, mixed direction, Dynamic Type
and large keyboard settings; generation time, peak memory and GIF byte size on the oldest supported
device class.

**Gate:** the acceptance criteria pass and nothing regresses when no text is selected.

---

## 12. Test plan

Swift Testing, pixel *measurement* on structured fixtures in the `LensDistortionTests` idiom. **No
reference images on disk.** What makes that work for text is that the master raster is computed in
process and *is* the reference, so "does the composite match" is a real assertion with nothing
checked in.

### 12.1 Why not snapshot tests

Revision 1 asked for snapshot tests at four progress values for every preset. The repo has no
snapshot infrastructure, `FEATURE-THEMES.md` §9 declines to add one, and the project's own
verification idiom is measurement plus a manual PNG dump harness. The architecture in §7 makes the
infrastructure unnecessary: parity is a property of sharing one layout and one transform function,
and that property is directly testable.

### 12.2 The load-bearing test

`tiles_partitionTheMasterRaster_withoutOverlapOrLoss` — for each granularity crossed with
{LTR multiline, RTL, emoji, OUTLINE, BLOCK}:

1. no two `pixelRect`s of `.cut` tiles intersect;
2. compositing every tile at alpha 1 and identity is **byte-identical** to `master`;
3. the union of `glyphIDs` is the full glyph set and every pairwise intersection is empty.

This one test kills overlap double-composite, dropped ink at seams, mis-derived seam positions,
local/pixel coordinate errors, and any future "optimization" that inflates tiles for decoration
bleed.

### 12.3 Language correctness

- `arabicJoining_survivesTiling` — lay out `"سلام"` as one string, and separately lay out each
  grapheme cluster in isolation; assert the **total ink pixel counts differ**. Isolated forms are
  geometrically different from joined ones, so equal counts would prove we re-shaped per cluster.
  This is the test that catches the fatal version of this design, and it needs no Arabic reading
  ability to interpret.
- `lamAlef_isASingleUnit` — `"لا"` is two clusters and one glyph, so exactly one unit. Pins the
  merge rule.
- `latinLigature_isNotSplit` — `"ffi"` in a ligating font yields one unit.
- `rtl_typesInLogicalOrderAtVisualPositions` — the first-typed unit is the rightmost while its
  `order` is lowest.
- `graphemeClusters_areNeverSplit` — ZWJ family emoji, regional-indicator flag, `e` + U+0301,
  skin-tone modifier: one unit each.
- `wordDrop_usesLinguisticTokens` — `"don't stop"` is two word tiles, not three.

### 12.4 Animation and transform algebra

Iterate `allCases`, never a hand-listed set — LEARNINGS 2026-08-07 and 2026-08-08 both record bugs
that per-effect tests missed and a cross-effect test caught.

- `everyPreset_atZeroProgress_rendersNoTextPixels` — composite over a known solid base and count
  differing pixels; zero. This also protects the product property that a saved GIF's first frame
  carries no text, so reopening it cannot duplicate the title.
- `everyPreset_atFullProgress_isBytewiseTheRestingRaster`.
- `tileStates` are finite across a 0…1 sweep, and clamp safely outside it.
- `flicker_withTheSameSeed_isIdentical`, and differs across seeds.
- `screenSpaceTranslation_survivesUserRotation` — θ = π/2 with RISE keeps the motion up-screen.
- `localScale_doesNotMoveTheTileCentre` — POP at peak.
- `restingTransform_isRotationThenPlacement` — p = 1 reduces to `S(1/k) · R(θ) · T(center · S)`.
- `exportPath_neverAppliesLiveScale`.

### 12.5 Resolution independence — the parity guarantee

`layoutIsResolutionIndependent` — prepare the same overlay at 600 and at 1200; assert every
`unit.inkRect / S` matches within 1e-6, unit counts and orders are identical, and the ink coverage
fraction of the two masters matches within 1%. Since preview and export differ *only* by
`pixelSize` and share the layout and the transform, this test is the parity guarantee, and it fails
loudly if anyone reintroduces a resolution-dependent constant.

### 12.6 Touch routing

Extract the decision from the view into a pure function — `route(firstTouch:hitRegion:) -> Route`
plus the lock/release rule — so it is testable without a touch harness.

- `route_isDecidedByTheFirstTouchOnly` — a sequence starting on the text stays `.text` even when a
  later touch lands outside, and vice versa. This is the straddling-pinch case, and it is the one
  bug in this feature that would only reproduce near an invisible boundary.
- `route_isReleasedOnlyWhenEveryTouchLifts` — with two touches down, lifting one must not re-arm
  the decision.
- `hitRegion_honoursRotationAndTheMinimumTouchTarget` — a 30° rotated overlay hit-tests against its
  rotated bounds, and a small overlay still presents at least 44 pt on each axis.
- `hitRegion_doesNotDependOnSelection` for routing purposes — an unselected overlay is draggable.

The UI-level counterpart is in §12.10; this is the part that can fail silently.

### 12.7 Gesture session

- `simultaneousPinchAndRotate_produceExactlyOneUndoEntry`.
- `cancelledGestureWithNoChange_pushesNothing`.
- `abortMidGesture_commitsExactlyOnce_andIsIdempotent`.

LEARNINGS 2026-08-08 warns that "pushes exactly one entry" tested through the model API cannot see a
second push wired up in the view. `TextGestureSession` is deliberately a pure reference type with
injected closures so the counting logic is on the tested path.

### 12.8 Geometry

- `settledCentre_isAlwaysInsideTheRestInset`.
- `trackingCentre_rubberBands_monotonicallyAndBounded` — never past `centreHardInset`.
- `maxFontSize_keepsThreeLinesInsideTheVerticalBudget`.
- `angleSnap_hasHysteresis` — sweep 0 → 0.12 rad → 0 and assert the detent sequence contains
  exactly one transition in and one out. The detent sequence *is* the haptic schedule, so this
  asserts "the haptic fires once" without mocking `HapticService`.
- `normalizedGeometry_at325_and600_agree`.

### 12.9 Pipeline and view model

- `nilOverlay_producesByteIdenticalGIF` against the pre-change generator on a fixed fixture.
- `addingText_changesNeitherFrameCountNorDelays`.
- `pauseFrames_areByteIdentical`, and identical to the final moving frame.
- `repeatedGeneration_isDeterministic`.
- Snapshots, undo/redo, reset and non-default detection include the overlay; whitespace-only text
  is not an active overlay.
- A queued regeneration during an in-flight one is applied (§8.7).

### 12.10 UI tests

The happy path, end to end: TEXT tab → tap a preset → keyboard appears → type → DONE → settings
panel → pick a colour → confirm → drag, pinch and rotate the text → generate → save and share.

Then the edges:

- **The two-phase session is one undo step.** Confirm creates exactly one entry; one undo removes a
  newly created overlay entirely. Cancelling from the settings phase removes a newly created
  overlay, and restores prior text and style when editing an existing one.
- **Double-tapping the text returns to the keyboard**, prefilled, and DONE returns to the settings
  phase rather than closing the session.
- **The photo is unchanged.** Pan, pinch-zoom and double-tap-zoom starting anywhere off the text
  behave exactly as under the visual-effects category — the direct comparison, not an assertion in
  isolation.
- **The straddling pinch** — one finger on the text, one off — scales the text, and the mirror case
  starting off the text zooms the photo.
- Delete and RESET remove both the live and the generated overlay.
- The keyboard on a short device leaves the field and DONE visible.
- Switching categories keeps the overlay, deselects it, and stops its display link.

### 12.11 Human visual review

Structural tests cannot catch what LEARNINGS 2026-08-07 calls the "verify by looking" class. Per
preset, dump PNGs at p = 0, .2, .35, .5, .7 and 1 over a real photo, at 0°/15°/90° and min/mid/max
size. Check Silkscreen crispness at POP's overshoot and at 45°, and the nearest-neighbour transient
during a live pinch. Measure GIF byte size and generation time with and without text on the oldest
supported device.

---

## 13. Accessibility and safety

- Respect Reduce Motion in the editor preview by showing the completed text state. The exported GIF
  may retain the chosen effect because it is authored media, but the choice should be explicit and
  previewable as a still.
- **Direct manipulation needs a non-gestural equivalent, and it is not optional.** Drag, pinch and
  rotate cannot be performed under VoiceOver. The selected text exposes an
  `accessibilityAdjustableAction` with a rotor to choose the axis — position, size, angle — and
  increment/decrement stepping each. This is deliberately not three panel rows: the panel holds
  three rows total (§10), and spending two of them mirroring gestures would leave no room for style
  or animation. The rotor is also the better VoiceOver design, since it scales to future axes
  without competing for panel height.
- Give animation cards descriptive VoiceOver labels such as "Rise, text fades in while moving
  upward," not only their names.
- Enforce a contrast floor for BLOCK and OUTLINE. NONE and SHADOW may warn, but should not silently
  change the user's selected colour.
- Keep the editor local and offline; the feature needs no permissions or network service.

---

## 14. Acceptance criteria

1. A user can create one text overlay, style it, and place, scale and rotate it directly on the
   canvas, choosing one of five entrance effects.
2. The photo pans, pinch-zooms and double-tap-zooms exactly as it does under every other category,
   whether or not text is selected. A gesture starting on the text moves the text; a gesture
   starting anywhere else moves the photo; a two-finger gesture straddling the boundary follows
   whichever it started on.
3. A simultaneous drag, pinch and rotate produces exactly one undo entry and one regeneration.
4. The live preview and exported GIF agree on placement, wrapping, size, angle, colour, decoration
   and animation timing.
5. Text entrance is synchronized to the zoom's moving frames, complete by 70%, and fully visible in
   every pause frame; the first frame contains no text.
6. Emoji, composed characters, Latin ligatures, multiline alignment and tested Arabic/Persian
   strings render with correct joining and no mid-animation reflow.
7. Undo/redo, Cancel/Done, RESET, regeneration, save and share all include text state.
8. An edit made during an in-flight regeneration is applied rather than dropped.
9. With no text overlay, rendering behavior and output are byte-identical to today.
10. Generation stays within the performance and file-size budgets established in Stage C.

---

## 15. Open decisions

- **Generation at 1× zoom.** The plumbing treats a text overlay as sufficient reason to generate,
  matching the dormant `nil`-animator path, but the shipped UI always has a zoom type selected, so
  the case is unreachable. Resolved for V1 as: wire it, do not claim it. Text rides the zoom
  animation, and a title over a motionless photo is not the product. If ROADMAP's "Zoom is always
  on" is ever reversed, note that `activeAnimator` returns a bare `StaticAnimator()` and silently
  discards the modifier.
- **Which parameter each preset exposes, and its range.** §5 names one per preset, but the ranges
  and defaults come out of the Stage C prototype rather than being guessed here.
- **Whether STYLE stays a segmented bar once fills arrive.** Four decorations fit a segmented bar;
  adding gradient and sparkle fills (§16) will likely push COLOR and STYLE together into one FILL
  row with its own detail step. Not a V1 problem, but do not paint the row layout into a corner.

---

## 16. Follow-on work, and what V1 leaves room for

### Fill effects — the intended next step

Animated gradients, static gradients and sparkle are all **fills over fixed glyph geometry**, which
is why §7.1 insists the coverage mask survives as a distinct step inside `prepare`. Given that, each
is a contained addition rather than a re-architecture:

| Effect | What changes | What does not |
|---|---|---|
| **Static gradient** | The fill drawn through the mask, once, at prepare time | Nothing else — it is a different `master`, same tiles, same transforms |
| **Animated gradient** | The fill becomes a function of `progress`, applied at composite time through the static mask | Layout, units, tiles, seams, transforms, the entrance presets |
| **Sparkle** | Per-frame deterministic particles clipped to the mask, seeded from `frameIndex` as the existing effects are | Same |

The natural home is a fourth panel row or a FILL segment replacing COLOR once there is more than a
swatch to choose. Note the interaction with GIF palette size: animated fills raise inter-frame
entropy, which is exactly what the Stage C byte-size budget exists to measure — extend that budget
rather than assuming the V1 numbers hold.

Fonts belong in the same wave: `TextFont` already carries five cases, so it is a picker plus a row.

### Deliberately deferred

- multiple independently timed text layers;
- per-word fonts or colours, mentions, hashtags, and rich text spans;
- custom keyframes, motion paths, separate In/Out/Loop animations, or a timeline;
- text that tracks a face or source-image feature through the zoom;
- curved or 3D text;
- chromatic or per-channel text effects — the CIImage stage already owns that look;
- reconstructing editable text/effect recipes after a saved GIF is reopened.

The clean follow-on after fills is **multiple layers plus a layer list**, not more entrance presets.
That is the point at which independent timing and ordering become necessary; adding those concepts
to a single-layer release would make the first interaction much heavier without validating demand.
The tile architecture is already shaped for it — a second overlay is a second `RasterizedText`
composited in order — but the editor cost is where the work actually is.

---

## 17. File manifest

The order is the stage order (§11), and it is deliberate: everything in Stages A–D is headless and
fully testable, so the gesture and editor work in Stage F lands on a renderer that is already
proven. Do not reorder Stage E — the regeneration repair is a prerequisite, not a neighbour (§8.7).

The project uses a `PBXFileSystemSynchronizedRootGroup`, so **new files need no `.pbxproj` edits**
(LEARNINGS 2026-03-08). Note that `Enhance/Fonts/` is excluded from the two test targets via
`membershipExceptions`, so any test that resolves Silkscreen runs in the *hosted* test target and
reads it from `Bundle.main` — which is `Enhance.app`, as EFFECTS.md notes.

### New

| Stage | Path | Contents |
|---|---|---|
| A | `Enhance/Models/Text/TextOverlay.swift` | `TextOverlay`, `TextFont`, `TextColorChoice`, `TextDecoration`, `TextAlign`. Colour is a semantic enum with UIKit + SwiftUI projections, never a stored `SwiftUI.Color` (§6). |
| A | `Enhance/Models/Text/TextLayoutLimits.swift` | Clamp, rubber-band and detent maths (§9). Pure value functions, no UIKit — the easiest file to test and the one to write first. |
| A | `Enhance/Services/Text/TextLayoutEngine.swift` | One `CTFramesetter` pass → `PreparedTextLayout`, `TextUnit`, `TextLine`. The shaping-safe unit merge (§7.2) and seam computation (§7.3) live here. |
| A | `Enhance/Services/Text/TextRasterizer.swift` | `RasterizedText`, `TextTile`. One decorated master raster through a coverage mask (§7.1), cut into non-overlapping tiles. |
| B | `Enhance/Services/Text/TextTileCompositor.swift` | `TextComposer.transform` — the single source of truth for placement (§7.6) — plus the export `CGContext` compositor. |
| C | `Enhance/Models/Text/TextAnimationType.swift` | The five presets, `granularity`, `peakScale`, `tileStates(at:layout:)` (§5, §7.6). |
| A–C | `EnhanceTests/TextLayoutTests.swift` | §12.2 partition invariant, §12.3 language correctness. **Write §12.2 and `arabicJoining_survivesTiling` first** — they are what the whole architecture rests on. |
| B–C | `EnhanceTests/TextAnimationTests.swift` | §12.4 endpoints and transform algebra, §12.5 resolution independence. |
| A, C | `EnhanceTests/TextGeometryTests.swift` | §12.8 clamping, sizing, detent hysteresis. |
| F | `Enhance/Components/TextGestureSession.swift` | §8.6. No UIKit import, so the undo-counting logic is directly testable (§12.7). |
| F | `Enhance/Components/TextOverlayHostView.swift` | `UIView` subclass: CALayer tile stack, `hitRegion`, the five recognizers, `CADisplayLink` (§8.8). |
| F | `Enhance/Assets.xcassets/icon-text.imageset/` | Template SVG — `template-rendering-intent: template`, no baked `fill-opacity` (LEARNINGS 2026-03-12/13). |
| F | `EnhanceTests/TextRoutingTests.swift` | §12.6. Extract `route(firstTouch:hitRegion:)` as a pure function so it needs no touch harness. |

### Modified

| Stage | Path | Change |
|---|---|---|
| D | `Enhance/Services/GIFGenerating.swift` | Add `textOverlay: TextOverlay?`. |
| D | `Enhance/Services/GIFGenerator.swift` | One `TextRasterizer.prepare` before both loops; composite after `applyVisualEffects` in `addAnimatedFrames` and `addPauseFrames` (§7.7). |
| D | `EnhanceTests/EditorViewModelTests.swift` | `StubGIFGenerator` — a compile-time witness for the protocol; update in the same commit. |
| D | `EnhanceTests/SaveGIFTests.swift` | `SaveStubGenerator` — the second witness. |
| E | `Enhance/Features/Editor/EditorViewModel.swift` | `regeneratePending` (§8.7), **on its own commit, suite green before and after**. |
| F | `Enhance/Components/ImageCanvasView.swift` | Representable root becomes a container `UIView` with the scroll view and text host as siblings; first-touch routing in `hitTest` (§8.2, §8.3). Move the scroll config verbatim — do not refactor `updateUIView` while in there. |
| F | `Enhance/Features/Editor/EditorViewModel.swift` | `textOverlay` in `EditorSnapshot`, `currentSnapshot`, `restore`, `resetEffects`, `hasNonDefaultSettings`, `hasEffectsWithoutZoom` **and** `regenerateGIF`'s `canRegenerate`; `beginTextGesture`/`endTextGesture`; `editingRowCount` gains `.text` → 3. |
| F | `Enhance/Features/Editor/EditorView.swift` | Fourth category tab with derived spacing; preset carousel; two-phase editor; three-row settings panel; the live-canvas exception in **both** `canvasSection` branches (§10). |
| F | `Enhance/Models/EffectCategory.swift` | Fourth case, `text`. |

### Reuse, do not rebuild

`EffectCarousel`, `EffectCardView` (including its still-thumbnail initializer for preset previews),
`EffectDetailPanel`, `SegmentedBar`, `ParameterSliderRow`, `EffectParameter` storage via
`parameterValues`, `HapticService`, `LaserColor` as the shape to copy for `TextColorChoice`,
`AppConstants.Layout.parameterRowHeight(forPanelHeight:rowCount:)`, `FontRegistration`, `Typography`.

### Verification once a Mac is available

There is no CI in this repo, so the suite is the only gate. Confirm it is **green on the untouched
baseline first** (LEARNINGS 2026-08-07 — a permanently red suite is worse than no suite), then work
the stages in order, keeping `main` fast-forwarded at each green stage as the project already does.
Stage C and Stage G both need a device: the preset review and the Silkscreen crispness checks in
§12.11 cannot be done from test output.

---

## 18. Implementation status

> **Stages A–F shipped; Stage G (hardening) is the remainder.** Full suite green (330/0) as of
> 2026-08-11. The A–C handoff note that lived here is deleted: it described getting a
> never-compiled renderer through its first build, which is long done.
>
> The spec above is the durable design. Where the shipped feature departs from it, the code is
> right and the prose is historical — those departures are listed below rather than edited into
> the earlier sections, so the reasoning that produced them stays legible.

### Where the shipped feature departs from this plan

| Plan | Shipped | Why |
|---|---|---|
| §10's three-row panel: COLOR, STYLE, per-preset tunable | **Two rows** — COLOR and the tunable, plus FROM (UP/DOWN) for SLIDE | STYLE cannot work yet. `TextRasterizer` fills one coverage mask with a single colour, so SHADOW renders in the text's own colour and BLOCK fills a plate over the glyphs. `TextDecoration` stays in the model until decoration draws through a second, contrasting fill. |
| §10: the TEXT category keeps the live canvas after ENHANCE | Live **only while editing** — typing or panel open — handing back to the GIF on confirm | Holding the live canvas permanently meant a generated GIF never appeared in the preview; it was visible only after saving. Positioning still happens with the panel open, which is when it is wanted. |
| §5's five presets: POP, RISE, TYPE, WORD DROP, FLICKER | POP, **SLIDE**, **TYPEWRITER**, **SPIN**, FLICKER | Device review. RISE and WORD DROP differed only by travel direction, so they folded into SLIDE with a direction toggle; that freed a slot for SPIN. TYPE became TYPEWRITER, and its SPEED control was inverted — higher now means faster. POP's single overshoot became a damped spring, since one soft overshoot read as a swell rather than a bounce. |
| §6: no recipe persistence | The overlay **is** persisted, per asset identifier | Text is authored rather than chosen from a card, so losing it means retyping. Safe because frame 0 of every entrance is empty, so the source rebuilt from it carries no text and a restored overlay cannot double up with the baked one. Does not yet cover a *first* save — that callback discards the new asset id (same P1 as zoom params). |

### Two traps this feature hit, which generalise

- **A full-canvas sibling view above the scroll view will swallow every touch.** `TextOverlayHostView`
  covers the canvas; until it overrode `point(inside:)` to answer only for the text's own rotated
  box, the photo could not be panned or zoomed *in any category*. UIKit's default hit test walks
  subviews in reverse order and the topmost full-bounds view wins.
- **`.whole`-granularity presets are cut as one tile spanning the entire raster.** Anything sizing a
  hit region, selection box or measurement must use `layout.inkBounds`, never the tiles — measuring
  tiles reports the whole canvas as "the text".
