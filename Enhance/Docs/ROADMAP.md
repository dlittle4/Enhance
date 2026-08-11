# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-08-10 (session 15)

## Vision

Enhance is built around a simple creative flow:
**choose a photo → define a focal point → generate motion → refine → save or share.**

Each step should feel fast, tactile, and visually satisfying.

---

> **Docs:** [EFFECTS.md](EFFECTS.md) — how to build an effect, and what is still worth building.
> [LEARNINGS.md](LEARNINGS.md) — rules discovered the hard way.

---

## Pick up here

**State:** `main` has LENS (Phase 17h) and **Feature Scrambler V1 — THIRD EYE (Phase 17i)**,
pushed to `origin/main`. Unit suite green. The session's pattern is to commit on the branch and
fast-forward `main` at each green stage, so Xcode always sees a working build.

THIRD EYE's on-device pass is confirmed (2026-08-10) — V1 fully done. **Scrambler Stage E** (the
MOUTH EYES / EYE MOUTH / SHUFFLE layout pack) is also shipped; only device QA on those three new
layouts remains (THIRD EYE is already device-confirmed).

**Next:** step 5 below — Phase 17f (control audit) is the smallest, then Gallery Stage B.

### What shipped

1. **The disappearing-GIFs bug** *(user-reported)* — four defects composed into one failure.
   Recovery from an iOS `Caches/` purge could not reach iCloud, the photo fallback called a
   video-only API, and the cleanup sweep then deleted the survivors. Stage A fixed; **Stage B
   still open** — the trigger is fixed but the failure *mode* survives (a GIF is still dropped
   from the grid if its URL fails to resolve).
2. **Six effects retired**, hidden from the picker but kept compiled and tested via
   `VisualEffectType.retired`.
3. **Three new effects** — GRADIENT (user-picked multi-stop ramp), EDGES, DITHER. Nine colour
   grades were built and then cut on review.
4. **DITHER locked to the subject** — `FrameGeometry` carries both zoom scale *and* content
   offset, because scaling the cell alone left the grid crawling as the animation pans.
5. **The drill-down effect UI**, Stages 1–7 of the plan: declarative `EffectParameter`
   declarations, namespaced per-effect value storage, dotted numeric sliders, the detail panel
   with discard/confirm semantics, device-scaled cards up to 160pt, and face-filter thumbnails.
6. **Three docs** split by role — this file (what/when), EFFECTS.md (how), LEARNINGS (rules).
7. **Stage 8 — the effect system fully migrated.** Every computed shim and legacy label
   property deleted, three zero-reference files removed, and a real bug fixed on the way out:
   the panel pushed undo *twice* per slider drag, so the second undo stepped the user forward.
8. **The ZOOM tab joined the drill-down pattern**, which is what fixed its iPhone SE 3
   overflow. SPEED and PAUSE became continuous over the generator's actual clamps
   (0.25–4×, 0–5s) instead of discrete cycle buttons that never reached the full range.
9. **Zoom cards show a framing, not a flat fill**, from a snapshot that only moves when a
   gesture settles; carousel edges dissolve instead of slicing a card; and an arrival hint tells
   the user to pinch before ENHANCE has to tell them off for not.
10. **Two feature plans written and reviewed** — [FEATURE-LENS-DISTORTION.md](FEATURE-LENS-DISTORTION.md)
    (evidence-based port of a Figma shader) and [FEATURE-SCRAMBLER.md](FEATURE-SCRAMBLER.md)
    (face-region rearrangement). Both are specified; neither is started.

---

### Next up — in this order

The order matters more than usual right now, because one bug gates two features and one
assumption turned out to be false. Rationale in "Why this order" below.

**0 — Yours, not mine. Blocks nothing, so do it whenever.**

- [ ] **Device-verify `4×` and `0.25×` playback.** Newly reachable, never exercised. The specific
      hazard is in "Needs device verification".
- [ ] **Device-verify DITHER.** The only user-reported bug still unconfirmed, two sessions on
      `main`. Mechanism proven by `dither_phaseIsPeriodicInCellSize`; the *result* has never been
      watched in a real GIF.

**1 — Unblock the face-effect render path. ✓ Done 2026-08-09.**

- [x] ~~**`faceEffectedSource` renders the full-resolution source once per frame.**~~ Fixed — the
      source is pre-scaled to the largest size the zoom can reveal (`fillScale × maxZoom`, clamped
      to 1). **Measured 67.2s → 3.8s, 17.7× faster** on a 12MP source at zoom 1, 13 frames, iPhone
      17 Pro sim. Both planned effects sit on this path, so it landed before them.
- [x] ~~**`HeatHazeEffect` constructs a `CIContext` per frame.**~~ Fixed — one shared static
      context.

**2 — Finish the cheap correctness work. ✓ Done 2026-08-09.**

- [x] ~~**`saveGIFToLibrary` can save the wrong file.**~~ Fixed — SAVE reads `generatedGifURL`
      directly; the `gifURL` fallback property is deleted so the trap can't return.

**3 — LENS (Phase 17h). ✓ Done 2026-08-09.**

- [x] Shipped in both carousels — AMOUNT + REACH, three `CIZoomBlur` passes recombined, no new
      infrastructure. Rendered on the reference photo and inspected: radial prismatic dispersion,
      centre-clean, REACH confines it to an edge fringe at 0 and fills the frame at 1. 216 tests.

**4 — Feature Scrambler (Phase 17i). ✓ V1 + layout pack done 2026-08-10.**

- [x] Shipped THIRD EYE (V1) then the Stage E layout pack (MOUTH EYES / EYE MOUTH / SHUFFLE).
      Copies features to wrong positions over the zoom with a `smoothstep` settle; single-face;
      INTENSITY + SIZE + LAYOUT (three-row panel). Left behind the reusable landmark compositor
      (`FaceRegion` / `FaceRegionMaskBuilder` / `FaceRegionCompositor`), the `FaceRegions` +
      `LandmarkQuality` model, `ScrambleLayout`, and a general `EffectParameter.Kind.preset`.
      **THIRD EYE device-confirmed; the three new layouts still need a device pass.**

**5 — Then, in rough value order.**

- [ ] **Phase 17f** — control audit. Candidates already identified with file and value.
- [ ] **Gallery Stage B** — close the failure *mode*, not just the trigger.
- [ ] **Phase 19b** — copy effects between photos, and stacking. Stacking reverses a documented
      decision; read that entry first.
- [ ] **Phase 17e** — CIKernel infrastructure and Riso Print. **Deliberately last now** (see
      below). Still the highest-risk change in the project.

### Why this order

**The face-effect render cost stopped being a nice-to-have.** It was measured at "~25
full-resolution renders" when the frame count was effectively fixed. Continuous speed shipped
this session, and `frameCount = max(12, Int(1/speed/0.04))` means **0.25× playback now produces
100 frames** — so the same bug is roughly 4× worse than when it was filed, and it sits directly
under both planned features. The Scrambler plan already says to fix it before interpreting
benchmarks, but files it under "performance budget" rather than as a gate. It is a gate.

**Phase 17e is no longer the gateway to new effects.** The roadmap implicitly assumed that
porting Figma *shader* effects would need `CIKernel` infrastructure — which is why 17e sat in
front of the interesting work despite being the riskiest change in the project (the `-fcikernel`
build rule would break the animated canvas border *at runtime*). The LENS analysis disproves the
assumption: a Figma shader effect reconstructs to about eight stock Core Image nodes. So 17e can
move behind both new effects, and the roadmap gets materially less risky for free.

**Scrambler is bigger than it looks and LENS is smaller.** LENS needs no new
`EffectParameter.Kind`, no `EditorSnapshot` field, no landmark-model change, and no new panel
component. Scrambler as originally scoped needs all four, plus a 4-row panel that does not fit a
4.7" screen. Doing LENS first also exercises the "one `VisualEffect`, both carousels" path while
the adapter is fresh.

---

## Needs device verification

Landed and green in tests, but **not yet confirmed on a physical device**. Verified only by
rendering frames and inspecting them, which cannot catch everything.

- [ ] **DITHER motion during the zoom.** The grid is meant to stay locked to the subject:
      cell size scales with the zoom (`FrameGeometry.scale`) and grid phase follows the pan
      (`FrameGeometry.contentOrigin`). Reported as "moving slightly differently than the
      zoom" before the phase fix; the phase mechanism is proven by
      `dither_phaseIsPeriodicInCellSize` but the end result has not been watched in a real GIF.
      **If it still crawls, the prime suspect is the Y-flip in `GIFGenerator.frameGeometry`** —
      that line was reasoned about rather than measured. A quick check: log `contentOrigin`
      per frame and confirm it moves monotonically with the pan.
- [ ] **DITHER legibility after GIF palettisation.** Does the stipple survive the 256-colour
      quantisation, or read as noise? If it needs help, the SCALE slider is the first lever.
- [x] **THIRD EYE (Feature Scrambler V1)** — device pass confirmed 2026-08-10, looks good. The
      deep edge cases (4× 12-frame floor across Zoom In/Out/Pulse; the one-eye profile fallback;
      the animal fallback) were not each individually exercised and can be spot-checked if a report
      comes in — padding 0.35 / feather 0.55 remain the seam/halo levers.
- [ ] **20-item effects carousel** — scroll feel, and whether entering the IMAGE tab stutters
      while 11 thumbnails render (was 8 before the new effects).
- [ ] **GRADIENT colour wells** — the three system wells show Apple's spectrum ring; confirmed
      working but never seen alongside the rest of the row on device.
- [ ] **`4×` and `0.25×` playback actually play at those rates.** The specific hazard:
      `frameCount = max(12, Int(1/speed/0.04))` floors at 12 above 2×, so 4× yields 12 frames at
      ~0.0208s — and **many decoders round delays under 0.04s up to 0.1s**, which would make 4×
      play *slower* than 1×. This range was unreachable before, so exposing it exposes the bug
      for the first time. If it misbehaves, floor the *delay* and cut the duration rather than
      flooring the frame count.
- [ ] **A `0s` pause reads as no pause.** `max(1, …)` still emits one ~0.04s frame; confirm that
      is invisible rather than a stutter.
- [ ] **Zoom card gallery scroll feel** with only three cards, which do not fill the width.

---

## Known Bugs — Session 14 Audit (2026-08-07)

Found by code review, not yet reproduced on device unless noted. Ordered by severity.
Each entry names the file and line where the defect lives.

### P0 — Data loss (perceived)

- **Gallery GIFs disappear after the app sits unused.** *(user-reported)*
  Four defects composed into one failure. The assets were never lost — they stay intact in
  Photos — but the gallery could not re-resolve them and then deleted its own cache.
  **Stage A fixed 2026-08-07; Stage B still open.**
  - [x] GIF originals are cached in `Library/Caches/MyGIFs/`, which iOS purges under storage
        pressure, preferentially for apps not used recently. *(Root trigger — left as-is for now;
        recovery is what was broken. See Stage B for the alternative.)*
  - [x] The cache-miss recovery path could not reach iCloud: `PHContentEditingInputRequestOptions`
        never set `isNetworkAccessAllowed = true`, while the thumbnail options on the same fetch did.
        Offloaded assets returned a nil `fullSizeImageURL`. → Replaced with
        `copyOriginalImageData(for:destination:)` using `requestImageDataAndOrientation`
        (`version = .original`, network access allowed), the correct API for original GIF bytes.
  - [x] The photo fallback called `requestAVAsset(forVideo:)` on a *photo* asset and always
        returned nil. → `requestAVAsset` is now used only for genuine video assets.
  - [x] `cleanupStaleCacheFiles()` deleted cache files for dropped entries, escalating a partial
        failure into permanent cache loss, and wiped everything if the fetch fully failed.
        → Now runs only after a complete, untimed-out fetch that resolved every asset.
  - [x] A stalled request could leave `isFetching` pinned true for the session. → `group.notify`
        replaced with `group.wait(timeout: 30s)`, and every leave routed through `LeaveGuard`
        so a repeated or missing Photos callback can neither over- nor under-balance the group.
  - [ ] **Stage B (open):** a GIF is still only displayed when *both* thumbnail and URL resolve
        (`GIFLibraryService` intersection, `GalleryView.swift:50`), so any future URL failure
        still removes it from the grid. Decouple display from URL resolution — replace the three
        parallel arrays with one `[GifItem]` (`assetIdentifier`, `thumbnail`, `url: URL?`) and
        resolve the URL lazily on tap. Touches ~9 sites in `GalleryView`.
  - [ ] **Stage B (open):** consider moving originals from `Caches/` to
        `Application Support/MyGIFs/` with `isExcludedFromBackup = true` so the system never
        purges them in the first place.

### Test suite

- [x] Fixed three stale tests that asserted behaviour deliberately removed in earlier phases and
      had been failing on `main`: `generateGIF_withScaleTooLow_returnsNil` (Phase 13c removed the
      `currentScale > 1.0` guard), `resetEffects_restoresDefaults` (Phase 13c made modifiers
      deselectable; default speed is 0.5 not 1.0), and `pixelate_atZeroProgress_returnsUnchanged`
      (2026-03-11 inverted pixelate's progress). Suite was 89 passing / 3 failing → **92 / 0**.
- [x] Added `EnhanceTests/GIFLibraryCacheTests.swift` covering `LeaveGuard` balance semantics
      and `ThumbnailCache` directory recovery after a purge.

### P1 — Correctness

- [ ] **Edits are silently dropped during regeneration.** `guard !isRegenerating else { return }`
      appears in 12 places. A change made while a regeneration is in flight is discarded with
      nothing queued and no re-check on completion — the UI shows the new setting, the GIF shows
      the old one. The four sliders are *not* `.disabled` during regeneration
      (`EditorView.swift:641`, `:689`, `:794`, `:842`), so slider edits are the most likely to vanish.
      Root cause: the same 6-line "mark modified + regenerate" block is copy-pasted ~13 times
      across 8 `.onChange` handlers, 4 drag-end methods, and `restore()` (31 `regenerateGIF()` callsites).
- [ ] **Newly-saved GIFs never persist their zoom params.** `persistZoomParams` is called only from
      `updateOriginalGIF` (`EditorViewModel.swift:812`). `saveGIFToLibrary` — which handles first-time
      saves *and* "SAVE NEW COPY" — never calls it, so re-opening falls back to the hardcoded
      `scale = 2.0, rect = (0.15, 0.15, 0.7, 0.7)` (`:632`). Structural blocker: the save callback
      does not return the new PHAsset identifier, so there is currently no key to store against.
- [x] **RESET on an existing GIF leaves the preview stale.** *(fixed 2026-08-08.)* `resetEffects()`
      cleared all effects but only touched `enhanceState` in the `.newImage` branch, so on an
      existing GIF it never regenerated and never set `hasModifiedSettings` — the displayed GIF kept
      the old effects and SAVE stayed disabled, making the reset look like a no-op. It now calls
      `regenerateIfNeeded()` on the other branch. Note the near-miss: an undebounced
      `.onChange(of: playbackSpeed)` had been accidentally papering over half of this, and deleting
      that handler in the same session would have made the bug fully visible had it not been fixed
      alongside.
- [x] **`saveGIFToLibrary` can save the wrong file.** *(fixed 2026-08-09.)* It read `gifURL`, which
      fell back to `existingGifURL`, so a failed regeneration on an existing GIF let "SAVE NEW COPY"
      duplicate the unmodified original. Now reads `generatedGifURL` directly like `updateOriginalGIF`;
      the fallback property is deleted so it can't be reintroduced.
- [x] **A stalled iCloud download can wedge the gallery for the whole session.** *(fixed 2026-08-07 —
      see P0 above.)* The degraded-image early return skips `group.leave()` by design, which is
      correct only if a final delivery always arrives. If it did not, `group.notify` never fired,
      `isFetching` stayed `true`, and `guard !isFetching` made every later refresh a silent no-op
      until relaunch.

### P1 — Correctness (cont.)

- [x] **The ZOOM tab overflows on short devices.** *(fixed 2026-08-08.)* Measured on iPhone SE 3
      (667pt): the zoom controls needed ~246pt (42pt tabs + three 60pt rows + spacing) against
      roughly 110pt of budget, so the modifier row and SPEED/PAUSE collided with ENHANCE. Fixed by
      moving the tab to the same cards → drill-down panel the other two use.
      **Two further overflows surfaced only on device, both general rather than SE-specific:**
      (a) panel rows were a fixed 44pt, so a three-row panel did not fit — they now size from the
      height the panel is actually given (`PanelMetrics`), clamped 34–44pt, *with the header
      counted as one more unit in that division*; omitting it overflowed by ~8pt.
      (b) the colour swatch row forced the whole panel **wider than the display** — `Spacer()`
      carries its own ~8pt minimum *on top of* the HStack's default spacing, so six swatches had a
      ~390pt intrinsic minimum against a 195pt slot. Both `spacing` and `minLength` had to be zero.
      This one had shipped in LAZER EYES for some time and was never noticed.
- [ ] **Onboarding tagline truncates on SE 3** — "DRAMATIC ZOOMS AND S…". Fixed font size
      against a narrower screen.

### P2 — Performance

- [x] **Face-effect GIF generation renders the full-resolution source once per frame.** *(fixed
      2026-08-09 — pre-scaled to `fillScale × maxZoom`; measured 17.7× faster. See
      `GIFGenerator.faceEffectSourceScale`.)*
- [ ] ~~(original entry kept for context)~~ **Face-effect GIF generation renders the full-resolution source once per frame.**
      `faceEffectedSource` (`GIFGenerator.swift:157`) builds a CIImage from the full-size source,
      applies the effect, and calls `createCGImage` once per animation frame plus the pause frame —
      for a 600×600 output. The preview path already downscales to 650px; the GIF path never got
      the same treatment.
      **Now roughly 4× worse than when this was filed, and promoted to a prerequisite.** Continuous
      speed shipped 2026-08-08, and `frameCount = max(12, Int(1/speed/0.04))` means 0.25× playback
      produces **100 frames**, not the ~25 this entry was written against. Both planned effects
      (Phase 17h, 17i) sit on this path, so benchmarking either one before this is fixed measures
      this instead. See "Next up" step 1.
- [x] **`HeatHazeEffect` creates a `CIContext` on every frame.** *(fixed 2026-08-09 — shared
      static context.)* Original detail: `CIContext()` is constructed
      inline inside `apply` (`HeatHazeEffect.swift`, in the `createCGImage` guard), so a 25-frame
      GIF builds 25 contexts — and **up to 100 at 0.25× playback** since continuous speed shipped. LEARNINGS 2026-03-08 states the rule explicitly: create one
      `CIContext` and reuse it, never per frame or per effect. Every other effect either avoids
      `CIContext` entirely or uses the shared one. Found while auditing effect parameters.
- [x] **The disk thumbnail cache is destroyed on every refresh.** *(fixed 2026-08-07)*
      `ThumbnailCache` stores at `Caches/MyGIFs/Thumbs/`, *inside* the directory
      `cleanupStaleCacheFiles()` sweeps. `Thumbs` was not in `validFilenames`, so it was
      recursively deleted; `thumbsDir` was only created in the singleton's `init`, so after the
      first cleanup it never returned and all disk writes failed silently through `try?`.
      → Directory name exposed as `ThumbnailCache.directoryName` and skipped by the sweep;
      the directory is now re-created on every write rather than assumed to persist.

### P3 — Polish / open questions

- [ ] **"NO FACES DETECTED" toast repeats.** `detectFacesIfNeeded` guards on `detectedFaces.isEmpty`
      (`EditorViewModel.swift:346`), which stays true forever when detection legitimately finds nothing,
      so every return to the face tab re-runs detection and re-toasts. Needs a separate "has run" flag.
- [ ] **Undo does not capture zoom.** `EditorSnapshot` (`:9`) has no `currentScale` / `visibleRect`.
      Pinch/pan is not undoable, and undo after a zoom restores effects against different framing.
      May be intentional — needs a decision either way.
- [x] **Preview images changed aspect ratio.** *(confirmed on device and fixed 2026-08-08)*
      Three effects returned a larger extent than they were given: FISHEYE
      (`CIBumpDistortion`), SWIRL (`CITwirlDistortion`) and PIXELATE (`CIPixellate`, which
      grows by ~half a cell per side). Since `ImageCanvasView.configureContentSize` runs
      only in `makeUIView`, a preview image with a different aspect ratio letterboxed the
      canvas — visible as a black band above the photo — and would also have changed frame
      dimensions in the GIF pipeline. All three now `.cropped(to: image.extent)`, and
      `allEffects_preserveInputExtent` guards every effect at two progress values through
      both entry points.
- [ ] **`PhotoManager` uses `assign(to:)` for `@Published` forwarding** (`PhotoManager.swift:24-29`),
      which contradicts the documented rule in LEARNINGS.md (2026-03-08, "use `sink` with explicit
      assignment"). Either the code or the learning is wrong; reconcile them.

---

## Phase 0: Cleanup & Foundation ✓

- [x] Fix PhotosPicker tap interception (DragGesture + nested Button bug)
- [x] Remove debug instrumentation from ButtonModifiers and GalleryView
- [x] Delete dead files (Backups/, ContentView.swift, ViewExtensions.swift, unused components)
- [x] Gate `print()` statements behind `#if DEBUG`

## Phase 1: Architecture Refactor ✓

- [x] Extract models (AnimatorType, EnhanceState, DetailContent, AnimationConfig) into `Models/`
- [x] Split PhotoDetailView into Editor feature folder (EditorViewModel, EditorView, ImageCanvasView, AnimatorPickerView, GIFPreviewView, ShareSheet)
- [x] Create GIFGenerating protocol and inject via environment
- [x] Split PhotoManager into PermissionManager, PhotoLibraryService, GIFLibraryService
- [x] Create Gallery feature folder (GalleryView, GifGridItem)
- [x] Fix matched geometry transition IDs
- [x] Extract font registration and typography into Design/

## Phase 2: Core Flow Improvements ✓

- [x] Add in-app photo selection grid with fluid transitions (PhotoGridView)
- [x] Improve focus area definition with visual zoom frame indicator (ZoomFrameOverlay)
- [x] Add animation preview with play/pause and speed controls (PreviewControlsView)

## Phase 3: Gallery & Editor UI Overhaul ✓

- [x] Gallery grid: 3-column layout, 114pt square cells, 16px corner radius, shadow
- [x] Gallery carousel: vertical scroll with parallax scale/opacity, 34px corner radius
- [x] Floating bottom bar: equal-width buttons, 8px gaps, dark translucent toggle
- [x] NUX: first-time user experience screen with create-first-GIF prompt
- [x] Editor button styles: ENHANCE/SHARE use mesh gradient, SAVE uses dark translucent bg
- [x] Font constants: silkscreenButtonLabel (16px), silkscreenControl (13px)
- [x] Animated border renders on top of photo with matching corner radius
- [x] Existing GIF re-edit: extract first frame, apply new effects, regenerate
- [x] Save dirty state: SAVE disabled until effect/speed changed on existing GIF
- [x] Save action sheet: UPDATE ORIGINAL GIF / SAVE NEW COPY options
- [x] PHAsset identifier tracking in GIFLibraryService for targeted deletion
- [x] Component reorganization: moved 7 reusable views from feature folders to Components/
- [x] Fixed canvas zoom hit-test leak blocking close button

## Phase 3.5: Photo Picker & Sharing Improvements ✓

- [x] Photo album browser with floating filter button and action sheet
- [x] Album sheet uses native presentationDetents (half-height, expandable)
- [x] Photo sort options (by recent, by date captured)
- [x] Photo thumbnail performance: reduced size from 1035px to 390px (50% faster)
- [x] Progressive photo loading in batches of 12
- [x] PHCachingImageManager for better thumbnail caching
- [x] ShareSheet uses UIActivityItemSource with explicit UTType.gif for broader share targets
- [x] Save/share action sheet animations (spring slide-up)
- [x] Pagination with LOAD MORE button (100 initial, 50 per tap)
- [x] Full-resolution image fetch on photo selection (3000×3000 for editor quality)
- [x] Auto-continue for iCloud-sparse batches (caps at 5 consecutive empty batches)
- [x] Debounced photoLibraryDidChange observer (2s cooldown, GIFs only)
- [x] Fixed CGImageSourceCreateImageAtIndex CFNull options across 4 files

## Phase 4: New Effects ✓

### Phase 4a: Motion Modifiers ✓

- [x] MotionModifier protocol + CompositeAnimator (base effect + modifier composability)
- [x] StraightModifier (default pass-through, no modification)
- [x] ShakeModifier (layered sine-wave jitter with decaying amplitude)
- [x] SpiralModifier (polar-coordinate circular displacement, tightening spiral)
- [x] ModifierType enum (STRAIGHT / SHAKE / SPIRAL)
- [x] Modifier segmented bar in editor (3rd row: between base effects and speed)
- [x] RESET button in editor header (visible when settings differ from defaults)
- [x] GIF regeneration triggers on modifier change

### Phase 4b: Visual Effects ✓

- [x] VisualEffect protocol (CIImage → CIImage per-frame post-processing, progressive with animation)
- [x] FadeToBWEffect (CIColorControls desaturation, linear progress)
- [x] ChromaticAberrationEffect (R/B channel split via CIColorMatrix, cubic ease-in)
- [x] HalftoneEffect (CICMYKHalftone newspaper dot pattern, quadratic ease-in)
- [x] FisheyeEffect (CIBumpDistortion center bulge, quadratic ease-in)
- [x] VisualEffectType enum (FADE TO B&W / CHROMA SHIFT / HALFTONE / FISHEYE)
- [x] EffectCategory enum + category dropdown switching in editor
- [x] Toggle pill grid for visual effects (2x2, mutually exclusive, green border when active)
- [x] Effects sheet shows applied settings as subtitles per category
- [x] GIFGenerator pipeline: shared CIContext, applyVisualEffects helper, CIImage chaining
- [x] Visual effects combine with zoom effects (both categories active simultaneously)
- [x] GIF regeneration triggers on visual effect toggle

## Phase 5: Simplify & Stabilize

### Phase 5a: Replace Custom Photo Picker ✓
- [x] Swap PhotoGridView with native SwiftUI PhotosPicker
- [x] Remove custom pagination, album browsing, thumbnail caching, and iCloud batch logic
- [x] Clean up PhotoLibraryService (stripped to static fetchAlbumCollection helper only)
- [x] Clean up PhotoManager (removed photo-forwarding properties, Combine subscriptions)
- [x] Deleted PhotoGridView.swift (~280 lines removed)
- [x] Simplified DetailContent.newImage (removed index used only for matched geometry hero animation)
- [x] Simplified ImageCanvasView (removed namespace/photoIndex params, no more matchedGeometryEffect)
- [x] Verify full-resolution image handoff to editor works (PhotosPicker loads full data → UIImage)

### Phase 5b: Bug Fixes & Cleanup ✓
- [x] Consolidated fetchMyGifs/forceRefreshGifs into single coalesced method with isFetching gate (prevents concurrent fetches)
- [x] Stable cache filenames using asset localIdentifier (eliminates GIF/Thumbnail cache invalidation on refresh)
- [x] PHImageManager degraded-callback guard (checks PHImageResultIsDegradedKey, only counts final delivery)
- [x] Automatic stale cache file cleanup after each refresh
- [x] Removed all #if DEBUG logging instrumentation from EditorViewModel, GalleryView, GIFGenerator, PermissionManager, FontRegistration
- [x] Removed debug file-logging to .cursor/debug-0cbc41.log
- [x] Upgraded GifGridItem and GalleryCarouselView thumbnails to use CGImageSourceCreateThumbnailAtIndex (more efficient, avoids full-decode + resize)
- [x] Auto Layout constraint warnings: confirmed Apple-internal (PhotosPicker NavigationButtonBar) — cannot fix

## Phase 6: Performance ✓

- [x] Cap GIFCache size (countLimit: 50, totalCostLimit: 100MB) with per-entry cost tracking
- [x] Background-thread thumbnail pipeline (CGImageSourceCreateThumbnailAtIndex on global queue with cancellation)
- [x] Lazy GIF decoding via onAppear/onDisappear isVisible gating (offscreen cells show cached thumbnail)
- [x] Gallery view crossfade transition on grid/carousel switch
- [x] NUX flash fix (hasLoaded gate prevents empty-state flash while GIFs load)
- [x] Disk-backed ThumbnailCache (JPEG persistence in Caches/MyGIFs/Thumbs/, instant gallery load on relaunch)
- [x] Stale thumbnail cleanup after each GIF refresh
- [ ] _(deferred)_ Frame streaming: decode GIF frames on-the-fly during playback instead of loading all frames into memory
- [ ] _(deferred)_ Profile and reduce GIF generation time (CGContext reuse, parallel frame rendering)

## Phase 7: Testing ✓

- [x] AnimatorTests (ZoomIn, ZoomOut, Pulse: boundary values, monotonicity, midpoint behavior)
- [x] MotionModifierTests (Straight pass-through, Shake jitter + decay, Spiral radius + settle, CompositeAnimator)
- [x] VisualEffectTests (FadeToBW, ChromaticAberration, Halftone, Fisheye: zero-progress identity, full-progress output, extent preservation)
- [x] GIFGeneratorTests (valid output, GIF89a magic bytes, scale guard, all animators, visual effects, composite animators, speed variants, saveTempGIF round-trip)
- [x] Extracted GIFGenerating protocol for dependency injection into EditorViewModel
- [x] EditorViewModelTests (initial state, hasNonDefaultSettings, resetEffects, activeAnimator, isSaveEnabled, buttonText, showToast)
- [x] EnhanceUITests (launch smoke, gallery-or-NUX detection, view toggle, launch screenshot, launch performance)
- [x] Removed leftover debug file-logging from ShakeModifier and SpiralModifier

## Phase 8: New Features

### Phase 8a: Delete GIFs ✓

- [x] Multi-select mode: long-press grid thumbnail to enter, tap to toggle selection
- [x] Selected items show 4px red border (#EB1B15)
- [x] Gallery header updates to "N PHOTOS SELECTED" with X exit button
- [x] Red "DELETE SELECTED PHOTOS" button replaces normal floating bar in select mode
- [x] Batch deletion via single PHAssetChangeRequest.deleteAssets call
- [x] Confirmation alert before deletion
- [x] Auto-exit select mode when switching to carousel or when selection becomes empty
- [x] Removed old context menu delete from GifGridItem (replaced by selection mode)

### Phase 8b: Visual Effect Intensity Slider ✓

- [x] Added `effectIntensity` property (0.0–1.0) to EditorViewModel
- [x] Each VisualEffect now accepts intensity in its initializer, scaling max parameters
- [x] Draggable intensity slider bar below visual effects grid (mint green fill, shows LOW/MEDIUM/HIGH/MAX)
- [x] Calibrated so intensity 0.5 (medium) matches original tuned values; 1.0 (max) is ~2x stronger
- [x] GIF regeneration triggers on drag end (debounced, not continuous)
- [x] Effects sheet subtitle shows intensity level alongside effect name

### Phase 8c: Configurable Pause Duration ✓

- [x] Added `pauseDuration` (1–5 seconds) to EditorViewModel with cycle-on-tap behavior
- [x] Speed button cycles 1X → 2X → 0.5X (replaced SegmentedBar with toggle buttons)
- [x] Pause is fully independent of speed (pause frames use fixed frame delay, not speed-scaled)
- [x] GIFGenerator dynamically computes pause frame count from duration at ~25fps
- [x] Removed viewer-side playback speed scaling (speed is baked into GIF frame delays)
- [x] Fixed AnimatedGifView stale `isVisible` capture preventing carousel playback

### Phase 8d: Gallery UX Improvements ✓

- [x] Pinch-to-reflow: MagnificationGesture drives grid column count (3 → 2 → 1)
- [x] Removed carousel view entirely (pinch-driven grid replaces it)
- [x] Centered "MY GIFS (N)" header with live count
- [x] Max zoom increased to 50x
- [x] Mesh gradient colors updated to green/teal palette matching app logo

### Phase 8e: Multi-Select Actions, Export & Gallery Controls ✓

- [x] Multi-select bottom bar: COPY, SHARE, DELETE buttons (mint green selection border, dark background)
- [x] Copy action: loads GIF data from selected URLs, sets on UIPasteboard as UTType.gif items, shows toast
- [x] Share action: copies GIFs to temp files, presents UIActivityViewController
- [x] Gallery pause/play button in header (toggles auto-play for all GIFs via @AppStorage)
- [x] Auto-play toggle wired to GifGridItem (disables GIF animation, shows static thumbnail)
- [x] Export format preference stored via @AppStorage ("gif" or "video")
- [x] MP4/video export pipeline (AVAssetWriter + H.264, reuses GIF frame generation pipeline)
- [x] VideoPreviewView for MP4 playback in editor (AVPlayerViewController with looping, no controls)
- [x] GifGridItem video thumbnail support (AVAssetImageGenerator for MP4 files)
- [x] GIFLibraryService detects video assets and caches with correct .mp4 extension
- [x] Stale cache validation (magic-byte check removes .gif files containing MP4 data)
- [x] PHAssetResourceType auto-detection (.video for MP4, .photo for GIF) on save

### Phase 8f: Visual Effect Preview ✓

- [x] Real-time static preview of visual effects on image canvas before GIF generation
- [x] Viewport-centered effects: added `viewportCenter` parameter to `VisualEffect` protocol
- [x] FisheyeEffect and HalftoneEffect track viewport center in image coordinates during preview
- [x] Debounced re-render on pan/zoom (30ms, GPU-accelerated CIContext) keeps preview responsive
- [x] Non-spatial effects (B&W, Chromatic Aberration) use default protocol extension (no viewport dependency)
- [x] Preview clears automatically on RESET or after GIF generation (isSplit)
- [x] Intensity slider and effect toggle changes trigger immediate (non-debounced) preview update

### Phase 8g: Fisheye Controls & Preview Performance ✓

- [x] Separate size parameter for FisheyeEffect radius (0.1–0.5 of image dimension)
- [x] VisualEffectType.effect() accepts `size:` parameter (only fisheye uses it)
- [x] `effectSize` property + SIZE slider in editor (visible only when fisheye selected)
- [x] `sizeLabel` computed property (SMALL / MEDIUM / LARGE / MAX)
- [x] Effects sheet subtitle shows size alongside intensity for fisheye
- [x] Downscaled preview source: 650x650 CGImage via CGImageSourceCreateThumbnailAtIndex
- [x] Preview CIFilter processes ~14x fewer pixels (~2-3ms vs ~15-25ms)
- [x] Cached preview source cleared on reset or source image change
- [x] Tests updated for effectSize defaults, reset, and fisheye size variants

### Phase 8h: New Visual Effects Batch ✓

- [x] SwirlEffect — spiral/vortex distortion using CITwirlDistortion (viewport-centered)
- [x] GlitchEffect — deterministic pseudo-random horizontal band displacement
- [x] ScanlinesEffect — CRT/VHS look via CIStripesGenerator overlay + subtle green tint
- [x] PixelateEffect — chunky mosaic using CIPixellate (viewport-centered, progressive)
- [x] RippleEffect — sine-wave horizontal displacement of image row strips
- [x] VisualEffectType enum expanded from 4 to 9 cases
- [x] Editor grid updated to 3-column layout with smaller cells (48pt height, 12px radius)
- [x] `supportsSizeControl` property on enum for future extensibility
- [x] Unit tests for all 5 new effects (zero progress, full progress, viewport/frame variants)

### Phase 8i: Effect Refinements ✓

- [x] PixelateEffect inverted — starts pixelated, resolves to sharp as animation progresses ("reveal" aesthetic)
- [x] Fisheye INTENSITY + SIZE sliders laid out side-by-side (HStack) to save vertical space
- [x] `supportsSizeControl` on VisualEffectType drives horizontal vs. stacked slider layout
- [x] Project pushed to GitHub (github.com/dlittle4/Enhance), .venv removed from history, .gitignore added

### Phase 9: Face Filters ✓

- [x] FaceDetectionService — Vision framework face/landmark detection with coordinate conversion and caching
- [x] DetectedFace model — pre-computed image-coordinate positions for bounding box, pupils, eyes, brows, contour
- [x] FaceEffect protocol — face-aware effect interface separate from VisualEffect
- [x] FaceFilterType enum — 4 cases (bushy eyebrows, googly eyes, bobble head, handsome) with custom slider labels
- [x] BushyEyebrowsEffect — multiple CIBumpDistortion along eyebrow landmark points
- [x] GooglyEyesEffect — procedural CIRadialGradient eyes with xorshift PRNG pupil wobble per frame
- [x] BobbleHeadEffect — CIBumpDistortion centered on face with CIAffineClamp for edge safety
- [x] HandsomeEffect — CIFilter approximation (jaw stretch + cheekbone bumps + CISharpenLuminance)
- [x] EffectCategory expanded with faceFilters case (third editor page)
- [x] Editor UI: 2-column face filter grid, face detection overlay with tap-to-select, custom intensity slider labels
- [x] GIF pipeline updated to chain face effects per frame with coordinate scaling
- [x] Unit tests for all 4 face effects, FaceFilterType enum, and EditorViewModel face filter state

### Phase 10: Editor UI Overhaul & Effect Polish ✓

- [x] Icon tab bar — replaced dropdown category selector with 3 tappable icons (zoom, image, smiley) from custom SVG assets
- [x] Custom pixel-art SVG icons added to asset catalog as template images (tint-aware)
- [x] SegmentedBar selected state updated — green-tinted bg (rgba 100/148/122/0.7), mint border, mint text per Figma
- [x] Removed effects sheet dropdown + TriangleDown shape + categorySubtitle helper
- [x] Effect carousels — both visual effects and face filters use horizontal ScrollView with pill-shaped buttons
- [x] Consistent 60pt height across all effect buttons and sliders
- [x] Enhance/Save/Share buttons pinned to fixed bottom position (outside scrolling controls section)
- [x] Face effect timing — removed 0.3 progress delay from squeeze, handsome, and all adapted visual effects (fisheye, swirl, ripple, fadeToBW, chromaShift); effects now animate from progress 0→1 for full zoom duration
- [x] Exceptions: laser eyes, pixelate, and googly eyes retain delayed start
- [x] Pixelate face effect preview fix — added `skipDelay`/`passRawProgress` to FaceVisualEffect, per-effect `previewProgress` on FaceFilterType
- [x] Fisheye face effect second slider — added SIZE control matching the visual effect version
- [x] Speed options — added 0.25x speed, default changed from 1x to 0.5x, cycle: 0.25→0.5→1→2→0.25
- [x] Glitch effect removed — removed from both VisualEffectType and FaceFilterType
- [x] Ripple effect rewritten — whole-face horizontal shake (amplitude 3.5, speed 70) with red tint overlay; slider controls REDNESS instead of intensity

### Phase 10b: Gallery Performance ✓

- [x] Gallery GIF frame count doubled (15→30 frames in low-quality mode) for smoother animation
- [x] Gallery thumbnail resolution increased (200→350px) to match retina grid cell sizes
- [x] GIF cache limit increased (100→150MB) to accommodate larger decoded frames
- [x] Full-quality single-column mode — pinch-to-zoom to 1 column renders full resolution GIFs with full framerate (lowQuality: false)

### Phase 11: Bug Fixes & Stability

- [x] Lock app to portrait orientation only (UIRequiresFullScreen + portrait-only orientations)
- [x] Delete dead code: GalleryCarouselView.swift
- [x] Audit and fix force-unwraps in save/generate flow (removed `image!` in `generateGIF`)
- [x] Debug symbol format set to dwarf-with-dsym for Apple crash reporting
- [ ] Fix: saving a photo sometimes uses a different photo's frame in the gallery thumbnail
- [x] Fix: re-editing losing zoom coordinates — separated generation zoom from canvas zoom, persisted via UserDefaults

### Phase 12: Performance & Core Polish

- [x] Pan/zoom performance — `.drawingGroup()` rasterizes canvas to Metal texture, removed async binding hop; later replaced with UIScrollView in Phase 13b
- [x] Face detection — landmarks + rectangles run in parallel to catch side profiles; added `redetect()` support
- [x] Face detection UI — pulse animation on selected face box outline
- [x] Gallery press state — bounce/scale effect (0.95x) with brightness dim on tap
- [x] Haptic feedback — `HapticService` utility with light/medium/heavy/selection/success/error; wired to gallery taps, long-press, pinch, editor buttons, effect toggles, face selection, save success

### Phase 13: Effect Cleanup & New Effects ✓

**Image effects**
- [x] Added rainbow gradient overlay/animation effect (diagonal sweep, intensity controls opacity)
- [x] Removed scanlines effect (deleted ScanlinesEffect.swift)
- [x] Removed fade to B&W image effect (kept FadeToBWEffect for face filter use)
- [x] Removed ripple image effect (kept RippleEffect for face filter use as "Intensify")
- [x] Cleaned up stale GlitchEffect.swift

**Face effects**
- [x] Heart vignette — heart-shaped darkened vignette around the face, feathered edges
- [x] Heart eyes — animated pink hearts over detected pupils with subtle bounce
- [x] Anime background — radiating speed lines behind the face for dramatic focus
- [x] Renamed ripple face effect to "Intensify"

### Phase 13b: Editor UX & Performance ✓

**Pinch/zoom performance**
- [x] Replaced SwiftUI gesture-based pinch/zoom with UIScrollView via UIViewRepresentable for hardware-accelerated 60fps zoom
- [x] Face box overlays converted to UIView subviews with CAShapeLayer borders and CABasicAnimation pulse
- [x] Double-tap gesture to toggle zoom between 1x and 2x
- [x] Fixed preview image swap resetting scroll position (only swap UIImageView.image, don't reconfigure scroll geometry)

**Undo/redo**
- [x] EditorSnapshot struct capturing all undoable state (effects, sliders, speed, pause, face selection)
- [x] Undo/redo stacks capped at 50 entries with pushUndo/undo/redo/canUndo/canRedo
- [x] Slider undo: snapshot captured on drag start, not per frame
- [x] Reset pushes undo first (reset is undoable)
- [x] Pixel-art undo/redo SVG icons added to asset catalog as template images
- [x] Editor top bar redesigned: RESET + undo/redo icons on left, X on right; removed EDIT PHOTO title

**UI polish**
- [x] Selected button stroke updated to 2pt across all effect carousels and segmented bars
- [x] Fixed effect carousel clipping (added vertical padding inside ScrollView)
- [x] Photo border changed from gradient to solid mintGreen, reduced from 10pt to 5pt
- [x] Button gradient updated to brighter mint green palette matching Figma
- [x] Button text color changed from white to near-black (#171717) on all gradient-backed buttons
- [x] SegmentedBar gained onWillChange callback for pre-change hooks
- [x] Fixed gallery multi-select: simultaneousGesture for long press + tap suppression after long press

### Phase 13c: Optional Controls & Laser Colors ✓

**Deselectable zoom and modifier toggles**
- [x] Replaced SegmentedBar for zoom types (ZOOM IN / ZOOM OUT / PULSE) with individual toggle buttons — tapping a selected item deselects it (no zoom animation)
- [x] Replaced SegmentedBar for modifiers (LINEAR / SHAKE / SPIRAL) with individual toggle buttons — deselecting all means linear/no modifier
- [x] Renamed ModifierType "STRAIGHT" to "LINEAR" to match Figma
- [x] Added StaticAnimator — no-op Animator conformance that holds the user's zoom position unchanged
- [x] Made `selectedAnimatorType` and `selectedModifier` optional in EditorViewModel and EditorSnapshot
- [x] Effects-only GIF generation: removed hard `currentScale > 1.0` guard from GIFGenerator; users can generate GIFs with visual/face effects without zooming in
- [x] Validation: zoom-type-selected requires zoom-in; no-zoom requires at least one effect applied

**Laser color picker**
- [x] LaserColor enum with 6 presets (red #FF0000, yellow #FFE600, green #00CC77, blue #0066FF, purple #AA33DD, magenta #FF2299)
- [x] LazerEyesEffect parameterized with color — core tinted, inner glow/bloom/flares use selected color
- [x] FaceFilterType.effect() accepts and forwards laserColor
- [x] Color picker row (6 circles, 26pt, mint green border on selected) appears below face filter sliders when LAZER EYES is active
- [x] laserColor included in EditorSnapshot for undo/redo support

**Settings**
- [x] Hidden themes section from settings sheet (placeholder until design is finalized)

### Phase 17: Bug Fixes & Polish ✓

**Bug fixes**
- [x] "No faces detected" now uses toast pattern instead of static text overlay
- [x] Fixed regeneration guard blocking effects-only GIFs (scale 1.0) when re-editing existing GIFs
- [x] Fixed first item in horizontal effect carousels getting clipped when selected (added horizontal padding)
- [x] Fixed slider fill bar bleeding outside container bounds (changed fill from RoundedRectangle to Rectangle; parent clipShape handles rounding)
- [x] Reordered effect category tabs: face filters now second (zoom → face → image)

**Heart Eyes dual sliders**
- [x] Added speed parameter to HeartEyesEffect controlling bounce animation frequency
- [x] Heart Eyes first slider relabeled from INTENSITY to SIZE
- [x] Speed buckets: SLOW / MEDIUM / FAST / HYPER

**Editor UX**
- [x] Auto-dismiss editor 1.5s after successful save (both new save and update original)
- [x] Scroll position preserved when switching between effect category tabs (ScrollViewReader auto-scrolls to selected effect on tab reappear)

**Gallery UX**
- [x] Fixed header position shift when entering/exiting multi-select mode (stable left-aligned title with maxWidth frame)
- [x] Smooth bottom bar transitions between normal and select modes (slide-from-bottom + opacity)
- [x] Added EnhancePressButtonStyle (ButtonStyle-based) for press animation on PhotosPicker and all gallery buttons
- [x] Applied consistent press animation to MAKE A GIF, CREATE YOUR FIRST GIF, COPY, SHARE, DELETE buttons

### Phase 17b: App Store Rejection Fix & Onboarding Redesign ✓

**App Store rejection fix (Guideline 2.1a — App Completeness)**
- [x] Fixed blank screen on first launch: `PHPhotoLibrary.shared().register(self)` in PhotoManager.init() triggered the permission dialog immediately; deferred observer registration until after authorization is granted
- [x] `hasLoadedGifs` now set to `true` when permission is denied (prevents permanent blank state)
- [x] `onAppear` no longer requests authorization if status is `.notDetermined` — permission is deferred to user action

**Onboarding redesign**
- [x] New showcase carousel on first-launch screen with 8 bundled GIFs demonstrating app effects
- [x] ShowcaseCarousel component: infinite loop, center-scale effect (305pt center / 265pt edge), swipe gestures, tap-to-center, slow auto-scroll (left-to-right drift)
- [x] Carousel supports both static images (.image) and animated GIFs (.gif via AnimatedGifView)
- [x] "MAKE YOUR FIRST GIF" button requests photo access permission, then presents PhotosPicker
- [x] Centered "ENHANCE" title, tagline text blocks matching Figma design

**Permission denied state**
- [x] Dedicated denied-state view with carousel, explanation text, "OPEN SETTINGS" button, and "CREATE GIF WITHOUT SAVING" fallback PhotosPicker
- [x] `scenePhase` observer re-checks authorization when returning from Settings (only when status is determined)
- [x] SAVE button hidden in editor when photo access is denied; SHARE button remains available

**Visual polish**
- [x] Mesh gradient animation updated to diagonal sweep (3 mesh points animate diagonally)
- [x] New image effects: Monotone, Duotone, Heat Haze, Bloom, Motion Blur, Inversion, Vintage Grain, Pop Art
- [x] Duotone color selector using LaserColor enum presets
- [x] Effect thumbnails on visual effect buttons (pixelated preview of image with effect applied)
- [x] Face effect buttons disabled/dimmed when no faces detected
- [x] Removed old StaircaseSquares NUX icon

### Phase 17c: Codebase Audit & Gallery Cache Recovery ✓ (session 14)

**Full-codebase bug audit**
- [x] Reviewed all ~8,600 lines plus both docs; catalogued 12 defects across 4 severity tiers
      in the "Known Bugs" section at the top of this file, each anchored to file and line

**Gallery cache recovery (P0 — user-reported disappearing GIFs), Stage A**
- [x] Replaced the photo URL path: `requestContentEditingInput` → `requestImageDataAndOrientation`
      (`version = .original`, `isNetworkAccessAllowed = true`) in `copyOriginalImageData(for:destination:)`
- [x] `requestAVAsset` restricted to genuine video assets (it can never succeed for a photo)
- [x] `cleanupStaleCacheFiles()` gated on a complete, untimed-out fetch that resolved every asset
- [x] `group.notify` → `group.wait(timeout: 30s)` so a stalled request cannot pin `isFetching`
- [x] Added `LeaveGuard` — idempotent `DispatchGroup` leave, safe against repeated or missing
      Photos callbacks
- [x] `ThumbnailCache.directoryName` exposed and skipped by the stale-file sweep; thumbs directory
      re-created on every write instead of only in `init`

**Test suite**
- [x] Repaired 3 stale tests that had been failing on `main` (see "Test suite" section above)
- [x] Added `EnhanceTests/GIFLibraryCacheTests.swift` — 5 tests covering `LeaveGuard` balance
      semantics and `ThumbnailCache` directory recovery
- [x] Suite green: 92 passing / 0 failing (was 89 / 3)

**Effect retirement (soft-remove, implementations kept)**
- [x] Retired 6 image effects from the picker: MONOTONE, DUOTONE, BLOOM, INVERSION,
      VINTAGE GRAIN, POP ART. Verified none are used by `FaceFilterType` before retiring.
- [x] Added `VisualEffectType.retired` (a `Set`) and `VisualEffectType.selectable`. The picker
      and thumbnail generation walk `selectable`; the test suite keeps walking `allCases` so the
      retired implementations stay compiled and exercised. Re-enabling = delete one set entry.
- [x] Visible effects now 8: CHROMA SHIFT, HALFTONE, FISHEYE, SWIRL, PIXELATE, RAINBOW,
      HEAT HAZE, MOTION BLUR
- [x] 3 tests added covering the retirement mechanism; suite 95 passing / 0 failing
- [ ] **`supportsColorPicker` now has no visible consumer** — Duotone was its only one. The
      `duotoneColor` plumbing (`EditorViewModel`, `EditorSnapshot`, `EditorView.duotoneColorPicker`,
      the `.onChange` regeneration handler) is intact but dormant. Intended next use is Gradient
      map; rename `duotoneColor` → `effectColor` when that lands. A test asserts this state so it
      fails loudly the moment a new effect claims the picker. **Do not delete as dead code.**

### Phase 17d: New Image Effects — Phase 1 ✓ (session 14)

Carousel 8 → 11 visible effects, all stock Core Image, no new build infrastructure.

> **Course correction.** This phase initially shipped 9 colour-grade presets (SEPIA, VINTAGE,
> WARM, COOL, FADE, VIVID, CONTRAST, NOIR, MONO) alongside the three below. They were cut on
> review — they were never actually wanted. The plan carried them because the question asked
> was *how* they should appear in the UI rather than *whether* they were wanted at all.
> Implementations are in commit `148d105` if any are ever needed.
>
> Gradient Map also changed: the original six predefined ramps were replaced with three
> user-picked colours via native `ColorPicker`.

**Groundwork**
- [x] `EffectOptions` struct replaces the growing positional parameter list on
      `VisualEffectType.effect(intensity:options:)`
- [x] Renamed `duotoneColor` → `tintColor` throughout (a param named for a retired effect
      is a trap — Colored Edges shares it)
- [x] `EffectPickerKind` replaces the hardcoded `supportsColorPicker` view; `supportsColorPicker`
      is now derived so the two cannot drift
- [x] Deduplicated `duotoneColorPicker` / `laserColorPicker` into one `colorSwatchRow(selection:)`
- [x] `requiredFilterNames_exist` test — `applyingFilter` fails *silently* on an unknown name

**Effects**
- [x] **GRADIENT** — luminance → colour ramp via a memoised 32³ `CIColorCubeWithColorSpace`.
      Three user-picked stops (`GradientStops`: dark / mid / light) using native `ColorPicker`
      for unrestricted colour choice. Bare swatches — no labels, no ramp preview; the two-stop
      toggle went with the MID label it was attached to, so ramps are always three stops
- [x] **EDGES** — Sobel via `CIEdges`, tinted from `LaserColor`, over a darkened original
- [x] **DITHER** — `CIDither` then `CIColorPosterize` (that order is the effect: noise pushes
      values across posterise boundaries so gradients stipple instead of banding)

**Coalescing for continuous controls**
- [x] `ColorPicker` writes on every drag frame of the system colour wheel, unlike sliders which
      have a drag-end commit. Added `pushUndoCoalesced(previousStops:)` (max one undo entry per
      0.7s, capturing the *pre*-change value via `onChange`'s `old`) and `scheduleRegenerate()`
      (debounced 0.45s) so the wheel doesn't flood the undo stack or regenerate per frame
- [x] Cube cache keyed on resolved RGB rather than a preset enum, bounded at 12 entries — users
      can produce unlimited distinct ramps. Intensity never affects the cube, so dragging the
      intensity slider always hits the cache

**Verification**
- [x] Rendered every new effect to PNG against a rich test fixture and inspected them — caught two
      bugs that all structural tests passed (see LEARNINGS 2026-08-07 on the linear working space)
- [x] Suite 95 → **108 passing / 0 failing**
- [x] **DITHER read as noise and sat static over the zoom** *(fixed 2026-08-07)*. Two causes:
      the pattern was generated at native pixel resolution (too fine), and effects are applied
      *after* the zoom transform so its cell size was fixed in output space while the preview
      applies effects pre-zoom. Added a `frameScale` parameter to `VisualEffect` (defaulted
      overload, same pattern as `viewportCenter`) so cell size tracks the zoom and both paths
      agree, plus a SCALE slider for cell chunkiness. See LEARNINGS 2026-08-07.
- [ ] **`ColorPicker` aesthetics** — the system colour wheel is a modal iOS sheet and will look
      foreign against the Silkscreen pixel-art styling. Accepted deliberately for the colour
      freedom; revisit if it grates in use.

### Phase 17g: Drill-down effect UI ✓ (sessions 14–15)

Cards browse, a panel edits. Replaces the stacked full-width control rows, which had a hard
two-slider ceiling and no room to grow.

**Framework (Stages 1–7)**
- [x] `EffectParameter` declarations are the single source of truth for an effect's UI — adding
      a control is a line in `parameters`, with no layout change and no per-effect branching
- [x] Namespaced keyed value store (`parameterValues`), so `VisualEffectType.fisheye` and
      `FaceFilterType.fisheye` cannot collide
- [x] Dotted numeric sliders quantised to a 20-step lattice, so the knob's number is honest
- [x] `EffectDetailPanel` with discard/confirm semantics — one undo entry per visit, and global
      undo disabled while it is open
- [x] Cards scale from measured space up to 160pt, and face-filter thumbnails

**Stage 8 — cleanup**
- [x] Deleted every computed shim (`effectIntensity` / `effectSize` / `faceFilterIntensity` /
      `faceFilterSpeed`), `supportsSizeControl`, `secondSliderLabel`, `FaceFilterType`'s three
      label properties, and `EffectParameter.unselectedKey`. Kept `colorPickerKind` /
      `supportsColorPicker` — `parameters` is built from them
- [x] Deleted three zero-reference files: `AnimatorPickerView`, `AnimationConfig`,
      `PreviewControlsView`
- [x] **Fixed a double undo push.** The panel passed `onBeginDrag: { pushUndo() }` *and*
      `commitEditing()` pushed the entry snapshot, so dragging a slider then confirming recorded
      two entries and the second undo stepped the user **forward**. The existing "exactly one
      entry" test missed it by calling `setValue` directly, bypassing the row

**The ZOOM tab**
- [x] Cards + detail panel, matching the other two tabs and fixing the SE 3 overflow
- [x] SPEED and PAUSE are continuous over the generator's real clamps. Speed is **geometric**
      (`0.25 · 16^u`) so equal travel means equal ratio, 1× sits at the track midpoint, and both
      defaults land on lattice steps — an off-lattice default would snap on first touch and
      silently change a value the user never edited. Pause is linear over 0–5s
- [x] `isDefaultSpeed` is tolerant, not `==`: the geometric round trip yields
      `0.5000000000000001`, which would otherwise leave RESET on screen forever
- [x] MOTION is a `SegmentedBar` bound to a normalising `modifierSelection`, so `nil` stays
      canonical for "no modifier" everywhere else in the model
- [x] Dropped the undebounced `.onChange(of: playbackSpeed / pauseDuration)` regeneration — fine
      for discrete buttons, a full GIF render per value change for a continuous slider

**Browse-card polish**
- [x] **The ZOOM cards show a framing, not a flat fill.** The three animators travel
      between the same two endpoints and differ only in the path, so each card shows the
      framing that type ends on: ZOOM IN tight, ZOOM OUT wide, PULSE between them. PULSE
      is deliberately *not* its true last frame — `sin(π)` returns it to where it started,
      so a literal reading would make its card identical to ZOOM OUT's
- [x] Falls back to a representative centred 2.5x until the user sets a zoom. Without it
      the two endpoint framings are identical and all three cards show the same untouched
      photo
- [x] **Carousel edges dissolve instead of slicing a card.** The gallery now spans the
      full screen width and insets its content to the canvas edges; clipping at the canvas
      width put the cut on a line the layout treats as a margin, so a sliced card read as
      a rendering fault rather than as content continuing off-screen. The fade is driven
      from `ScrollGeometry`, so it appears only on the side that actually has more content
      — this is the carousel's only "there is more" cue, since it has no scrollbar
- [x] One `EffectCarousel` component replaces three near-identical copies of the scroll
      view, one per tab

**Discoverability**
- [x] **An arrival hint tells the user to pinch.** Nothing on the editor said that pinching
      the canvas is how the zoom target gets chosen, so a first-time user could reasonably
      tap ENHANCE and be told off for it. Reuses the ENHANCE nag's own toast chrome — same
      instruction, arriving earlier — and latches off the first time they work the canvas
- [x] Dismissal is driven from the scroll view's `willBegin` delegate callbacks, not from
      `currentScale` changing. Those two are also written *programmatically* (an existing
      GIF restores its saved zoom; the nag bounces the scale), and a value-based signal
      cannot tell a real gesture from either

**Deliberately unreachable, not removed**
- [ ] **Zoom is always on.** One of the three zoom types is always selected; there is no NONE
      card and cards do not toggle off. **Consequence: effects-only GIFs at 1× are impossible.**
      Because this is provisional, the `nil`-animator paths (`hasEffectsWithoutZoom`,
      `activeAnimator`'s `StaticAnimator` branch, `regenerateGIF`'s `selectedAnimatorType == nil`
      gate) are kept intact but unreachable, so reversing it is a UI change rather than a
      re-implementation. **If it is ever re-exposed, note that `activeAnimator` returns a bare
      `StaticAnimator()` and silently discards the modifier** — that path was already broken
      before it became unreachable.

### Phase 17h: LENS — radial chromatic dispersion ✓ (2026-08-09)

> Full analysis, evidence and parameter table in
> **[FEATURE-LENS-DISTORTION.md](FEATURE-LENS-DISTORTION.md)**. This section tracks status only.

Ported from a Figma shader effect via the Figma MCP. **The shader source is not obtainable** —
the capture harness states it outright — so the algorithm is a reconstruction from measured
renders, not the Figma implementation. Five properties were identified by numeric measurement
(radial chroma profiles, disc extent, pairwise pixel diffs), and one of them turned out to be
**inert across its entire range**.

Despite the name, the effect is not geometric distortion: it is radial prismatic dispersion.

- [x] `LensDistortionEffect: VisualEffect` — three `CIZoomBlur` passes, one per colour channel at
      different amounts, recombined additively, masked by a `CIRadialGradient` for reach.
- [x] Two sliders only: **AMOUNT** (geometric mapping) and **REACH** (linear). Reuses the existing
      `intensityID` / `sizeID` constants.
- [x] `VisualEffectType.lensDistortion` + `FaceFilterType.lensDistortion`, the latter one line
      through `FaceVisualEffect`.
- [x] **No `FrameGeometry`, deliberately.** A lens aberration is anchored to the lens, not the
      subject, so staying locked to the output frame under zoom is correct rather than the
      crawling bug DITHER had. This must be stated in the doc comment or someone will "fix" it.
- [x] `.cropped(to: image.extent)` is mandatory — `CIZoomBlur` grows its extent, the exact
      failure that produced a black band for FISHEYE, SWIRL and PIXELATE.

**Why this is cheap:** no new `EffectParameter.Kind`, no picker, no `EditorSnapshot` field, no
`CIKernel`, no pbxproj edit. Two rows sits inside the measured three-row panel ceiling.

**Open product questions** (in the feature doc): whether it overlaps CHROMA SHIFT too much — that
also ships in both carousels and is linear rather than radial — and whether "LENS" or "PRISM"
describes it more honestly than "LENS DISTORTION".

### Phase 17i: Feature Scrambler ✓ — THIRD EYE (V1) + layout pack (Stage E) shipped 2026-08-10

> Full specification in **[FEATURE-SCRAMBLER.md](FEATURE-SCRAMBLER.md)**. This section records
> the review outcome, the re-scope, and what V1 actually shipped.

Copies eyes and mouth to deliberately wrong positions. The engineering design is sound — Core
Image compositing rather than a kernel, a reusable region compositor as the strategic payload,
and a Stage A prototype rendered *through GIF encoding* before any real work, which is exactly
the lesson EDGES and the black band taught.

**Shipped THIRD EYE as V1 — no layout picker.**

- [x] **Stage B — landmark groundwork.** `FaceRegions` (eye/lip/nose polygons) + `LandmarkQuality`
      added to `DetectedFace`, defaulted so the many memberwise-init call sites stayed source-
      compatible. Only the precise Vision path populates them; rectangle, CIDetector, and animal
      paths stay `.estimated` with empty regions. `scaled(x:y:)` carries them, with a test that
      enumerates every region point so a future field cannot be forgotten.
- [x] **Stage C — reusable compositor.** `FaceRegion` (source resolution + eye fallback to pupil
      /width, mouth unavailable without lips), `FaceRegionMaskBuilder` (lazy soft-alpha elliptical
      mask), `FaceRegionCompositor` (crop → clamp → mask → transform → composite, extent-preserving,
      no `CIContext`/`createCGImage`). Colored-fixture tests prove sampled pixels land at the
      destination. This is the strategic payload the whole feature existed to leave behind.
- [x] **Stage D — THIRD EYE vertical slice.** `FeatureScramblerEffect` + `FaceFilterType.scramble`,
      INTENSITY + SIZE via the existing `secondaryID` convention (two rows, fits SE 3),
      `requiresSingleFace`. Timeline reveal `0.15→0.75` with a single `smoothstep` settle,
      deterministic (no `frameIndex`, no unseeded randomness). Intensity 0 is an exact no-op; any
      positive value keeps the tuned opacity floor. Parity table updated. Padding/feather/placement
      constants locked after visual QA on a real photo.
- [x] **Stage C2** (face-effect render perf prerequisite) was already done — see "Next up" step 1.
- [x] **Stage D2 — device pass confirmed 2026-08-10.** Looks good on device; no crawling, seams,
      or stale preview reported. Deep-matrix edge cases (4× 12-frame floor, animal fallback) can be
      spot-checked opportunistically but are no longer blocking.

**Stage E — layout pack ✓ shipped 2026-08-10 (pending device QA on the new layouts).** MOUTH EYES,
EYE MOUTH, and SHUFFLE behind a preset-row picker.

- [x] **`ScrambleLayout` enum** owns per-layout availability and placement specs. THIRD EYE copies
      one eye to the forehead (V1 mapping preserved exactly); EYE MOUTH enlarges an eye onto the
      mouth; MOUTH EYES copies the mouth onto both eyes; SHUFFLE is a three-way cycle
      (left eye→right, right eye→mouth, mouth→left). Feature-to-feature placements scale to fit the
      destination feature, modulated by SIZE. `FeatureScramblerEffect` iterates the specs, sampling
      every placement from the original so a swap is a true swap.
- [x] **Skin heal so features move, not stack.** Before compositing a moved feature, the layout
      covers the feature it *replaces* with skin sampled from just beside it (same vertical level,
      toward the face centre — the nose bridge / cheek — so it matches local shading rather than one
      global tone). THIRD EYE heals nothing (the real eyes stay); EYE MOUTH heals the mouth; MOUTH
      EYES heals both eyes; SHUFFLE heals all three. Fully lazy (`CIAreaAverage`). A moved feature
      still carries a soft patch of its *source* skin — subtle on real faces, only obvious on an
      extreme tone gradient; tighten placement padding/feather if a real photo shows a halo.
- [x] **INTENSITY dropped.** The effect only reads well at full strength, so it always renders
      opaque and the slider is gone. The panel is **two rows** — SIZE (the single slider, in the
      primary slot) + LAYOUT — which fits SE 3 with room to spare
      (`panel_threeRowsFitWithoutScrollingOnShortPanel` still guards the 3-row general case).
      LAYOUT is a new `EffectParameter.Kind.preset` backed by a **dedicated typed `scrambleLayout`**
      on the view model *and* `EditorSnapshot` — never a numeric-store case index. Captured, restored,
      and reset with the rest of the snapshot.
- [x] **Availability + normalization.** Mouth layouts need precise lips; swaps need both eyes; a
      profile face degrades to THIRD EYE / EYE MOUTH. The preset row shows only available layouts,
      and `toggleFaceSelection` collapses a stored layout the new face can't support to THIRD EYE
      (no hidden invalid layout). `onlyLazerEyesAndScrambleDeclareAPicker` updated for the new owner.
- [ ] **Device QA on the new layouts (Stage E's D2).** THIRD EYE is device-confirmed; MOUTH EYES /
      EYE MOUTH / SHUFFLE verified only by rendered fixtures. Watch feature-fit scale on real faces,
      the SHUFFLE cycle reading clearly, and the three-row panel not scrolling on a physical SE 3.

Free requirements noted during the port: pause frames already reuse one rendered image, so
"byte-stable" needs nothing from the effect; and the `scaled()` enumeration test knows
`normalizedBoundingBox` is deliberately unscaled.

### Phase 17e: New Image Effects — Phase 2 (not started, deliberately deferred)

> Full specifications live in **[EFFECTS.md](EFFECTS.md)** — build mechanics, per-effect
> algorithms, and the list of candidates deliberately rejected. This section tracks status only.

**Moved behind Phases 17h and 17i on 2026-08-09.** This phase used to sit in front of the
interesting effect work on the assumption that porting Figma *shader* effects would require
`CIKernel` infrastructure. The LENS analysis (Phase 17h) disproves that: a Figma shader effect
reconstructed to about eight stock Core Image nodes with no kernel at all. Since this phase
carries the project's highest runtime risk, deferring it behind two shippable effects is a
straight de-risking with no cost. Do it when an effect genuinely cannot be built without it —
Riso Print is still the strongest such candidate.

- [ ] **CIKernel infrastructure.** Build rule scoped to `*.ci.metal`, so `-fcikernel` does not
      reach `Pixellate.metal`. Target-scope flags would break the animated canvas border **at
      runtime** — the highest-risk change remaining in the project.
- [ ] **De-risking gate.** Passthrough kernel, then confirm the border still renders in both
      `EditorView` and `GradientViews` before writing any effect math.
- [ ] **Riso Print** — the first kernel, and the most distinctive look available. Built from
      algorithm description; the original WGSL was never available.
- [ ] Then, in rough value order: Hatching, Slice shift, Pixel stretch, Pattern refraction,
      Water caustic. Hatching and Slice shift may not need kernels at all — try `CIEdgeWork`
      and strip compositing first.

### Phase 17f: Control audit — expose the parameters the new UI can now carry

The drill-down panel removed the two-slider cap, but no existing effect was revisited
afterwards. Several still collapse independent qualities into one INTENSITY slider, or
hardcode a value a user would want to change.

**Candidates are already identified with file and value** in
[EFFECTS.md → Control audit](EFFECTS.md#control-audit--effects-with-hidden-parameters) —
this is a pass over that table, not an investigation from scratch.

- [ ] Highest value first: **DITHER** (LEVELS + MONO), **MOTION BLUR** (ANGLE — a directional
      blur whose direction is hardcoded to 45°), **SWIRL** (SIZE — straight parity gap with
      FISHEYE), **HALFTONE** (SHARPNESS + ANGLE, both already supported by `CICMYKHalftone`).
- [ ] Then: HEAT HAZE (FREQUENCY + SPEED), CHROMA SHIFT (ANGLE), GRADIENT (MIDPOINT),
      PIXELATE (SHAPE — `CIHexagonalPixellate` makes hex nearly free), RAINBOW (SPEED, which
      the face variant already has).
- [ ] Prefer **splitting coupled qualities** over inventing new parameters. Most of these are
      one slider driving two independent things; separating them makes currently-unreachable
      looks reachable without changing what the effect is.
- [ ] Respect the panel budget — `parameters.count <= 5` and `pickers.count <= 1` are enforced
      and exist because the browse state has no scroll. Raise the cap deliberately if needed,
      and re-check a short device; do not just relax the assertion.

### Phase 18: Settings & Social

> The dead `themesSection` scaffolding in `SettingsView` is claimed by
> [FEATURE-THEMES.md](FEATURE-THEMES.md) Stage 5 — don't repurpose it here.

- [ ] Add "RATE THE APP" row in settings with 5 star icons (opens SKStoreReviewController or App Store URL)
- [ ] Add "SHARE WITH FRIENDS" row in settings (presents UIActivityViewController with App Store URL)

### Phase 19: Effects Rethink (needs design)

- [ ] IG-style color filters — add a "FILTERS" category with CIFilter-based color presets (warm, cool, vintage, vivid, etc.) alongside existing effects
- [ ] Auto-zoom on enhance — when no zoom is set, auto-zoom slightly toward center or a detected face before generation
- [ ] Toggling off all zoom types resets canvas to 1.0x / full frame (currently StaticAnimator holds the user's zoom position)

### Phase 19b: Effect reuse & stacking (needs design)

Two related features. Both are more feasible than they look, because groundwork landed for
other reasons — and each has one specific catch worth deciding knowingly.

**Copy effects from one photo to another**

- [ ] `EditorSnapshot` is already exactly the payload to copy — it captures animator, modifier,
      speed, pause, visual effect, `parameterValues`, category, face filter, and all three
      colour selections, and undo/redo already round-trips it. A "copy settings / paste
      settings" feature is largely a matter of deciding what *not* to carry.
- [ ] **Strip the photo-specific fields.** `selectedFaceIndex` is meaningless on a different
      photo, and a face filter pasted onto a photo with no faces needs a defined outcome
      (drop it, or keep it inert and let the existing no-faces blocking handle it). Zoom
      (`currentScale` / `visibleRect`) is not in the snapshot and should stay out — the subject
      is somewhere else in a different photo.
- [ ] **Making it persist changes an existing constraint.** `EffectParameter`'s doc comment
      notes that parameter ids are in-memory only today, so the "ids must not change once
      shipped" warning does not yet bite. Saved presets make ids load-bearing and introduce a
      migration concern. In-session copy/paste avoids this entirely; saved presets do not.
- [ ] `GradientStops` holds SwiftUI `Color`, which is not directly `Codable` and whose equality
      LEARNINGS calls opaque. `GradientStops.resolved` already yields clamped sRGB triples —
      persist those, not the `Color`s.

**Stack multiple effects on one photo**

- [ ] **The render pipeline already supports it.** `generateGIF` takes
      `visualEffects: [VisualEffect]`, and `applyVisualEffects` chains them lazily, so N effects
      still cost one render per frame (LEARNINGS 2026-03-08 on CIImage chaining). Only
      `selectedVisualEffect: VisualEffectType?` — a single optional — stands in the way.
- [ ] **The parameter store already handles it.** Values are keyed per effect
      (`"<namespace>|<effect>|<paramID>"`), so every effect in a stack keeps its own settings
      with no further work.
- [ ] ⚠️ **This reverses a documented decision.** Effects *were* stackable via
      `Set<VisualEffectType>` and were deliberately changed to single selection — LEARNINGS
      2026-03-08 records why: chained CIFilters "produced unpredictable, unpleasant results"
      and emergent behaviour that is hard to preview or control. That entry's own suggested
      path is worth taking seriously: *"if stacking is needed later, it should be done through
      intentional, curated presets rather than free-form combination."*
- [ ] Order matters — CIFilter chains are not commutative, so a stack needs a defined and
      probably reorderable order, which is a new UI concept the drill-down panel does not have.
      The panel edits one effect at a time, so stacking likely means a layer list that drills
      into the existing panel per layer.
- [ ] Cheapest first step, if the concern above holds: ship a small set of **curated
      combinations** as single entries rather than free-form stacking. Same visual payoff, none
      of the unpredictability, and no UI concept to invent.

**They compose.** Once a stack exists, the copyable payload is the stack — so settle the
stacking model before designing the copy format, or the format will need reworking.

### Phase 19c: Animated text overlays (Stage A–C written, unverified)

**Status: Stages A–C exist on `feature/text-overlay-renderer` and have never been compiled.**
They were written without a macOS toolchain, and there is no CI, so the first Xcode session owns
getting them to build and proving the gates. The branch adds nine files and modifies none, so it
cannot break the app. **§18 of the plan is the handoff**: what exists, the likely first errors,
the order to run the tests, and what a failure in each one actually means.

Stages D–G are not started. The file manifest is §17.

Full product, rendering, gesture, UX, accessibility, and test plan:
**[FEATURE-TEXT-EFFECTS.md](FEATURE-TEXT-EFFECTS.md)** — **revision 2 (2026-08-10)**, which moves
pinch-to-resize and free rotation into V1 and rewrites the renderer and gesture sections around
them. Revision 2 §2 also records three defects found in revision 1: it assumed snapshot-test
infrastructure this repo does not have, it claimed 1× effects-only generation that "Zoom is always
on" makes unreachable, and it left the overlay uneditable after ENHANCE because the canvas swaps to
`GIFPreviewView`.

Stages A–G in the plan; the gate for each is in §11.

- [~] **Stage A** — *written, unverified.* One CoreText layout, one master raster, non-overlapping tiles. Prove the
      partition invariant and Arabic joining before anything else is built on it.
- [~] **Stage B** — *written, unverified.* The shared transform and the export compositor, still headless.
- [~] **Stage C** — *written, unverified.* Five zoom-synchronized entrance presets: POP, RISE, TYPE, WORD DROP, FLICKER.
      Establish generation-time, memory, and GIF-size budgets from this prototype.
- [ ] **Stage D** — composite text after the existing face → zoom → visual-effect pipeline;
      `textOverlay == nil` must stay byte-identical.
- [ ] **Stage E** — repair `regenerateIfNeeded`'s dropped-edit P1 first, on its own commit. Direct
      manipulation makes it fire constantly instead of occasionally.
- [ ] **Stage F** — first-touch gesture routing and the two-phase editor. The photo pans and zooms
      exactly as under every other category; a gesture starting on the text moves, scales or
      rotates it. Preset carousel → keyboard → DONE → three-row settings panel, as one undo entry.
- [ ] **Stage G** — hardening. Prove emoji, composed-character, ligature, multiline and RTL
      correctness, and profile on the oldest supported device.

Cross-cutting: include text in undo/redo, reset, regeneration, save, and share; keep the live
canvas (not the baked GIF) while the TEXT category is active.

Deliberately left for the wave after V1, and shaped for in §16: **fill effects** — static and
animated gradients, sparkle — plus font choice. These are all fills over fixed glyph geometry, so
V1's rasterizer keeps the glyph coverage mask as a distinct step to leave the seam in the right
place. Font is already modelled (`TextFont` carries five cases); V1 simply ships Silkscreen Bold
and no picker.

### Phase 20: Onboarding & NUX

- [ ] Add 5 default onboarding photos to show how the app works (think Tom from MySpace)
- [ ] Viral unlock: "Give the gift of a GIF" — send a GIF to unlock face effects

### Phase 21: Customization & Themes

> Themes are fully planned in **[FEATURE-THEMES.md](FEATURE-THEMES.md)** — the slot contract, the
> staged migration, and the boundaries of what must *not* follow a theme. Read it before starting:
> the headline finding is that this is a **migration, not a feature**. There is no design system to
> extend (one token, ~340 colour literals across ~22 files), so the first stage is reconciling
> duplicate values while the app is still dark-only.

- [ ] Custom app icons (pick a GIF from gallery, set thumbnail as app icon)
- [ ] **Custom app themes** — appearance (light/dark/system) × user-authored colour schemes.
      Colours only; font-token cleanup is separate, non-blocking work
- [ ] Create custom pixel-art icons for remaining UI elements

### Phase 22: Future Features

**Editor UX**
- [ ] Fix copy text for action buttons
- [ ] Stateful save button (show saving state, success confirmation, error feedback)
- [ ] Pause/edit during animation preview (pause playback, adjust zoom point, resume)
- [ ] Fix RESET/X spacing in editor header (RESET looks like a label for X — add visual separation)
- [ ] Crosshair overlay on photo canvas when zoomed in (shows zoom focal point)

**Real-Time Effects via Metal Shaders**
- [ ] Metal shader pipeline: `.distortionEffect()`, `.colorEffect()`, `.layerEffect()` (iOS 17+)
- [ ] Replace CIFilter-based preview with GPU shader modifiers for zero-latency preview
- [ ] New shader-based effects: wave/ripple, swirl, heat shimmer, pixelation, VHS glitch

**Undo / History**
- [x] Undo/redo stack for editor (track effect, speed, pause, zoom changes; button to step back/forward) — completed in Phase 13b
- [ ] UNDO button for existing GIF editing (revert all changes back to the original saved state)

**New Animation & Content**
- [ ] Add Bounce, Dramatic Zoom, Loop Zoom base animation styles
- [ ] Animated text overlays — tracked in Phase 19c and
      [FEATURE-TEXT-EFFECTS.md](FEATURE-TEXT-EFFECTS.md)

**Settings & Preferences**
- [x] General settings sheet (expandable: auto-play, app icon selection) — completed in Phase 10 (session 10)
- [ ] App themes (fonts and colors) — section hidden in settings until design is finalized

---

## Architecture

```
App/              → Entry point, font registration
Models/           → Data types (AnimatorType, ModifierType, VisualEffectType, EffectCategory, AnimationConfig, DetailContent, etc.)
Services/         → Business logic (GIF generation, photo library, permissions)
  Animators/      → Animator + MotionModifier + VisualEffect protocols, CompositeAnimator, per-effect files
Features/
  Gallery/        → Gallery screen + pinch-to-reflow grid (GalleryView)
  Editor/         → Editor screen + logic (EditorView, EditorViewModel)
Components/       → Shared reusable UI (15 components: ImageCanvasView, GIFPreviewView,
                    SegmentedBar, GifGridItem, ShareSheet, BottomSheet,
                    ZoomFrameOverlay, AnimatorPickerView, PreviewControlsView,
                    GradientViews, AppButton, CircleButton, GifBadge,
                    PermissionViews, ShowcaseCarousel)
Design/           → Constants, modifiers, typography
Extensions/       → Swift extensions
Docs/             → This file + LEARNINGS.md
```
