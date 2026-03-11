# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-03-11 (session 5)

## Vision

Enhance is built around a simple creative flow:
**choose a photo → define a focal point → generate motion → refine → save or share.**

Each step should feel fast, tactile, and visually satisfying.

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

### Phase 8i: Future Features

**Editor UX**
- [ ] Stateful save button (show saving state, success confirmation, error feedback)
- [ ] Pause/edit during animation preview (pause playback, adjust zoom point, resume)
- [ ] Fix RESET/X spacing in editor header (RESET looks like a label for X — add visual separation)
- [ ] Crosshair overlay on photo canvas when zoomed in (shows zoom focal point)

**Real-Time Effects via Metal Shaders**
- [ ] Metal shader pipeline: `.distortionEffect()`, `.colorEffect()`, `.layerEffect()` (iOS 17+)
- [ ] Replace CIFilter-based preview with GPU shader modifiers for zero-latency preview
- [ ] New shader-based effects: wave/ripple, swirl, heat shimmer, pixelation, VHS glitch

**Undo / History**
- [ ] UNDO button for existing GIF editing (revert all changes back to the original saved state)
- [ ] Undo/redo stack for editor (track effect, speed, pause, zoom changes; swipe or button to step back/forward)

**New Animation & Content**
- [ ] Add Bounce, Dramatic Zoom, Loop Zoom base animation styles
- [ ] Text overlays with drag-to-position

**Settings & Preferences**
- [ ] General settings sheet (expandable: auto-play, export format, future preferences)

## Phase 9: Bug Fixes & Polish

- [ ] Fix: re-editing a GIF with existing effects sometimes loses or changes the zoom coordinates
- [ ] Delete dead code: GalleryCarouselView.swift
- [ ] Add haptic feedback on key interactions

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
Components/       → Shared reusable UI (14 components: ImageCanvasView, GIFPreviewView,
                    SegmentedBar, GifGridItem, ShareSheet, BottomSheet,
                    ZoomFrameOverlay, AnimatorPickerView, PreviewControlsView,
                    GradientViews, AppButton, CircleButton, GifBadge, PermissionViews)
Design/           → Constants, modifiers, typography
Extensions/       → Swift extensions
Docs/             → This file + LEARNINGS.md
```
