# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-08-11 (session 17 — restructured; accuracy sweep against the code)

## Vision

Enhance is built around a simple creative flow:
**choose a photo → define a focal point → generate motion → refine → save or share.**

Each step should feel fast, tactile, and visually satisfying.

---

## How to read this file

Four sections, ordered by what unblocks what — **not** by phase number. The old numbering survives
only in [HISTORY.md](HISTORY.md), because it had stopped describing any real order (17e sat in
front of 17h and 17i; 19b and 19c predate 20).

1. **[Foundations](#1--foundations)** — work that unblocks other work. Every item names the
   dependent it unblocks. An item that cannot name one belongs in §3.
2. **[Effects](#2--effects)** — classified by *what blocks them*, since kernel-vs-not stopped
   predicting anything (see the note in §2).
3. **[Product bets](#3--product-bets)** — judged on upside. Nothing is waiting on them.
4. **[Defects](#4--defects)** — judged on accruing cost. Kept apart from §3 deliberately: a
   feature always looks more appealing than a bug, so they must not compete in one list.

**Device verification is tracked per item**, not in a separate list. In this project an effect is
not done when it compiles — THIRD EYE took several device passes and each one changed constants.
Items marked 🔍 are landed and green but never confirmed on hardware.

> **Docs:** [EFFECTS.md](EFFECTS.md) — how to build an effect, and what is worth building.
> [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) — the design-system audit and phased plan.
> [LEARNINGS.md](LEARNINGS.md) — rules discovered the hard way.
> [HISTORY.md](HISTORY.md) — everything already shipped, and why.
> Feature plans: [TEXT-EFFECTS](FEATURE-TEXT-EFFECTS.md) · [THEMES](FEATURE-THEMES.md) ·
> [LENS](FEATURE-LENS-DISTORTION.md) · [SCRAMBLER](FEATURE-SCRAMBLER.md) *(historical)*

---

## Pick up here

**State:** `main` has LENS, THIRD EYE, text-overlay Stages A–F, and the design-system plan.
The pattern is to commit on a branch and fast-forward `main` at each green stage, so Xcode always
sees a working build.

**The next three things, in order:**

1. **The control audit** (§2d) — eight of the nine hidden parameters fit the panel as it stands.
   No panel work is wanted; three rows is the ceiling and the audit lives inside it.
2. **Then the new effects** (§2a) — SLICE SHIFT and HATCHING, both ready, no new infrastructure.
   (BOKEH was declined on 2026-08-11; don't lead with it.)
3. **CI running the test suite** (§1b) — four sessions share this repo with no automated gate.

> **A note on trusting this file.** A 2026-08-11 sweep checked every load-bearing claim against the
> code and found six wrong — one of which actively instructed a future session to revert a repaired
> bug. Claims here now carry a file and line where one exists. **If you find one that disagrees
> with the code, the code wins and the doc is the defect** — fix it in the same commit.

---

## 1 — Foundations

Work that unblocks other work. **Entry bar: each item names what it blocks.** This bar exists
because the project has already been burned once — the old Phase 17e sat in front of every
interesting effect for months on the assumption that Figma shader effects need custom kernels,
which LENS then disproved by reconstructing one from about eight stock Core Image nodes.

**Bugs that get worse with new infrastructure belong here, not in §4.** Precedent: the face-effect
render cost was filed as a P2 nit, then continuous speed shipped and
`frameCount = max(12, Int(1/speed/0.04))` turned ~25 frames into 100 at 0.25× — the same bug, four
times worse, and by then gating two features.

### 1a. The panel row budget — a constraint, not a task ✓ closed

**No panel changes are wanted.** *(User's call, 2026-08-11.)* Raising the panel's height, lowering
the 34pt floor, and capping effects at three rows were all considered and **all declined** — the
panel works, and the control audit fits inside it. This section stays only to record the ceiling
everything else must respect.

Computed from `PanelMetrics.swift:35-41` (grid 16, small 8, floor 34pt, cap 44pt), the panel height
needed before rows floor and the content overflows:

| rows | minimum panel height | on an SE 3 (~190pt) |
|---|---|---|
| 3 | 192pt | **fits — verified on device 2026-08-11** |
| 4 | 234pt | does not fit |
| 5 | 276pt | does not fit |

**The working ceiling is three rows.** Four will not render on the shortest supported device, so
`parameters.count <= 5` remains an assertion that permits layouts nothing can display — left as-is
deliberately, since nothing is allowed to reach it.

Two things to respect rather than fix:

- **Row count is not fixed per effect.** TEXT's `editingRowCount` returns 2 normally and 3 with
  SLIDE's direction toggle, so a category can change row count at runtime. TEXT is therefore
  *already at the ceiling*, and any future per-preset control there overflows without anyone
  touching panel code.
- **The gesture conflict is unverified and now unreachable.** If rows ever do floor, the
  `ScrollView` turns on and competes with `DragGesture(minimumDistance: 0)`
  (`ParameterSliderRow.swift:95`). The two code comments describing what happens next contradict
  each other on which gesture wins — `PanelMetrics.swift:5-10` says the drag loses,
  `EffectDetailPanel.swift:45-52` says it wins and then concludes it scrolls anyway. Nothing can
  reach it at three rows, so it stays a curiosity unless a fourth row is ever wanted.

### 1b. CI running the test suite → protects every parallel session

[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) §3a sequences CI *after* its Phases 1–2, because the **lint**
rules assume the colour literals are gone. Running `xcodebuild test` carries no such dependency,
and there is no automated gate on this repo today.

**A concrete instance of what this catches** *(2026-08-11)*: two sessions running simulators at once
starved the machine enough that
`EditorViewModelTests/generateZoomPreviewImage_afterAnEarlyNoOp_stillBuildsWhenTheSourceArrives`
took **154s and 258s wall-clock against a 2-second poll budget**. It passes in isolation and in a
quiet full run — a genuine flake, not a regression. Poll since widened to 10s (assertion unchanged;
it still exits the moment the image appears, so the happy path costs nothing). **Four sessions
sharing one machine is exactly the environment where a timing assumption rots**, and nobody found
this by reading the test — they found it by tripping over it. A runner with a known load profile is
where that belongs.

- [ ] **Split test-only CI out and do it now** — a macOS runner on `xcodebuild test`. Lint follows
      later, with the token migration.
- [ ] Sweep the suite for other wall-clock assumptions once CI exists — this one was found by
      accident, so it is unlikely to be the only one.

### 1c. CIKernel de-risking gate → blocks Riso Print, Water Caustic, Hatching styles

Split out of the old Phase 17e. The risk in that phase was never the effect math — it is that a
target-scoped `-fcikernel` reaches `Shaders/Pixellate.metal` and **breaks the animated canvas border
at runtime**. Decoupled, the gate is about an hour, and it converts the rest into ordinary work.

- [ ] Build rule scoped to `*.ci.metal`, so the flag cannot reach `Pixellate.metal`.
- [ ] Passthrough kernel, then confirm the border still renders in **both** `EditorView` and
      `GradientViews`, before any effect math is written.

### 1d. Design system, Phases 1–2 → blocks themes (§3b)

Tokens, then migration onto them. Pure refactors with **zero intended visual change** — each token
equals the literal it replaces, so the app should render pixel-identical. Full plan in
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md); the audit scores the current system 1.5 / 5.

- [ ] **Phase 1 — tokens.** Extend `Design/Colors`, `Constants`, `Typography`; add
      `Design/Motion.swift`; route existing components through them via 1:1 swaps. Self-contained.
- [ ] **Phase 2 — migrate the duplicated patterns.** A `Surface` primitive; move the inline
      `0x202020` pills and the inline Silkscreen fonts onto tokens.
- [ ] **Re-derive the plan's `EditorView` line references first.** They were captured 28 commits ago
      and text overlays has since rewritten that file: `EditorView.swift:726` and `:765` no longer
      point at what the plan says, while the `GalleryView` and `SettingsView` references still hold.
      Prefer symbol anchors over line numbers in a doc that will outlive several refactors.
- [ ] **Re-measure the literal count, with a stated method.** FEATURE-THEMES claims ~340 across ~22
      files; the reproducible counts are **192 across 28 files** excluding `Services/Animators/**`,
      or **253 across 44** including it. The file count — the number that sets migration scope — is
      understated either way.

### 1e. Return the new asset id from the save callback → blocks zoom params *and* text restore

*Promoted from §4 on 2026-08-11, at the text-overlay session's suggestion.* One structural gap
serves two features, which is exactly the entry bar for this section — and while it sat under P1
Correctness it was competing with polish bugs it will always out-rank.

> **This is no longer latent — it is the cause of a reported bug** *(2026-08-11)*. Edit a gallery
> GIF that already has text, change any effect, and **the text silently disappears**. The chain:
> "SAVE NEW COPY" could not store the overlay because there was no asset id, so the reopened editor
> has `textOverlay == nil` while the words are baked into the pixels — and the first regeneration
> rebuilds from the textless frame 0. **Claimed by the text-overlay session**, which is in
> `GIFLibraryService`, `PhotoManager` and `EditorViewModel.saveGIFToLibrary`.

`saveGIFToLibrary`'s callback does not return the new `PHAsset` identifier, so there is **no key to
store anything against** after a first-time save. Two consequences, found independently:

- **Zoom params are never persisted for new saves.** `persistZoomParams` is called only from
  `updateOriginalGIF` (`EditorViewModel.swift:812`); `saveGIFToLibrary` — first-time saves *and*
  "SAVE NEW COPY" — never calls it, so re-opening falls back to a hardcoded
  `scale = 2.0, rect = (0.15, 0.15, 0.7, 0.7)` (`:632`).
- **A first-time save cannot restore its text overlay**, for the same reason (§3a).

- [ ] Thread the created asset identifier back through the save callback, then have both
      persistence paths key off it. Do this once rather than twice.

### 1f. Effect-carousel thumbnail cost → worsens with every effect added

Already at 11 thumbnails, up from 8. Each new effect in §2 makes it worse, which is what puts it
here rather than in §4.

- [ ] 🔍 Whether entering the IMAGE tab stutters while thumbnails render, and the scroll feel of a
      20-item carousel.

---

## 2 — Effects

> **Why the classification changed.** The old axis was "does this need a custom kernel," and it
> stopped predicting anything. LENS was assumed to need one and needed eight stock nodes. Water
> Caustic was filed as an easy catalog fill and is the one candidate that genuinely cannot be built
> stock. Pattern Refraction and Pixel Stretch were filed as kernel work without anyone checking
> whether `CIDisplacementDistortion` covers them. The axis is now *what actually blocks this*.

Build mechanics, per-effect specifications, and the candidates deliberately rejected live in
**[EFFECTS.md](EFFECTS.md)**. This section tracks status only.

### 2a. Ready to build — stock filters, no new infrastructure

- ~~**BOKEH (face-aware)**~~ — **not wanted, 2026-08-11.** Cut on the user's call before any code
      was written; nothing was built and nothing is owed. The analysis below is kept because it is
      the reason the *approach* is cheap, not the reason the effect is wanted — if it is ever
      revived, none of it needs re-deriving. **Do not re-propose it as "the obvious next build"
      without asking**; it has been declined once. `CIMaskedVariableBlur` grades blur by
      mask value, so blur falls off with distance from the face and reads as depth rather than as a
      cutout; feed it `FaceRegionMaskBuilder`, which THIRD EYE already left behind. This is the only
      candidate that adds a *capability* — subject-aware depth of field — rather than another
      surface treatment, and the source shader cannot do it because it has no notion of a subject.
      Only the highlight weighting is kernel-only, and that approximates stock (threshold
      highlights → blur separately → add back). **Open design call:** it is face-dependent so it
      belongs in the face carousel, but unlike THIRD EYE it should *degrade* rather than vanish on
      estimated landmarks — a blur does not need precise geometry.
- [ ] **SLICE SHIFT** — bands displaced along an angle with per-band jitter, seeded from
      `frameIndex`. Strip compositing avoids a kernel; this existed in the project before as
      `GlitchEffect`, doing exactly that. Animates strongly across frames, which little else does.
      Watch the node count if soft band edges need per-band gradient masks.
- [ ] **HATCHING (straight lines)** — `CILineScreen` / `CIHatchedScreen` take angle and width
      directly, which is closer than the `CIEdgeWork` route EFFECTS.md suggests. Three screens at
      15°/45°/75°, each masked by a luminance band, composited with darken. Grid effect: needs
      `FrameGeometry` for scale **and** phase, or it crawls exactly as DITHER did.

### 2b. Needs a spike first

- [ ] **Test whether `CIDisplacementDistortion` covers Pattern Refraction and Pixel Stretch.** Both
      are per-pixel UV remaps, which is what a displacement map expresses: build the procedural
      height field as a CIImage, displace by it, and run three passes at different scales for
      per-channel dispersion — the same trick LENS uses with `CIZoomBlur`. If it works, both leave
      §2c and the kernel gate's remaining justification narrows sharply.

### 2c. Blocked on the kernel gate (§1c)

- [ ] **Riso Print** — the most distinctive look available, and the best fit for the pixel-art
      identity. The original WGSL is in hand at `reference/riso-print.wgsl`; port from that, not
      from prose. Tonal-band separation, not CMYK. It fits the parameter budget only by reusing
      `GradientStops` for its three spot colours — **re-check that against §1a before starting**,
      since it needs four sliders plus a picker.
- [ ] **Water Caustic** — *reclassified 2026-08-11.* Core Image has no caustic and no
      Worley/Voronoi generator. `CICrystallize` makes Voronoi-ish cells but exposes no seed or
      phase, so it cannot flow across frames, and blurred noise is ruled out by the smeared-noise
      rule in LEARNINGS. This is the effect that most needs the kernel.
- [ ] **Hatching line styles** — wave, zigzag, concentric. Arbitrary substitutions into the `sin`
      argument, with no stock equivalent. The straight-line version in §2a needs none of this.

### 2d. Control audit — **next up**, and it fits

Nine shipped effects collapse independent qualities into one INTENSITY slider, or hardcode a value
a user would reasonably want to change. Candidates are named with file and value in
[EFFECTS.md → Control audit](EFFECTS.md#control-audit--effects-with-hidden-parameters).

**Eight of the nine fit inside the verified three-row ceiling** — checked against each effect's
current row count, not assumed. An earlier version of this section called most of them blocked;
that was written while three rows was still believed marginal.

| effect | rows now | adds | after |
|---|---|---|---|
| MOTION BLUR | 1 | ANGLE | 2 |
| SWIRL | 1 | SIZE | 2 |
| CHROMA SHIFT | 1 | ANGLE | 2 |
| RAINBOW | 1 | SPEED | 2 |
| PIXELATE | 1 | SHAPE | 2 |
| HALFTONE | 1 | SHARPNESS + ANGLE | 3 |
| HEAT HAZE | 1 | FREQUENCY + SPEED | 3 |
| GRADIENT | 2 | MIDPOINT | 3 |
| **DITHER** | 2 | LEVELS + MONO | **4 — over** |

- [ ] **The eight that fit**, in rough value order: MOTION BLUR (ANGLE — a directional blur whose
      direction is hardcoded to 45°), SWIRL (SIZE — a parity gap, FISHEYE already exposes it),
      HALFTONE (SHARPNESS + ANGLE, both already supported by `CICMYKHalftone`), CHROMA SHIFT
      (ANGLE), HEAT HAZE (FREQUENCY + SPEED), GRADIENT (MIDPOINT), RAINBOW (SPEED, which the face
      variant already has), PIXELATE (SHAPE — `CIHexagonalPixellate` makes hex nearly free).
- [ ] **PIXELATE's SHAPE is not a `Double`** and must not be stored as a case index — typed property
      on the view model plus an `EditorSnapshot` field, per LEARNINGS 2026-08-10. It is the only one
      of the eight that is more than a slider.
- [ ] **DITHER: ship LEVELS, defer MONO.** LEVELS is the one that decouples posterisation depth from
      dither amplitude, which is the actual complaint; MONO is a look, and a fourth row cannot
      render. Revisit only if the panel ceiling ever moves.
- [ ] Prefer **splitting coupled qualities** over inventing new ones. Most of these are one slider
      driving two independent things; separating them makes currently-unreachable looks reachable
      without changing what the effect is.

### 2e. Follow-ups on shipped effects

- [ ] **THIRD EYE's ray colour should follow the COLOUR pick.** Currently hardcoded warm gold while
      the eye tints. LAZER EYES tints its whole glow, which is part of why it reads as cohesive.
      One `CIColor` in `ThirdEyeEffect`.
- [ ] **THIRD EYE edge cases**, opportunistic: the 4× 12-frame floor across Zoom In/Out/Pulse, and
      the animal/estimated-landmark fallback — it works from a pupil plus eye width, so it should
      degrade rather than vanish.
- [ ] 🔍 **DITHER motion during the zoom.** Cell size scales with `FrameGeometry.scale` and phase
      follows `contentOrigin`; the mechanism is proven by `dither_phaseIsPeriodicInCellSize`, but
      the result has never been watched in a real GIF. **If it still crawls, the prime suspect is
      the Y-flip in `GIFGenerator.frameGeometry`** — that line was reasoned about, not measured.
      Log `contentOrigin` per frame and confirm it moves monotonically with the pan.
- [ ] 🔍 **DITHER legibility after GIF palettisation** — does the stipple survive 256-colour
      quantisation, or read as noise? The SCALE slider is the first lever if it needs help.
- [ ] 🔍 **GRADIENT colour wells** — confirmed working, but never seen alongside the rest of the row
      on device.

---

## 3 — Product bets

Judged on upside; nothing is waiting on them.

### 3a. Animated text overlays — **owned by another session**

Stages A–F are on `main`. Full plan in [FEATURE-TEXT-EFFECTS.md](FEATURE-TEXT-EFFECTS.md)
(revision 2).

- [ ] **Stage G — hardening.** Emoji, composed characters, ligatures, multiline and RTL, plus
      profiling on the oldest supported device. Known gaps from device testing: preset cards render
      blank thumbnails; edge clamping has no rubber-band and rotation no haptic detents; no
      VoiceOver adjustable actions. Two carry beyond this section — **STYLE is withdrawn** until the
      rasterizer can draw decoration in a second contrasting fill (a shadow currently renders in the
      text's own colour), and a **first-time save cannot restore its text** because the save
      callback discards the new asset id, which is the same blocker as the zoom-param persistence in §1e.
- [ ] Deliberately after V1: **fill effects** (static and animated gradients, sparkle) and **font
      choice**. `TextFont` already models five cases; V1 ships Silkscreen Bold and no picker. The
      rasterizer keeps the glyph coverage mask as a distinct step so the seam is in the right place.

*Status here is intentionally thin — that session maintains it.*

### 3b. Themes — a migration, not a feature

Blocked on §1d. [FEATURE-THEMES.md](FEATURE-THEMES.md) holds the slot contract, the staged
migration, and the boundaries of what must *not* follow a theme.

- [ ] Appearance (light / dark / system) × user-authored colour schemes. Colours only.
- [ ] Custom app icons — pick a GIF from the gallery, set its thumbnail as the app icon.
- [ ] Pixel-art icons for the remaining UI elements.

### 3c. Design system, Phase 3 — beyond the CI split in §1b

- [ ] SwiftLint banning raw colours and fonts outside `Design/` (needs §1d complete to pass).
- [ ] A `ComponentGallery` catalog, and `#Preview`s for the 13 of 19 components that lack them.
- [ ] Snapshot tests and an accessibility baseline. **Note this will not cover effects** —
      EFFECTS.md is blunt that structural tests cannot see a wrong-looking effect, and both
      `extent ==` and `createCGImage != nil` passed while EDGES rendered cyan instead of green.
      Effect verification stays render-to-PNG-and-look, plus device QA.
- [ ] `AGENTS.md` — the contribution rules, enforceable once the lint exists.

### 3d. Effect reuse and stacking (needs design)

Both are more feasible than they look, because groundwork landed for other reasons.

- [ ] **Copy settings between photos.** `EditorSnapshot` is already the payload, and undo/redo
      round-trips it; the work is deciding what *not* to carry. `selectedFaceIndex` is meaningless
      on another photo, zoom should stay out, and a face filter pasted onto a faceless photo needs a
      defined outcome. **In-session copy avoids a migration concern that saved presets do not** —
      parameter ids are in-memory only today, so the "ids must not change once shipped" warning does
      not yet bite. Persist `GradientStops.resolved`, never the SwiftUI `Color`s.
- [ ] ⚠️ **Stacking reverses a documented decision.** The pipeline already supports it —
      `generateGIF` takes `[VisualEffect]`, chained lazily, so N effects still cost one render per
      frame — and values are keyed per effect, so each keeps its own settings. Only the single
      optional `selectedVisualEffect` stands in the way. But effects *were* stackable and were
      deliberately made exclusive: LEARNINGS 2026-03-08 records that chained CIFilters "produced
      unpredictable, unpleasant results." **Read that entry before starting.** Its own suggested
      path — curated presets rather than free-form combination — is the cheap first step, with the
      same visual payoff and no new UI concept to invent. Order matters either way; CIFilter chains
      are not commutative.

### 3e. Other bets

- [ ] **Effects rethink** (needs design): an IG-style colour-filter category; auto-zoom toward a
      detected face when no zoom is set; and making "toggle off all zoom types" reset the canvas to
      1× rather than holding the user's position.
- [ ] **Onboarding**: five default photos demonstrating the app; a "give the gift of a GIF" viral
      unlock for face effects.
- [ ] **Settings & social**: RATE THE APP (`SKStoreReviewController`), SHARE WITH FRIENDS.
- [ ] **Editor UX**: a stateful save button; pause/edit during preview playback; RESET/X spacing in
      the header (RESET currently reads as a label for X); a crosshair showing the zoom focal point;
      fix the action-button copy.
- [ ] **New animation styles**: Bounce, Dramatic Zoom, Loop Zoom.
- [ ] **UNDO for existing-GIF editing** — revert all changes back to the saved original.
- [ ] **Real-time preview via Metal shaders** (iOS 17+ `.colorEffect()` / `.distortionEffect()` /
      `.layerEffect()`), replacing the CIFilter preview path. Note this is a *preview* technology
      and cannot render GIF frames — it does not substitute for §1c.

### 3f. Open questions — decide either way, then record it

- [ ] **`ColorPicker` aesthetics.** The system colour wheel is a modal iOS sheet, against Silkscreen
      pixel-art styling. Accepted deliberately for the colour freedom; revisit if it grates in use.
- [ ] **Zoom is always on.** One of the three zoom types is always selected; there is no NONE card.
      **Consequence: effects-only GIFs at 1× are impossible.** The `nil`-animator paths are kept
      intact but unreachable (`EditorViewModel.swift:444, 957, 980, 1036`), so reversing this is a UI
      change rather than a re-implementation. **If it is re-exposed, note that `activeAnimator`
      returns a bare `StaticAnimator()` and silently discards the modifier** — that path was already
      broken before it became unreachable.
- [ ] **Undo does not capture zoom.** `EditorSnapshot` has no `currentScale` / `visibleRect`, so
      pinch/pan is not undoable, and undo after a zoom restores effects against different framing.
      May be intentional — needs a decision either way.

---

## 4 — Defects

Ordered by severity. Each names the file where the defect lives. Found by code review unless marked
*(user-reported)*.

### P0 — Data loss (perceived)

**Gallery GIFs disappear after the app sits unused** *(user-reported)*. Four defects composed into
one failure; the assets were never lost, but the gallery could not re-resolve them and then deleted
its own cache. **Stage A is fixed** — see [HISTORY.md](HISTORY.md) for the four causes and their
repairs. Stage B remains:

- [ ] **Decouple display from URL resolution.** A GIF is still shown only when *both* thumbnail and
      URL resolve (`GIFLibraryService` intersection, `GalleryView.swift:50`), so any future URL
      failure still drops it from the grid — the trigger is fixed, the failure *mode* is not.
      Replace the three parallel arrays with one `[GifItem]` (`assetIdentifier`, `thumbnail`,
      `url: URL?`) and resolve lazily on tap. Around 9 sites in `GalleryView`.
- [ ] **Consider moving originals out of `Caches/`** to `Application Support/MyGIFs/` with
      `isExcludedFromBackup = true`, so iOS never purges them in the first place.

### P1 — Correctness

- **Newly-saved GIFs never persist their zoom params** — **moved to §1e**, because the same
  missing asset id also blocks text-overlay restore. One fix, two features.
- [ ] **Saving a photo sometimes uses a different photo's frame** in the gallery thumbnail.
- [ ] **Onboarding tagline truncates on SE 3** — "DRAMATIC ZOOMS AND S…". A fixed font size against
      a narrower screen.

### P2 — Performance

- [ ] _(deferred)_ **Frame streaming** — decode GIF frames during playback instead of loading all of
      them into memory.
- [ ] _(deferred)_ **Profile and reduce GIF generation time** — CGContext reuse, parallel frame
      rendering.

### P3 — Polish

- [ ] **`previewProgress` is implemented three times, and two of them are identical.** A card
      sampled at one shared instant misrepresents any effect that peaks at a different time, so
      each card-bearing type has grown its own answer:
      `VisualEffectType.swift:119` and `FaceFilterType.swift:78` are the *same logic with
      paraphrased comments* (`pixelate → 0.2`, everything else `1.0`), and
      `TextAnimationType.swift:122` is the same concept with genuinely per-case values.
      **Both duplicates conform to `ParameterizedEffect`** (`EffectParameter.swift:86`) and nothing
      else does, so folding them into a protocol default — 1.0, overridden per type — is a few
      lines rather than a refactor. The text one is legitimately separate; leave it, but have it
      point at the shared idea.
      *Who hits this next:* whoever adds an effect that peaks anywhere but full strength. They will
      edit one enum, ship, and find the other card still wrong. That has now happened twice.
- [ ] **"NO FACES DETECTED" toast repeats.** `detectFacesIfNeeded` guards on `detectedFaces.isEmpty`
      (`EditorViewModel.swift:346`), which stays true forever when detection legitimately finds
      nothing, so every return to the face tab re-runs detection and re-toasts. Needs a separate
      "has run" flag.
- [x] ~~**`PhotoManager` uses `assign(to:)`, contradicting LEARNINGS.**~~ *Resolved 2026-08-11 — the
      code is right and the rule was over-broad.* `assign(to: &$published)` republishes *through*
      the `@Published` wrapper and does fire `objectWillChange`; it is `assign(to:on:)`, the
      key-path overload, that bypasses it (and retains the target). The LEARNINGS entry has been
      narrowed rather than deleted — the 2026-03-08 bug was real, but its cause was misattributed.

### Device verification 🔍

Landed and green, never confirmed on hardware. Effect-specific items are in §2e.

- [ ] **`4×` and `0.25×` playback actually play at those rates.** The hazard:
      `frameCount = max(12, Int(1/speed/0.04))` floors at 12 above 2×, so 4× yields 12 frames at
      ~0.0208s — and **many decoders round delays under 0.04s up to 0.1s**, which would make 4× play
      *slower* than 1×. The range was unreachable before, so exposing it exposes the bug for the
      first time. If it misbehaves, floor the *delay* and cut the duration rather than flooring the
      frame count.
- [ ] **A `0s` pause reads as no pause.** `max(1, …)` still emits one ~0.04s frame; confirm that is
      invisible rather than a stutter.
- [ ] **Zoom card gallery scroll feel** with only three cards, which do not fill the width.

---

## Architecture

```
App/              → Entry point, font registration
Models/           → Data types (AnimatorType, ModifierType, VisualEffectType, EffectCategory,
                    DetailContent, GradientStops, Text/*, etc.)
Services/         → Business logic (GIF generation, photo library, permissions, face detection)
  Animators/      → Animator + MotionModifier + VisualEffect protocols, CompositeAnimator,
                    per-effect files, FaceRegions/ compositor
  Text/           → Text layout, rasterization, tile compositing
Features/
  Gallery/        → Gallery screen + pinch-to-reflow grid
  Editor/         → Editor screen + logic (EditorView, EditorViewModel)
Components/       → Shared reusable UI
Design/           → Tokens, modifiers, typography, PanelMetrics
Extensions/       → Swift extensions
Shaders/          → Pixellate.metal (SwiftUI [[stitchable]], canvas border only — see §1c)
Docs/             → This file, HISTORY, EFFECTS, LEARNINGS, DESIGN_SYSTEM, feature plans
```
