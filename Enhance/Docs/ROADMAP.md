# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-08-07 (session 14)

## Vision

Enhance is built around a simple creative flow:
**choose a photo → define a focal point → generate motion → refine → save or share.**

Each step should feel fast, tactile, and visually satisfying.

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
- [ ] **RESET on an existing GIF leaves the preview stale.** `resetEffects()` (`:265`) clears all
      effects but only touches `enhanceState` in the `.newImage` branch. For an existing GIF it never
      regenerates and never sets `hasModifiedSettings` — buttons go inactive, the displayed GIF keeps
      the old effects, and SAVE stays disabled so the reset cannot be committed.
- [ ] **`saveGIFToLibrary` can save the wrong file.** It reads `gifURL` (`:771`), which falls back to
      `existingGifURL`. If regeneration failed on an existing GIF, "SAVE NEW COPY" silently duplicates
      the original, unmodified GIF. `updateOriginalGIF` correctly requires `generatedGifURL`.
- [x] **A stalled iCloud download can wedge the gallery for the whole session.** *(fixed 2026-08-07 —
      see P0 above.)* The degraded-image early return skips `group.leave()` by design, which is
      correct only if a final delivery always arrives. If it did not, `group.notify` never fired,
      `isFetching` stayed `true`, and `guard !isFetching` made every later refresh a silent no-op
      until relaunch.

### P2 — Performance

- [ ] **Face-effect GIF generation does ~25 full-resolution GPU renders.** `faceEffectedSource`
      (`GIFGenerator.swift:157`) builds a CIImage from the full-size source, applies the effect, and
      calls `createCGImage` once per animation frame plus the pause frame — for a 600×600 output.
      The preview path already downscales to 650px; the GIF path never got the same treatment.
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
- [ ] **Preview images may change aspect ratio.** `configureContentSize` runs only in `makeUIView`
      (`ImageCanvasView.swift:70`). Effects that alter the CIImage extent would make the preview's
      aspect ratio diverge from the source, and `.scaleAspectFill` would crop differently than the
      canvas expects. Unverified — needs checking against the strip-compositing effects.
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

### Phase 18: Settings & Social

- [ ] Add "RATE THE APP" row in settings with 5 star icons (opens SKStoreReviewController or App Store URL)
- [ ] Add "SHARE WITH FRIENDS" row in settings (presents UIActivityViewController with App Store URL)

### Phase 19: Effects Rethink (needs design)

- [ ] IG-style color filters — add a "FILTERS" category with CIFilter-based color presets (warm, cool, vintage, vivid, etc.) alongside existing effects
- [ ] Auto-zoom on enhance — when no zoom is set, auto-zoom slightly toward center or a detected face before generation
- [ ] Toggling off all zoom types resets canvas to 1.0x / full frame (currently StaticAnimator holds the user's zoom position)

### Phase 20: Onboarding & NUX

- [ ] Add 5 default onboarding photos to show how the app works (think Tom from MySpace)
- [ ] Viral unlock: "Give the gift of a GIF" — send a GIF to unlock face effects

### Phase 21: Customization & Themes

- [ ] Custom app icons (pick a GIF from gallery, set thumbnail as app icon)
- [ ] Custom app themes (fonts and colors)
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
- [ ] Text overlays with drag-to-position

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
