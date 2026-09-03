# Motion effects — FRAME ECHO and effects that read real motion

> Plan, 2026-09-03. Nothing here is built. Builds on BURST CAPTURE (`BurstFrame`, the
> generator's frames path) and SCRUB THE PREVIEW. See HISTORY.md for both.

## The idea

A burst gives the app something it never had: **time**. Today every effect still sees one
frame at a time — the burst path swaps the *source* per output frame, but an effect applied to
frame 12 has no idea frame 11 existed, where the face was in it, or which way anything moved.

Two families of effect want exactly that knowledge:

- **FRAME ECHO** — earlier frames' subject cut-outs composited behind the current one at
  falling opacity, the sports-photo sequence look. Needs the *previous frames* and *a mask per
  frame*.
- **Effects that read motion** — motion blur along the direction the face actually moved,
  speed lines behind a moving subject, SHAKE amplified by the real camera shake. Need a
  *velocity* per frame: for the subject (from the face track) and for the camera (from frame
  registration).

So the plan is one foundation and then effects on top of it. The foundation is the expensive,
unglamorous part; each effect after it is a day.

## 1 — Foundation: `MotionContext`

### 1a. What effects get

```swift
/// Everything an effect may want to know about the frames around the one it is drawing.
/// Nil for a still, so every existing effect is untouched.
struct MotionContext {
    /// Index of the frame being drawn, and the burst it belongs to.
    let index: Int
    let frameCount: Int
    /// A previous frame's image, in the *same pixel space* as the frame being drawn.
    /// `offset` is frames back (1 = the one before). Nil past the start.
    func frame(back offset: Int) -> CIImage?
    /// That frame's subject mask, same space. Nil if segmentation found nothing.
    func mask(back offset: Int) -> CIImage?
    /// The current frame's mask.
    var mask: CIImage? { mask(back: 0) }
    /// Subject motion this frame, normalized units per frame (from the face track).
    let subjectVelocity: CGVector
    /// Camera motion this frame, normalized units per frame (from frame registration).
    let cameraVelocity: CGVector
}
```

`VisualEffect` grows a fourth overload with a default that ignores it — the same pattern
`geometry` used, so the thirty shipped effects need no edit:

```swift
func apply(to image: CIImage, progress: CGFloat, frameIndex: Int,
           viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage
```

**Same pixel space is load-bearing.** The generator's face pass shrinks the source per frame
(`prepareFaceEffectPass`), and the preview stack renders at 650px. `frame(back:)` and
`mask(back:)` return images already scaled to whatever the effect is drawing into, so an effect
composites them without knowing which path it is on. The context is built once per render by
the owner of that space (generator: per output size; preview: per preview source), and both
pass it to `applyVisualEffects` alongside `geometry`.

### 1b. A mask per frame

`SubjectSegmentationService` produces one mask for the still. A burst needs one per frame:

- Run per frame off the main actor when the burst is adopted, exactly as `burstFaces` fills
  in (`EditorViewModel.adoptBurst`), into `burstMasks: [CIImage?]`. Results land as they
  finish; an effect sees `nil` for a frame not done yet and draws without that echo.
- **Cost** is the risk. Vision person segmentation at `.balanced` on a 720px frame is roughly
  30–60ms on the 17 Pro, so 18 frames is about a second — fine — but an SE 3 could be 3–4×
  that. Segment at 360px (the mask is upscaled anyway) and measure on both phones *before*
  choosing the level; the number goes in HISTORY.
- **Memory**: 18 single-channel masks at 360px is under 3MB. Not a concern.
- **Temporal flicker** is the other risk: Vision's mask edges jitter frame to frame, and an
  echo stack makes jitter visible five times over. Mitigation, in order of cost: feather the
  mask (the compositor's `feather` already exists), average each mask with its neighbours
  (`0.25·m₋₁ + 0.5·m + 0.25·m₊₁`), drop to `.fast` quality if the edges are still noisy.
  Decide from a render, not in advance.

### 1c. The subject track

`burstFaces` already has a face per frame. A `MotionTrack` model turns it into velocities:

- Match faces across frames by nearest normalized centre (the same matching BIG HEAD uses
  for its per-face masks). A face that leaves the frame ends its track; a new one starts.
- `subjectVelocity(at: i)` = centre(i) − centre(i−1), smoothed with an EMA (α ≈ 0.5) so a
  detection wobble does not read as a jerk. In normalized units, so it is resolution-free.
- No face → zero velocity. **Falls back to the camera velocity below**, so a burst of a cat
  still gets motion-aware effects from whatever moved.
- Pure and tested: three fixture tracks (still, drift, dart), asserting direction and
  magnitude.

### 1d. The camera track

For "SHAKE amplified by real shake" and for the no-face fallback, we need the whole frame's
motion between consecutive frames. `VNTranslationalImageRegistrationRequest` does exactly
this, cheaply (a few ms per pair at 360px), and returns a translation in pixels. Run it in the
same background task as segmentation; store per-frame translations; `cameraVelocity` is the
normalized translation, smoothed the same way.

### 1e. Plumbing

| where | change |
|---|---|
| `EditorViewModel` | `burstMasks`, `burstTrack`, `burstCameraTrack` filled beside `burstFaces`; `burstSourceFrames` carries them; the burst preview stack builds a `MotionContext` per frame |
| `BurstFrame` | gains `mask: CIImage?`, `subjectVelocity`, `cameraVelocity` |
| `GIFGenerator` | builds a `MotionContext` per output frame in the burst path (frames scaled into the pass's space, cached — the same `BurstSource` cache that holds face passes) and passes it to `applyVisualEffects` |
| `VisualEffect` | the fourth overload, default ignores `motion` |
| `FeatureFlags` | `featureMotionEffects` gates the new cards |
| CANVAS LAB | a MOTION FX section: segmentation size, mask feather, neighbour smoothing on/off, velocity smoothing α, echo maximum |

**Done when:** a burst adopted in the editor reports a mask and a velocity for every frame in
the debug log, the generator's burst path hands every effect a non-nil context, and no
existing effect's output changes by a byte (the `stillPathIsUnchangedByTheFramesOverload`
test pattern, extended to visual effects).

## 2 — FRAME ECHO

The first card, because it exercises every part of the foundation and its look is the least
ambiguous.

- **Render**: for echo `k` in 1…N, take `frame(back: k·spacing)` cut out by
  `mask(back: k·spacing)`, at opacity `fade^k`, optionally tinted (`LaserColor`, or none), and
  composite them **behind** the current subject: current frame → echoes oldest-first → current
  subject cut-out re-drawn on top so an echo never covers the person. Cost per frame is N+1
  mask composites — cheap next to the face pass.
- **Params** (the panel): ECHOES 1…6, SPACING 1…4 frames, FADE, TINT (six swatches plus
  NONE). Three to four rows; the panel scrolls.
- **Stills**: the card is burst-only. On a still it does not appear in the carousel; if a
  burst is adopted and then cleared the selection falls back to ORIGINAL (the
  `clearSingleFaceFilterIfNeeded` pattern). A hint pill says HOLD THE SHUTTER FOR A BURST the
  first time the VISUAL tab opens without one.
- **Preview**: the burst preview stack already renders the effect on every frame; with the
  context it shows the echoes.
- **Tests**: a synthetic burst of a square moving right; assert the composited frame carries
  colour at the echo positions and not elsewhere, and that a nil mask draws no echo.

## 3 — Effects that read motion

Each of these is a small change to an existing effect, gated on `motion != nil`:

- **MOTION BLUR follows the motion.** `MotionBlurEffect` gains: angle from
  `subjectVelocity` (falling back to the camera's, then to the slider), radius scaled by
  speed. Applied to the whole frame as today, with a BLUR SUBJECT ONLY toggle that uses the
  mask — the same toggle shape as BACKGROUND ONLY. The slider's ANGLE becomes a fallback and
  is labelled so.
- **MOTION TRAIL.** A new card: the previous `n` subject cut-outs blurred along their own
  velocity and composited behind at falling opacity. FRAME ECHO with a smear — shares its
  code; the difference is one `CIMotionBlur` per echo. Likely the better-looking of the two
  for fast motion and the worse for slow.
- **SPEED LINES.** Comic-style: a wedge of streaks radiating from the subject's trailing edge,
  opposite to `subjectVelocity`, length by speed. `CIStripesGenerator` rotated to the motion
  angle, masked by an eroded copy of the subject mask shifted backwards along the motion, so
  the lines start at the body and fade out. A kernel would be tidier; try stock filters first
  (LEARNINGS: LENS proved the stock path reaches further than expected).
- **SHAKE reads the shake.** `ShakeModifier` gains an amplitude input from
  `cameraVelocity` magnitude: still footage shakes as the slider says, a shaky burst shakes
  more, and REAL SHAKE ONLY on the panel zeroes the synthetic part so the GIF only exaggerates
  what the camera did.

Order: MOTION BLUR first (smallest change, proves the velocity is right), then MOTION TRAIL
(reuses FRAME ECHO), then SPEED LINES, then SHAKE.

## 4 — Sequence and cost

| phase | scope | rough size | visible? |
|---|---|---|---|
| 0 | `MotionContext`, per-frame masks, subject + camera tracks, plumbing, lab knobs | 2 days | no |
| 1 | FRAME ECHO | 1 day | yes |
| 2 | MOTION BLUR follows motion | ½ day | yes |
| 3 | MOTION TRAIL | ½ day | yes |
| 4 | SPEED LINES | 1 day | yes |
| 5 | SHAKE reads the shake | ½ day | yes |

Phase 0 ends with a device pass whose only output is numbers: segmentation ms per frame on
both phones, registration ms per pair, memory. Those decide the mask resolution and whether
neighbour smoothing is on by default. Every later phase ends with a render shown before it is
polished (ROADMAP's standing rule: three effects were declined on look, none on capability).

## 5 — Risks, in the order they would bite

1. **Mask flicker between frames** — visible in every echo. Mitigations in §1b; judged from a
   render of a real burst, not a synthetic one.
2. **Segmentation time on the SE 3.** If 18 frames takes more than ~3s there, segment at 240px
   or every other frame and interpolate; the echo effect only needs a soft silhouette.
3. **Preview stack cost.** Echo composites per frame could double the stack render. It already
   runs at utility QoS and yields to generation; if it lags, render the stack at 480px for the
   motion cards.
4. **Face track gaps.** A face turned away drops out of Vision for a few frames; the EMA
   carries the last velocity through short gaps, and a gap longer than three frames zeroes it.
5. **Burst persistence** is still a recorded limit: none of this survives a save-and-reopen.
   That is a separate piece of work and should come before these effects are relied on.

## 6 — Open questions

- Should FRAME ECHO ever show on a still? It could fake echoes by offsetting the single mask
  along a chosen direction — a poor cousin. Leaning **no**: burst-only keeps the card honest.
- Tinted echoes (the ECHO card's outline colours) or natural? Offer both; default natural.
- SPEED LINES as blur trail or as drawn lines? Build TRAIL first since it is nearly free, and
  decide whether LINES is still wanted after seeing it.
