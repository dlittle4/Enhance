# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-03-13 (session 12)

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

### Phase 14: Onboarding & NUX

- [ ] Add 5 default onboarding photos to show how the app works (think Tom from MySpace)
- [ ] Viral unlock: "Give the gift of a GIF" — send a GIF to unlock face effects

### Phase 15: Customization & Themes

- [ ] Custom app icons (pick a GIF from gallery, set thumbnail as app icon)
- [ ] Custom app themes (fonts and colors)
- [ ] Create custom pixel-art icons for remaining UI elements

### Phase 16: Future Features

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
Components/       → Shared reusable UI (14 components: ImageCanvasView, GIFPreviewView,
                    SegmentedBar, GifGridItem, ShareSheet, BottomSheet,
                    ZoomFrameOverlay, AnimatorPickerView, PreviewControlsView,
                    GradientViews, AppButton, CircleButton, GifBadge, PermissionViews)
Design/           → Constants, modifiers, typography
Extensions/       → Swift extensions
Docs/             → This file + LEARNINGS.md
```
