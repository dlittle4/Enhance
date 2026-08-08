# Enhance — Learnings Log

> Decisions, gotchas, and patterns discovered during development.
> Each entry records context so future sessions don't repeat mistakes.

---

## 2026-03-07: PhotosPicker tap interception bug

**Problem:** Tapping the "+" button and "CREATE YOUR FIRST GIF" button did nothing — the system photo picker never appeared.

**Root cause (two issues):**
1. The `enhanceButtonAnimation()` modifier adds a `DragGesture(minimumDistance: 0)` via `.simultaneousGesture()`. When applied to the label of a `PhotosPicker`, this gesture consumed touch events before the picker could respond.
2. The `AppButton` component wraps its content in a `Button(action:)`. When used as the label for a `PhotosPicker`, this inner Button intercepted taps, preventing the outer PhotosPicker from receiving them.

**Fix:**
1. Removed `.enhanceButtonAnimation()` from the CircleButton label inside the header PhotosPicker.
2. Replaced `AppButton(...)` with a plain styled `Text` view for the "CREATE YOUR FIRST GIF" PhotosPicker label — same visual appearance, no nested interactive element.

**Rule:** Never place interactive views (Button, gesture-modified views) inside a PhotosPicker label. The label must be purely visual.

---

## 2026-03-07: Architecture decision — Moderate + Feature Folders

**Context:** The app had accumulated a 709-line PhotoDetailView and a 424-line PhotoManager with mixed concerns.

**Decision:** Adopt a moderate architecture:
- One `@Observable` ViewModel per screen (EditorViewModel, GalleryViewModel)
- Protocol-driven services (GIFGenerating, Animator)
- Feature folders (Features/Gallery/, Features/Editor/)
- Shared components in Components/

**Why not lighter:** Pure file splitting without ViewModels would let business logic creep back into views.
**Why not heavier:** Full MVVM + Coordinators would require touching 3-4 files to add a simple slider.

**Rule:** Views contain only layout and styling. ViewModels own state and logic. Services are injected via protocols.

---

## 2026-03-07: Matched geometry IDs fixed

**Problem:** `GifGridItem` uses `matchedGeometryEffect(id: "gif\(index)")` but `EditorView` used `gifURL?.lastPathComponent` as the ID suffix. These never matched, so shared element transitions silently failed.

**Fix:** Added a second associated value to `DetailContent.existingGif(URL, Int)` to carry the grid index through to EditorView. Both sides now use `"gif\(index)"` as the geometry ID.

**Rule:** Matched geometry IDs must be identical on both ends of a transition. Use stable indices or identifiers, never derived values like file names.

---

## 2026-03-08: PhotoManager facade pattern

**Problem:** `PhotoManager` (~550 lines) mixed three unrelated concerns: permissions, photo fetching, and GIF album management. This made it hard to test or modify any single concern in isolation.

**Fix:** Split into three focused services:
- `PermissionManager` — authorization status and requests
- `PhotoLibraryService` — fetching recent photos from the library
- `GIFLibraryService` — fetching, saving, and refreshing GIFs in the "My GIFs" album

`PhotoManager` was kept as a thin facade that composes these services and forwards their `@Published` properties via Combine's `assign(to:)`. This preserves the existing public API — no callsite changes needed.

**Rule:** When splitting a large `ObservableObject`, keep a facade if many views depend on it. Internal services handle logic; the facade handles composition and property forwarding.

---

## 2026-03-08: Replaced system PhotosPicker with in-app photo grid

**Problem:** The system `PhotosPicker` leaves the app context, returns a single image via `loadTransferable`, and offers no visual continuity with the editor.

**Decision:** Created `PhotoGridView` — a full-screen overlay that displays `photoManager.photos` in a 3-column `LazyVGrid`. Each cell has `matchedGeometryEffect(id: "photo\(index)")` which matches the existing ID on `ImageCanvasView`, enabling a fluid hero transition from grid to canvas.

**Key detail:** `GalleryView` now uses plain `Button` actions to open the photo grid instead of `PhotosPicker`. This eliminates the `PhotosUI` import and the `loadTransferable` async callback. Photo data comes directly from `PhotoLibraryService` which already fetches high-quality thumbnails.

**Rule:** Prefer in-app photo grids over system pickers when visual continuity matters. Use `matchedGeometryEffect` with consistent IDs across the transition chain (grid → editor → canvas).

---

## 2026-03-08: Zoom frame minimap for focus area feedback

**Problem:** When the user pinches to zoom in `ImageCanvasView`, there's no visual indication of what region of the full image is selected as the GIF's focus target.

**Decision:** Created `ZoomFrameOverlay` — a minimap that appears in the bottom-left corner of the canvas when `scale > 1.05`. It shows the full image with the area outside `visibleRect` dimmed and a white border around the focus region.

**Implementation:** Uses a reverse-mask technique (`.blendMode(.destinationOut)` inside a `.mask`) to cut out the visible rect from a dim overlay, creating the "everything else is dimmed" effect.

**Rule:** Use `.allowsHitTesting(false)` on informational overlays to avoid interfering with gestures on the underlying interactive view.

---

## 2026-03-08: GIF preview playback controls

**Problem:** After generating a GIF, the user could only watch it loop at 1x with no way to pause or change speed.

**Decision:** Added `PreviewControlsView` with a play/pause button and 0.5x/1x/2x speed selector. `AnimatedGifView` now accepts a `playbackSpeed` parameter that divides `animationDuration` to speed up or slow down playback. The `Coordinator` stores the base duration so speed changes can be applied without reloading frames.

**Rule:** When adding playback controls to `UIViewRepresentable` animation, store the original timing in the Coordinator and derive the displayed timing from it. This avoids compounding speed changes.

---

## 2026-03-08: GIF zoom targets the wrong spot (aspect ratio bug)

**Problem:** The generated GIF didn't zoom to the area the user selected in the canvas. The Pulse effect also started too zoomed in, showing no context.

**Root cause:** `ImageCanvasView.calculateVisibleRect()` assumed the image was square, using `canvasSize * scale` for both dimensions. But with `.aspectRatio(contentMode: .fill)`, a landscape image is rendered wider than the canvas (overflow clipped), and a portrait image renders taller. The visible rect was computed in "square space" but the GIF generator interpreted it in "actual image space" — the coordinate mismatch caused the zoom center to be wrong for all non-square images.

**Fix:**
1. Added `renderedSize` computed property that calculates the actual rendered image dimensions under `.fill`, accounting for the image's aspect ratio: `fillScale = max(canvasSize / image.width, canvasSize / image.height)`.
2. Updated `calculateVisibleRect()` and drag gesture max offsets to use the correct per-axis dimensions.
3. Rewrote `PulseAnimator` to use a sine curve `sin(progress * .pi)` interpolating between `fullViewParams` and `userZoomParams`, so it sweeps from the full image to the target and back — showing full context at the start/end.

**Rule:** When an image uses `.fill` in a square frame, the rendered dimensions depend on the image's aspect ratio. Always compute the actual rendered size using the fill scale factor, never assume square.

---

## 2026-03-08: GIF generator .fit vs .fill mismatch

**Problem:** The generated GIF appeared slightly more zoomed out than the user's canvas selection, and zoom animations swooped diagonally instead of smoothly converging.

**Root cause (two issues):**
1. The GIF generator used `.fit` semantics in `calculateDrawRect` (fitting the image inside the output with letterboxing), while the canvas uses `.fill` (center-cropping to fill the square). At scale 1.0, the GIF showed the *entire* image with black bars, while the canvas showed only the center-cropped portion. The scale factor `S` from the canvas didn't translate correctly — the GIF needed a different effective scale to show the same visible fraction.
2. The ZoomIn/ZoomOut animators linearly interpolated both scale and center position. At low zoom, center shifts are imperceptible; at high zoom, the same shift is magnified. This created a non-uniform visual motion where the image appeared to swing sideways before settling.

**Fix:**
1. Changed `calculateDrawRect` to use `.fill` semantics: `fillScale = max(outputWidth / imageWidth, outputHeight / imageHeight)`. The image now overflows the output in one dimension (clipped), matching the canvas behavior exactly. The canvas scale factor transfers directly.
2. Added `easeInOut()` cubic function and applied it to the progress parameter in `ZoomInAnimator` and `ZoomOutAnimator`. The eased progress synchronizes center movement with scale change, eliminating the swooping artifact.

**Rule:** The GIF generator's drawing mode must match the canvas's content mode. If the canvas uses `.fill`, the generator must also use `.fill` — otherwise scale and center coordinates will be misinterpreted.

**Rule:** When interpolating zoom animations, always ease the progress. Linear interpolation of scale + center creates non-linear visual motion because scale magnifies displacement.

---

## 2026-03-08: Logarithmic scale interpolation for smooth zoom

**Problem:** Even with easing, the zoom animation had a "nothing → sudden burst → nothing" character at high zoom levels (e.g. 12x). The first few frames showed almost no change, then the middle frames contained a rapid zoom, and the final frames were again nearly static. The center panning also appeared as a visible "slide" before zoom kicked in.

**Root cause:** Linear interpolation of the scale parameter distributes equal scale increments per frame. Going from 1x to 12x in 20 frames means +0.58x per frame. But perceptually, going from 1x→2x (doubling) is as significant as going from 6x→12x (also doubling). Linear interpolation spends 1.7 frames on the first doubling and 10 frames on the last doubling — the zoom appears to "explode" in the middle.

**Fix:** Changed `interpolate()` to use logarithmic scale interpolation: `scale = exp(lerp(log(startScale), log(endScale), progress))`. This makes each frame represent an equal *ratio* of zoom change. For 1x→12x: frame 5 is at 1.2x, frame 10 is at 4.25x, frame 15 is at 10.9x — the visual zoom speed is constant throughout.

Center position remains linearly interpolated, which works naturally: at low zoom, center shifts are imperceptible; at high zoom, the remaining center displacement is small. The easing layer (cubic ease-in-out for Zoom In/Out, sine for Pulse) is applied *before* the log interpolation for smooth start/stop.

**Rule:** Always interpolate zoom scale in log space. Linear scale interpolation produces jerky animations at high zoom ratios because equal additive increments don't correspond to equal visual zoom.

---

## 2026-03-08: CGImageSourceCreateImageAtIndex empty dictionary → CFNull

**Problem:** The console was flooded with `IIOLogTypeMismatch: expected 'CFDictionaryRef' -- got 'CFNull'` errors every time the gallery refreshed (one pair per GIF).

**Root cause:** Passing `[:] as CFDictionary` as the options parameter to `CGImageSourceCreateImageAtIndex` was bridged to `CFNull` on some iOS versions, triggering the error. The function expects either a valid populated `CFDictionary` or `nil`.

**Fix:** Changed all four call sites (`AnimatedGifView`, `GifGridItem`, `GalleryCarouselView`, `EditorViewModel`) to pass `nil` instead of `[:] as CFDictionary`.

**Rule:** When calling Core Graphics / ImageIO C functions from Swift, pass `nil` for optional dictionary parameters when no options are needed. An empty Swift dictionary `[:]` does not bridge cleanly to `CFDictionary` and can produce `CFNull`.

---

## 2026-03-08: scaleEffect expands gesture hit-test area beyond canvas

**Problem:** When the user zoomed into the photo in the editor, the X close button became untappable. The zoomed image's gesture area extended beyond the canvas frame and intercepted touches meant for the topBar.

**Root cause:** `.scaleEffect(scale)` was applied to the Image, and `.gesture(dragGesture)` / `.gesture(magnificationGesture)` were attached directly to the scaled Image. Although `.clipped()` clips visual rendering, the gesture recognizers' hit-test area still extended to the scaled dimensions. In a VStack, the canvas's gesture area leaked into the topBar above it.

**Fix:** Restructured `ImageCanvasView`:
1. Removed the unnecessary `GeometryReader` wrapper (the `_` parameter was unused).
2. Moved gestures from the Image to the outer `ZStack` container.
3. Applied `.clipShape(RoundedRectangle(...))` and `.contentShape(Rectangle())` to the ZStack, constraining both visual and interactive bounds to `canvasSize × canvasSize`.
4. Added `.allowsHitTesting(false)` to `ZoomFrameOverlay` so it doesn't interfere with gestures.

**Rule:** Never attach gestures directly to a view that has `.scaleEffect`. Move gestures to a fixed-frame parent and clip that parent with `.clipShape` + `.contentShape(Rectangle())` to contain the interactive area.

---

## 2026-03-08: PBXFileSystemSynchronizedRootGroup — no project file edits needed for file moves

**Problem:** After moving 7 Swift files from feature folders to `Components/`, we needed to update the Xcode project file.

**Discovery:** The project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), the newer Xcode format where Xcode automatically syncs its file tree with the file system. There are no individual `PBXFileReference` entries per source file — Xcode watches the root group folder and picks up whatever is on disk.

**Rule:** For projects using `PBXFileSystemSynchronizedRootGroup`, file moves/renames on disk are sufficient. No `.pbxproj` edits are needed. Just rebuild.

---

## 2026-03-08: Component vs. Feature folder organization

**Problem:** Reusable UI views were scattered across feature folders, making them hard to find and creating implicit coupling.

**Decision:** Established a clear rule:
- **Components/** — Views used (or potentially used) by multiple features. Self-contained, parameterized via bindings/closures. Currently 13 files.
- **Features/\<Name\>/** — Screen-level views and their view models. Only files tightly coupled to that screen's specific layout and logic.

Files moved to Components: `GIFPreviewView`, `ShareSheet`, `ImageCanvasView`, `ZoomFrameOverlay`, `AnimatorPickerView`, `PreviewControlsView`, `GifGridItem`.

**Rule:** If a view accepts generic inputs (bindings, closures, model data) and could be embedded in any screen, it belongs in Components. If it references a specific ViewModel or orchestrates a specific screen's layout, it stays in its feature folder.

---

## 2026-03-08: Existing GIF re-edit via first-frame extraction

**Problem:** Users wanted to change the effect on a previously saved GIF, but the app only had the final GIF file — no original source image.

**Solution:** When opening an existing GIF in the editor:
1. Extract the first frame using `CGImageSourceCreateImageAtIndex(source, 0, ...)` and store it as `sourceImage` on `EditorViewModel`.
2. Show the GIF playing in the preview, with effect/speed controls enabled.
3. Track modifications via `hasModifiedSettings` — SAVE button stays disabled until the user changes something.
4. On save, present an action sheet: "UPDATE ORIGINAL GIF" (deletes old PHAsset, saves new) or "SAVE NEW COPY" (saves alongside).
5. `DetailContent.existingGif` now carries a third associated value: the `PHAsset.localIdentifier`, enabling targeted deletion for the update flow.

**Rule:** When re-editing generated content, extract a stable source representation (first frame, original parameters) rather than trying to reverse-engineer the final output. Track the asset identifier from the start so updates can target the correct library asset.

---

## 2026-03-08: Photo thumbnail performance — size and caching matter

**Problem:** Photo picker grid loaded slowly. Timing showed ~1567ms for 29 photos, with each thumbnail requested at 1035×1035 pixels (345pt × 3x scale) — far larger than the ~114pt grid cells.

**Fix:**
1. Reduced `thumbnailSize` from `345 * scale` to `130 * scale` (~390px). Images returned at 390×520 instead of 1036×1380.
2. Switched from `PHImageManager.default()` to `PHCachingImageManager` for better thumbnail caching.
3. Added progressive loading — UI updates every 12 images instead of waiting for all 50.
4. Result: load time dropped from ~1567ms to ~779ms (50% improvement).

**Rule:** Always match `targetSize` to the actual display size (cell width × screen scale). Use `PHCachingImageManager` for grid/collection views. Progressive batching prevents the "all or nothing" loading UX.

---

## 2026-03-08: iOS Simulator cannot download iCloud-only photos

**Problem:** Album-specific photo fetches returned 0 or very few photos on the simulator, with `CloudPhotoLibraryErrorDomain Code=1006 "User rejected a prompt to enter their iCloud account password"` errors — even when signed into iCloud.

**Cause:** `CKInternalErrorDomain Code=2011` — the simulator's Keychain/CloudKit auth doesn't properly handle photo download tokens. Photos in the "All" view worked because they were locally cached; album photos were iCloud-only and required a download.

**Rule:** Always test iCloud Photo Library features on a physical device. The simulator cannot reliably download iCloud-only photos even when signed in. Use TestFlight for comprehensive photo library testing.

---

## 2026-03-08: ShareSheet — explicit UTType for broader share targets

**Problem:** iMessage didn't appear in the share sheet when sharing GIFs.

**Fix:** Replaced plain `URL` activity items with a `UIActivityItemSource` (`GIFActivityItem`) that declares `UTType.gif.identifier` via `dataTypeIdentifierForActivityType`. This tells the system the exact content type so all compatible apps appear.

**Rule:** When sharing files via `UIActivityViewController`, implement `UIActivityItemSource` with explicit `dataTypeIdentifierForActivityType` rather than passing raw URLs. This ensures all compatible share targets (Messages, Mail, etc.) recognize the content type.

---

## 2026-03-08: Album sheet — native presentationDetents vs custom overlays

**Problem:** Custom full-screen overlay for album/sort picker couldn't be dismissed easily and didn't support half-height presentation.

**Fix:** Replaced the custom `ZStack` overlay with a native `.sheet` using `.presentationDetents([.medium, .large])`. The header stays outside the `ScrollView` so it pins at the top. The sheet starts at half-height and expands as the user scrolls.

**Rule:** Prefer SwiftUI's native `.sheet` with `presentationDetents` over custom overlay implementations when you need half-height sheets, drag-to-dismiss, or expandable content. It handles all the edge cases (gesture priority, safe areas, animation) automatically.

---

## 2026-03-08: Photo pagination with PHFetchResult caching

**Problem:** Removing the fetch limit to show all album photos caused the app to attempt loading 36,000+ photos synchronously, freezing the UI.

**Fix:** Implemented proper pagination:
1. Cache the `PHFetchResult` and maintain a `fetchResultOffset` to track position.
2. Load 100 photos on initial fetch, then 50 per "LOAD MORE" tap.
3. Filter out GIF album assets during iteration (skip by `localIdentifier`).
4. Progressive UI updates every 12 photos within each batch.
5. `hasMorePhotos` is derived from `fetchResultOffset < fetchResult.count`.

**Rule:** Never enumerate an entire `PHFetchResult` into memory. Cache the result, paginate with an offset, and load thumbnails in small batches with progressive UI updates.

---

## 2026-03-08: Auto-continue for iCloud-sparse photo batches

**Problem:** In albums where most photos are iCloud-only (no local thumbnail), a batch of 50 assets could yield 0 displayable photos. The user had to tap "LOAD MORE" repeatedly, getting nothing each time.

**Fix:** After each batch completes, if fewer than 10 new photos were added and more assets remain, automatically load the next batch. A cap of 5 consecutive empty batches prevents runaway scanning. The counter resets on each manual "LOAD MORE" tap.

**Why 5:** Balances between finding scattered local photos and not burning CPU on albums that are entirely iCloud-only. On a real device (where iCloud downloads succeed), the auto-continue rarely triggers because each batch yields a full 50 photos.

**Rule:** When paginating through a data source where items may be unavailable (iCloud, network), auto-continue past empty batches but cap the attempt count. Reset the cap on explicit user action.

---

## 2026-03-08: Combine assign(to:) vs sink for @Published forwarding

**Problem:** `PhotoManager` used `assign(to: &$hasMorePhotos)` to forward values from `PhotoLibraryService.$hasMorePhotos`. The UI did not update when `hasMorePhotos` changed — the "LOAD MORE" button never appeared.

**Root cause:** `assign(to:)` on a `@Published` property writes directly to the backing storage, bypassing the `objectWillChange` publisher. SwiftUI views observing the `PhotoManager` never received change notifications for the forwarded properties.

**Fix:** Replaced `assign(to:)` with explicit `sink` subscriptions that assign the value manually: `photoLibrary.$hasMorePhotos.sink { [weak self] value in self?.hasMorePhotos = value }`. The property setter on `@Published` triggers `objectWillChange`, causing view updates.

**Rule:** When forwarding `@Published` values between `ObservableObject`s, use `sink` with explicit assignment instead of `assign(to:)`. The `assign(to:)` operator bypasses the `objectWillChange` publisher, silently breaking SwiftUI reactivity.

---

## 2026-03-08: LazyVGrid siblings in ScrollView layout issues

**Problem:** The "LOAD MORE" button placed as a sibling view after a `LazyVGrid` inside a `ScrollView` was rendered in the view hierarchy (confirmed via `onAppear`) but was not visible or scrollable to.

**Root cause:** `LazyVGrid` inside a `ScrollView` can cause subsequent sibling views to be laid out incorrectly — the lazy grid doesn't report its full height to the scroll view's layout engine until all items are materialized.

**Fix:** Wrapped the `LazyVGrid`, the "LOAD MORE" button, and bottom padding inside a `VStack(spacing: 0)` within the `ScrollView`. The `VStack` acts as a concrete container that forces proper sequential layout.

**Rule:** When placing views after a `LazyVGrid` in a `ScrollView`, wrap everything in a `VStack`. Don't rely on `LazyVGrid` siblings being laid out correctly as direct children of the `ScrollView`.

---

## 2026-03-08: Prefer shared components over one-off implementations

**Problem:** The effects sheet, save sheet, and album picker sheet each had their own inline implementations of the same UI pattern — dark scrim, header with title and close button, slide-up content. This led to inconsistent animations, duplicated styling code, and extra work every time a new sheet was needed.

**Fix:** Created a reusable `BottomSheet` component in `Components/` that encapsulates the shared header, presentation detents, drag indicator, and background. All three sheets now use this component, giving them identical behavior with zero duplication. The component accepts an `expandable` flag so fixed-content sheets (save, effects) stay at half-screen while scrollable sheets (album picker) can grow.

**Rule:** Before building any UI element, ask: "Will we need this pattern again?" If yes — or even maybe — extract it into a shared component in `Components/` from the start. It's cheaper to generalize early than to refactor three copies later. Shared components also guarantee visual and behavioral consistency across the app.

---

## 2026-03-08: Composable effects via protocol layering

**Problem:** Adding new motion effects (Shake, Spiral) as standalone `Animator` implementations would have created a combinatorial explosion — every base effect × every motion style = a separate class (ZoomInShake, ZoomInSpiral, PulseShake, etc.).

**Fix:** Introduced a `MotionModifier` protocol that transforms `AnimationParameters` produced by a base `Animator`. A `CompositeAnimator` wraps any base + modifier pair and itself conforms to `Animator`, so `GIFGenerator` needs zero changes. The `StraightModifier` is a pass-through (no modification), `ShakeModifier` adds sine-wave jitter, and `SpiralModifier` adds circular displacement. Any base effect works with any modifier.

**Rule:** When extending a system with a second axis of variation (e.g., base effects × motion styles), use protocol composition rather than multiplying implementations. A wrapper struct that conforms to the original protocol keeps the consumer unchanged and scales to N × M combinations with only N + M implementations.

---

## 2026-03-08: CIImage chaining for efficient per-frame visual effects

**Problem:** Visual effects (film grain, vignette, chromatic aberration, light leak) need to be applied to every frame of a GIF (20+ frames). Naively converting CGImage → CIImage → applying filter → rendering back to CGImage for each effect on each frame would be expensive — potentially 4 render passes × 25 frames = 100 GPU round-trips.

**Fix:** Each `VisualEffect` conforms to a protocol that takes and returns `CIImage`. Since CIImage operations are lazy (they build a filter graph, not pixels), chaining 4 effects still produces a single filter graph per frame. `GIFGenerator` creates one shared `CIContext` and calls `createCGImage` exactly once per frame to render the entire chain. This means 25 GPU renders total regardless of how many effects are active.

**Rule:** When processing images through multiple Core Image filters, always chain `CIImage → CIImage` and render to `CGImage` only once at the end. Create `CIContext` once and reuse it — context creation is expensive. Never create a `CIContext` per frame or per effect.

---

## 2026-03-08: Progressive visual effects tied to animation progress

**Problem:** Applying visual effects at constant intensity across all frames felt jarring and disconnected from the zoom animation. Effects like film grain or chromatic aberration at full strength from frame 0 made the GIF look broken rather than intentional.

**Fix:** Each `VisualEffect` scales its intensity using the `progress` parameter (0.0 → 1.0) that's already passed through the protocol. Effects start invisible and build toward full strength as the zoom reaches its target. Using ease-in curves (`progress²` or `progress³`) keeps the first half of the animation mostly clean, with the effect kicking in dramatically in the second half — creating a visual crescendo that mirrors the zoom.

**Rule:** When adding per-frame effects to animations, tie the effect intensity to the animation's progress curve rather than applying it uniformly. Ease-in curves (`progress²` for moderate, `progress³` for aggressive) work well because they preserve the clean look early and deliver impact at the climax. Always include an early-out guard (e.g., `guard intensity > threshold else { return image }`) to skip GPU work on frames where the effect is imperceptible.

---

## 2026-03-08: Mutually exclusive vs. stackable effect selection

**Problem:** Initially visual effects were implemented as stackable (multiple active via `Set<VisualEffectType>`). In practice, combining effects like halftone + chromatic aberration produced unpredictable, unpleasant results because each CIFilter chain compounds in ways that are hard to preview or control.

**Fix:** Changed from `Set<VisualEffectType>` to `VisualEffectType?` (optional single selection). The UI toggles work like radio buttons — tapping an active effect deselects it, tapping a new one replaces the previous. This keeps the output predictable and the UI simple.

**Rule:** Default to mutually exclusive selection for creative effects unless there's a clear, tested reason to allow stacking. Stacking CIFilter chains creates emergent behavior that's difficult to predict or control. If stacking is needed later, it should be done through intentional, curated presets rather than free-form combination.

---

## 2026-03-08: Built-in CIFilter catalog for common visual effects

**Filters used in this project and their strengths:**

- `CIColorControls` — saturation, brightness, contrast adjustments. `kCIInputSaturationKey = 0.0` gives perfect grayscale.
- `CICMYKHalftone` — classic newspaper CMYK dot pattern. `kCIInputWidthKey` controls dot size (2–12px is a good range for 600px output). `kCIInputSharpnessKey` at 0.7 gives crisp dots.
- `CIBumpDistortion` — center bulge/pinch. Positive `kCIInputScaleKey` bulges outward (fisheye), negative pinches inward. Radius should be ~45% of the frame dimension for full coverage.
- `CIColorMatrix` — isolate individual RGB channels by zeroing unwanted rows. Combined with `CIAffineTransform` for channel offset and `CIAdditionCompositing` to recombine, this creates chromatic aberration.

**Rule:** Check Apple's CIFilter reference before writing custom pixel manipulation. Most common visual effects have efficient built-in implementations that are GPU-accelerated and handle edge cases (color spaces, alpha channels) correctly.

---

## 2026-03-07: Custom photo picker architecture (replaced with native PhotosPicker)

**What we built and why it was removed:**

We built a custom in-app photo picker (`PhotoGridView`) with album browsing, sort options, pagination, and thumbnail caching. It was removed in favor of SwiftUI's native `PhotosPicker` because the custom implementation had persistent bugs (iCloud-only assets failing silently, inconsistent batch loading, photos not appearing in albums) that consumed disproportionate development time.

**Architecture (for reference if rebuilding):**

- **PhotoGridView** (Features/Gallery/PhotoGridView.swift, ~316 lines): `LazyVGrid` of photo thumbnails with `matchedGeometryEffect` for hero transitions to the editor. Presented as an overlay from `GalleryView`. Used a callback `onPhotoSelected: (UIImage, Int) -> Void` to pass the selected image and grid index back to `GalleryView`.

- **PhotoLibraryService** (Services/PhotoLibraryService.swift, ~314 lines): `ObservableObject` wrapping the Photos framework. Key design decisions:
  - Cached the `PHFetchResult` from the initial query, then loaded thumbnails in batches via `loadNextBatch(count:append:)` to avoid loading all assets at once.
  - Used `PHCachingImageManager` with 390px thumbnails (down from 1035px) for 50% faster loading.
  - Progressive UI updates: published `@Published var photos: [UIImage]` which updated after each batch of 12 thumbnails loaded.
  - Album browsing via `fetchAlbums()` which queried `PHAssetCollection` for smart albums and user albums.
  - Sort options (`PhotoSortOrder` enum) toggling between `creationDate` and `modificationDate` sort descriptors.
  - Auto-continue for iCloud-sparse batches: when `isNetworkAccessAllowed = false`, many assets return nil. A `consecutiveEmptyBatches` counter capped auto-continue at 5 to prevent runaway loops.
  - Full-resolution fetch on selection: `fetchFullResolutionImage(for:)` requested 3000x3000 images for editor quality.

- **PhotoManager** (Services/PhotoManager.swift): Facade that forwarded `PhotoLibraryService` properties via `Combine` `sink` subscriptions. Initially used `assign(to: &$property)` which didn't trigger SwiftUI updates — switching to `sink` with explicit assignment fixed this.

- **Pagination**: "LOAD MORE" button at bottom of grid. Initial batch of 100, then 50 per tap. Button placed inside a `VStack` wrapping the `LazyVGrid` (not as a sibling of `LazyVGrid` directly in `ScrollView`, which caused layout bugs).

- **Album picker**: Floating filter button at bottom of `PhotoGridView` that presented a `.sheet` with `presentationDetents([.medium, .large])`. Sheet listed albums with photo counts; tapping an album called `fetchPhotos(from:sortOrder:)`.

- **Change observer**: `PHPhotoLibraryChangeObserver` on `PhotoManager` with 2-second debounce (only refreshed GIFs, not photos) to prevent infinite refresh cascades.

**Key bugs encountered:**
1. iCloud-only photos returned nil thumbnails on simulator even when signed in — no good workaround without `isNetworkAccessAllowed = true` (which blocks the thread).
2. `LazyVGrid` siblings in `ScrollView` have unreliable layout — always wrap in a `VStack`.
3. `Combine`'s `assign(to: &$property)` doesn't trigger `@Published` `objectWillChange` notifications — use `sink` with explicit assignment.
4. Album sort order: `modificationDate` ≠ "most recent" for users — `creationDate` is what people expect.
5. Batch loading with progressive UI caused the "LOAD MORE" button to flicker as `hasMorePhotos` toggled during batch processing.

**Rule:** Prefer native pickers (PhotosPicker, PHPickerViewController) unless you need deep customization of the selection UI. The Photos framework's thumbnail loading, iCloud handling, and album management are complex enough that the maintenance cost of a custom picker often exceeds the UX benefit. If rebuilding, start with `PHCachingImageManager` and batch loading from day one — retrofitting pagination onto a synchronous fetch is painful.

---

### Native PhotosPicker Swap (Phase 5a)

Replaced the entire custom photo picker (~280 lines of `PhotoGridView`, plus supporting code in `PhotoLibraryService` and `PhotoManager`) with SwiftUI's native `PhotosPicker` view.

**What changed:**
- `GalleryView` buttons now use `PhotosPicker(selection:matching:)` instead of presenting a custom overlay.
- `PhotoLibraryService` stripped to a single static `fetchAlbumCollection(named:)` helper (used only by `GIFLibraryService`).
- `PhotoManager` stripped of all photo-forwarding properties (`photos`, `photoAssets`, `albums`, `hasMorePhotos`, `isLoadingMore`), `Combine` subscriptions, and photo-fetching methods.
- `DetailContent.newImage` no longer carries an index (was only used for `matchedGeometryEffect` hero transition from the custom grid).
- `ImageCanvasView` no longer accepts `namespace` or `photoIndex` — the hero animation between grid cell and editor canvas was removed since the native picker handles its own presentation/dismissal.

**Image loading approach:** `PhotosPickerItem.loadTransferable(type: Data.self)` returns full-resolution image data. The `UIImage(data:)` initializer handles all formats. A loading overlay (`ProgressView`) covers the screen while the async transfer completes.

**Lines of code removed:** ~550 (PhotoGridView + stripped service/manager code).

**Tradeoff:** We lose custom album browsing, sort order controls, and the pagination UI — but these caused more bugs than they solved (iCloud failures, layout flickering, sort confusion). The native picker handles all of this with zero maintenance.

---

### GIF Gallery Race Conditions & Cache Stability (Phase 5b)

**Problem:** GIFs intermittently disappeared from the gallery on launch, and sometimes failed to animate.

**Root causes identified:**
1. **Concurrent fetches:** `fetchMyGifs()` and `forceRefreshGifs()` were separate methods that could run simultaneously (launch + `photoLibraryDidChange` observer + post-save callback). Overlapping `DispatchGroup` callbacks produced inconsistent array states.
2. **Unstable cache URLs:** `getGifURL` generated new UUID-based filenames on every refresh (`\(index)-\(UUID().uuidString).gif`). This invalidated both `GIFCache` (keyed by URL for animation frames) and `ThumbnailCache` (keyed by URL for static thumbnails), causing momentary blank views during re-decode.
3. **PHImageManager double-callback:** With `deliveryMode: .highQualityFormat` and `isSynchronous: false`, the handler can still fire once with a degraded image before the final. Not checking `PHImageResultIsDegradedKey` could cause `group.leave()` to fire prematurely.
4. **Temp file leak:** UUID-named files accumulated in `Caches/MyGIFs/` without cleanup.

**Fixes:**
- Consolidated into a single `fetchMyGifs()` with 0.15s coalescing (`DispatchWorkItem` cancel + re-schedule) and an `isFetching` gate.
- Stable filenames based on sanitized `asset.localIdentifier` — if the file already exists, skip the copy. This preserves cache validity across refreshes.
- Check `PHImageResultIsDegradedKey` in the `requestImage` callback; only count the final high-quality delivery.
- `cleanupStaleCacheFiles()` runs after each refresh, removing files not in the current URL set.

**Rule:** When caching files keyed by URL, ensure the URL is deterministic and stable across refreshes. UUID-based temp filenames break any downstream cache that uses the URL as a key. Use the source identifier (asset ID, hash) as the filename instead.

---

### CGImageSourceCreateThumbnailAtIndex vs CGImageSourceCreateImageAtIndex

For generating thumbnails from GIF data, prefer `CGImageSourceCreateThumbnailAtIndex` over `CGImageSourceCreateImageAtIndex` + manual resize. Benefits:
- Decodes directly at the target size (less memory, faster)
- Eliminates the `UIGraphicsImageRenderer` resize step
- Uses proper options dictionary (`kCGImageSourceThumbnailMaxPixelSize`, `kCGImageSourceCreateThumbnailFromImageAlways`, etc.)

`CGImageSourceCreateImageAtIndex` should only be used when you need the full-resolution image (e.g., extracting a source frame for GIF re-generation in the editor).

**Note:** `PHImageManager.requestImage` internally calls `CGImageSourceCreateImageAtIndex` when loading GIF thumbnails from the Photos library and passes invalid options, producing `CFNull` errors in the console. These are Apple framework bugs — non-fatal, cannot be fixed from app code.

---

## 2026-03-09: Multi-select delete mode vs context menus

**Problem:** Needed a way to delete GIFs from the gallery. Initially planned per-item context menus (long-press → "DELETE GIF"), but the Figma design called for a multi-select batch delete mode.

**Design pattern:** Long-press enters a selection mode that changes the gallery's behavior:
- Header updates to show selection count
- Taps toggle selection instead of navigating
- Bottom bar swaps to a destructive action button
- X button exits the mode

**Implementation:** Added `isSelectMode: Bool` and `selectedIndices: Set<Int>` to `GalleryView`. `GifGridItem` gained `isSelected: Bool` (drives a red border overlay) and `onLongPress` closure. The `onTap` closure is conditionally routed — in select mode it toggles selection, otherwise it navigates to the editor.

**Batch deletion:** `GIFLibraryService.deleteAssets(identifiers:)` fetches all PHAssets in one `fetchAssets(withLocalIdentifiers:)` call and deletes them in a single `performChanges` block. This is more efficient than N individual delete calls and presents the user with only one system permission prompt.

**Rule:** When implementing destructive batch operations, collect all identifiers first and execute in a single Photos framework `performChanges` block. This reduces permission prompts from N to 1 and is transactionally safer.

---

## 2026-03-09: Testing strategy — protocol injection for ViewModels

**Problem:** `EditorViewModel` creates `GIFGenerator()` inline in `generateGIF()` and `regenerateGIF()`. This makes unit testing impossible — every test that touches GIF generation must wait for real image rendering (slow, flaky, dependent on `UIGraphicsBeginImageContext` availability in test bundles).

**Fix:** Extracted a `GIFGenerating` protocol with `generateGIF(from:currentScale:visibleRect:animator:speed:visualEffects:) -> Data?` and `saveTempGIF(_:) -> URL?`. `GIFGenerator` conforms to it. `EditorViewModel` now accepts `gifGenerator: GIFGenerating` in its initializer with a default of `GIFGenerator()`, so production code is unchanged but tests can inject a `StubGIFGenerator` that returns canned data instantly.

**Rule:** When a ViewModel creates heavy service objects inline, inject them via an initializer parameter with a production default. This keeps the call sites unchanged while enabling fast, deterministic tests. Use a lightweight protocol — only the methods the ViewModel actually calls need to be on it.

---

## 2026-03-09: Swift Testing framework (@Test) vs XCTest

**Context:** The project was created with Swift Testing (`import Testing`, `@Test func`) for unit tests and XCTest (`import XCTest`, `XCTestCase`) for UI tests.

**Key differences:**
- Swift Testing uses `#expect(condition)` instead of `XCTAssertTrue`. Failures report the full expression, not just "assertion failed".
- Test functions use `@Test` attribute — no `test` prefix naming convention required.
- Tests are structs (value types), not classes. Each test gets a fresh instance automatically.
- UI tests still require `XCTest` because `XCUIApplication` and `XCUIElement` are XCTest APIs with no Swift Testing equivalent yet.

**Rule:** Use Swift Testing (`@Test`, `#expect`) for unit tests — it's more expressive and lighter weight. Use XCTest only for UI tests that need `XCUIApplication`. Don't mix frameworks within a single test file.

---

## 2026-03-09: Visual effect intensity — calibrating to a midpoint

**Problem:** Adding an intensity slider to visual effects required deciding how parameter values map to the slider range. A naive linear mapping (`minValue + intensity * range`) doesn't give users a natural feel if the "good default" doesn't land at the midpoint.

**Fix:** Calibrated each effect so that `intensity = 0.5` (medium, the default) reproduces the original hand-tuned values:
- ChromaticAberration: `maxShift = max(2.0, 20.0 * intensity)` → 10px at medium, 20px at max
- Halftone: `maxWidth = max(4.0, 24.0 * intensity)` → 12pt at medium, 24pt at max
- Fisheye: `maxScale = max(0.1, 1.4 * intensity)` → 0.7 at medium, 1.4 at max
- FadeToBW: `strength = intensity * 2.0` → full desaturation at medium, reaches B&W at 50% progress at max

**Rule:** When adding intensity controls to creative parameters, calibrate so the midpoint matches the previously tuned "good default." Use `parameter = oldValue * (intensity / 0.5)` as a starting formula, then adjust per-effect.

---

## 2026-03-09: Bake timing into GIF frames, don't scale at playback

**Problem:** The configurable pause duration was affected by the speed setting — a 4-second pause played in 2 seconds at 2x speed.

**Root cause:** `AnimatedGifView` divided the entire `animationDuration` (including pause frames) by `playbackSpeed`. Speed was being applied twice: once during GIF generation (correct frame delays baked into the file) and again during playback (incorrectly scaling everything).

**Fix:** Removed the `/ playbackSpeed` divisor from `AnimatedGifView`. The GIF generator already encodes correct per-frame timing — animation frames get shorter delays at higher speeds, while pause frames maintain their configured duration regardless of speed. The viewer now plays the GIF at its native frame rate.

**Rule:** When GIF frame timing is dynamically computed (variable speed, configurable pause), bake all timing into the file's per-frame delay values. Don't apply playback speed scaling in the viewer — it creates coupling between speed and other timing parameters (like pause) that should be independent.

---

## 2026-03-09: UIViewRepresentable struct captures stale values in async closures

**Problem:** GIFs in the carousel view never started animating, even though the frames loaded successfully.

**Root cause:** `AnimatedGifView` (a struct conforming to `UIViewRepresentable`) called `loadGIF` from `makeUIView`. The `loadGIF` completion closure captured `self.isVisible`, but since structs are value types, the captured value was the one at `makeUIView` time (`false`). By the time the async completion ran, `isVisible` had been updated to `true` via `onAppear` → parent re-render, but the closure still held the stale `false`. The `updateUIView` method that ran with the new `isVisible = true` found `animationImages == nil` (not loaded yet from the async dispatch), so it couldn't start animating either.

**Fix:** Always start animating when images finish loading, regardless of the captured `isVisible`. The `updateUIView` method will stop the animation on its next call if `isVisible` is actually `false`. For the cached path, removed the `DispatchQueue.main.async` wrapper entirely — since `loadGIF` is called from `makeUIView` (already on main thread), setting images synchronously ensures they're available when `updateUIView` runs.

**Rule:** In `UIViewRepresentable` structs, never rely on captured `self.property` values in async closures — they're stale snapshots. Either use the Coordinator (a reference type) to track mutable state, or perform the action unconditionally and let `updateUIView` correct it on the next pass.

---

## 2026-03-09: Pinch-to-reflow grid — simultaneousGesture + LazyVGrid

**Problem:** A `MagnificationGesture` attached to a parent view containing a `ScrollView` never received events — the scroll view consumed the gesture first.

**Fix:** Changed `.gesture()` to `.simultaneousGesture()` so the pinch recognizer fires alongside the scroll gesture. The pinch drives a `gridScale` state variable that maps to column count via a computed property:
- `gridScale < 1.3` → 3 columns
- `gridScale < 2.0` → 2 columns
- `gridScale >= 2.0` → 1 column

On gesture end, `gridScale` snaps to the nearest column stop (1.0, 1.5, or 2.0) with a spring animation. The `lastGridScale` anchor pattern (same as the editor's pinch-to-zoom) ensures consecutive gestures accumulate correctly.

**Key insight:** `LazyVGrid` column changes are discrete, not interpolated. The grid reflows instantly at the threshold — there's no smooth morphing between column counts. The spring animation on the `gridColumnCount` value change provides a visual transition via SwiftUI's layout animation system.

**Rule:** When combining `MagnificationGesture` with `ScrollView`, always use `.simultaneousGesture()`. Use a `lastScale` anchor pattern for cumulative pinch tracking across multiple gestures. Snap to discrete stops on gesture end for a polished feel.

---

## 2026-03-10: Viewport-centered visual effect preview

**Problem (iteration 1):** Applying the visual effect once to the full source image and letting SwiftUI handle pan/zoom was performant but the effect center (e.g., fisheye bulge) stuck to the image center. Panning the photo moved the bulge away from the viewport center — users expected the effect to track where they're looking.

**Problem (iteration 2):** An earlier approach tried cropping the source image to the visible viewport, applying the effect, then scaling back up. This was computationally expensive (~150ms per update) and caused noticeable jank during pan/zoom gestures.

**Fix:** Extended the `VisualEffect` protocol with an optional `viewportCenter: CGPoint?` parameter:
```swift
func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage
```
A default extension routes to the base method (ignoring the center) so non-spatial effects (B&W, Chromatic Aberration) are unaffected. Spatially-centered effects (`FisheyeEffect`, `HalftoneEffect`) override this to use the viewport center instead of the image center when provided.

`EditorViewModel.updatePreviewImage()` computes the viewport center in image coordinates from `visibleRect`:
```swift
let vpCenterX = (rect.midX) * imageWidth
let vpCenterY = (1.0 - rect.midY) * imageHeight  // CIImage Y-axis is flipped
```

A 30ms debounce via `DispatchWorkItem` coalesces rapid gesture updates. The GPU-accelerated `CIContext` processes the full image in ~15-25ms, so the effect tracks the viewport center with minimal perceptible lag.

**Why this works:** The effect is re-rendered at full image resolution with the correct center on each debounced update. SwiftUI's `scaleEffect` and `offset` handle smooth motion between renders. During fast continuous pans, the effect center drifts slightly (it's baked into the image from the last render), then snaps to the correct position when the debounce fires. This drift is typically imperceptible at 30ms intervals.

**Tradeoff:** The preview centers the effect on the viewport, but the final GIF generation still centers effects on the image center (passes `nil` for `viewportCenter`). This is intentional — the GIF animates across the full image, so a fixed viewport-relative center wouldn't make sense in the animated output.

**Alternative considered:** Metal shaders via SwiftUI's `.distortionEffect()` (iOS 17+) would apply the effect to rendered pixels post-transform, giving true zero-latency viewport-fixed distortion. This would be the right solution if the debounced approach proves too laggy on older devices.

**Rule:** When visual effects need to track a viewport position rather than image coordinates, extend the effect protocol with an optional center parameter and a default implementation that ignores it. This keeps the GIF pipeline unchanged while allowing the preview to pass viewport-relative coordinates. Use debounced re-rendering rather than per-frame processing — the GPU handles full-image CIFilter passes fast enough that a 30ms debounce feels responsive.

---

## 2026-03-10: CIImage coordinate system — Y-axis is flipped

**Problem:** The fisheye bulge appeared mirrored vertically from the expected position when passing viewport coordinates to the CIFilter.

**Root cause:** CIImage uses a bottom-left origin coordinate system (Y increases upward), while SwiftUI/UIKit use top-left origin (Y increases downward). The `visibleRect` from SwiftUI reports Y in top-left coordinates, so passing `rect.midY * imageHeight` directly to `CIVector` placed the effect center at the wrong vertical position.

**Fix:** Flip the Y coordinate when converting from SwiftUI space to CIImage space:
```swift
let vpCenterY = (1.0 - (rect.origin.y + rect.height / 2)) * imageHeight
```

**Rule:** Always flip the Y axis when converting between SwiftUI/UIKit coordinates and CIImage coordinates. `CIImage.extent` origin is bottom-left; SwiftUI layout origin is top-left.

---

## 2026-03-10: Downscaled preview source for CIFilter performance

**Problem:** The live visual effect preview processed the full source image (4032x3024 pixels) through CIFilter on every update. Even with GPU-accelerated `CIContext`, each render took ~15-25ms. During rapid pan/zoom gestures, this created perceptible lag between the gesture and the effect updating.

**Fix:** Created a 650x650 downscaled copy of the source image (matching the canvas at 325pt x 2x retina) using `CGImageSourceCreateThumbnailAtIndex`. This cached copy is created lazily on the first `updatePreviewImage()` call and reused for all subsequent renders. The CIFilter now processes ~14x fewer pixels, bringing render time down to ~2-3ms.

**Key implementation detail:** The downscaled image is created from JPEG data via `CGImageSourceCreateThumbnailAtIndex` (same efficient path used for gallery thumbnails), not by rendering through `UIGraphicsImageRenderer`. This avoids a full decode-then-draw cycle and lets ImageIO handle the downsampling at the codec level.

**Cleanup:** The cached `previewSourceCGImage` is cleared on `resetEffects()` or when the source image changes, so a stale preview source is never reused across different images.

**Rule:** When applying CIFilter effects for preview purposes, downscale the source to match the display resolution. A 325pt canvas at 2x retina only needs a 650x650 source — processing a 4032x3024 image wastes ~93% of the GPU work on pixels that are never displayed. Use `CGImageSourceCreateThumbnailAtIndex` for the most efficient downsampling path.

---

## 2026-03-10: Separating warp intensity from effect radius (CIBumpDistortion)

**Problem:** The fisheye effect had a single `intensity` control that scaled the `kCIInputScaleKey` (warp strength). The `kCIInputRadiusKey` (size of the distorted area) was hardcoded to 45% of the image dimension. Users couldn't create a tight, localized fisheye lens vs. a wide-angle distortion.

**Fix:** Added a second `size` parameter to `FisheyeEffect` that maps to `radiusFraction`:
- `size = 0.0` → radius = 10% of image (tight spot, like a magnifying glass)
- `size = 0.5` → radius = 30% of image (moderate area, the default)
- `size = 1.0` → radius = 50% of image (nearly full image, wide-angle)

The `VisualEffectType.effect(intensity:size:)` factory passes `size` only to `FisheyeEffect`; other effects ignore it via the default parameter. The editor shows a SIZE slider beneath the INTENSITY slider, but only when fisheye is selected.

**Rule:** When a CIFilter has multiple orthogonal parameters (strength vs. area, frequency vs. amplitude), expose them as separate controls rather than coupling them in a single slider. Users think about "how strong" and "how big" independently. Use the `VisualEffectType` factory's default parameters to keep the API clean for effects that don't use all parameters.

---

## 2026-03-11: Expanding visual effects with mixed CIFilter and manual compositing

**Problem:** Adding 5 new visual effects (swirl, glitch, scanlines, pixelate, ripple) required different implementation strategies depending on whether Core Image has a built-in filter.

**Approach by effect type:**
- **CIFilter-backed (GPU-efficient):** Swirl uses `CITwirlDistortion` (center, radius, angle params). Pixelate uses `CIPixellate` (center, scale). Both support viewport-centered preview via the existing `viewportCenter` protocol parameter.
- **Generator + compositing:** Scanlines uses `CIStripesGenerator` to create horizontal stripes, then composites them over the image with `CIColorMatrix` for a subtle green CRT tint. The generator produces an infinite-extent pattern that must be `.cropped(to:)` to the image extent.
- **Manual strip compositing:** Glitch and Ripple don't have CIFilter equivalents. They crop the image into horizontal strips, apply per-strip transforms (random displacement for glitch, sine-wave displacement for ripple), then composite strips back together. This is heavier than a single CIFilter call but still performant because the downscaled preview (650x650) keeps pixel counts low.

**Deterministic randomness for GIF consistency:** GlitchEffect uses a simple xorshift PRNG seeded by `frameIndex * 137 + bandIndex * 31` so the same frame always produces identical displacement. This ensures GIF playback is consistent — the glitch pattern doesn't change between preview and final render.

**Rule:** Prefer built-in CIFilters when available (swirl, pixelate) for GPU efficiency. When no filter exists, strip-based compositing (crop → transform → composite over) is the cleanest approach for row/band effects. Always seed randomness from `frameIndex` for GIF reproducibility. Keep strip counts reasonable (12–40) to balance visual quality with compositing overhead.

---

## 2026-03-11: Inverting effect progress for "reveal" aesthetics

**Problem:** The pixelate effect started sharp and became blocky as the animation progressed. This felt like degradation rather than enhancement. The more natural creative direction is to start pixelated and resolve to sharp — a "reveal" that pairs with the zoom animation reaching its destination.

**Fix:** Replaced `progress` with `1.0 - progress` in the scale calculation: `let remaining = 1.0 - progress`. The quadratic easing curve `remaining * remaining` now means the image de-pixelates quickly at the end for a satisfying snap to clarity.

**Rule:** When an effect feels like it's "breaking" the image rather than enhancing it, try inverting the progress direction. Effects that resolve (pixelate → sharp, blur → clear) often pair better with zoom animations than effects that accumulate (sharp → pixelated), because the animation's endpoint should feel like a reward, not corruption.

---

## 2026-03-11: Horizontal slider layout for multi-parameter effects

**Problem:** When fisheye was selected, the INTENSITY and SIZE sliders stacked vertically, consuming 128pt of vertical space (two 60pt sliders + 8pt spacing). On smaller devices this pushed the action buttons uncomfortably close to the bottom edge.

**Fix:** Wrapped both sliders in an `HStack(spacing: 8)` when `supportsSizeControl` is true. Each slider's `GeometryReader` naturally takes half the available width. For effects without size control, the intensity slider remains full-width. The conditional layout is driven by `VisualEffectType.supportsSizeControl` so adding future multi-parameter effects automatically gets the horizontal layout.

**Rule:** When an effect has two slider controls, lay them out horizontally to preserve vertical space. The `GeometryReader` inside each slider already handles proportional fill width, so halving the container width works without any internal changes. Use a semantic property (`supportsSizeControl`) on the effect type enum rather than checking specific cases — this keeps the view code extensible.

---

## 2026-03-11: Face-aware effects with Vision framework landmarks

**Problem:** Adding "face filters" (bushy eyebrows, googly eyes, bobble head, handsome) requires knowing where facial features are in the image. The existing `VisualEffect` protocol operates on the whole image without any spatial awareness of face geometry.

**Approach:** Created a separate `FaceEffect` protocol that takes a `DetectedFace` parameter alongside the image. `FaceDetectionService` uses `VNDetectFaceLandmarksRequest` to detect faces once per source image and caches results. The `DetectedFace` struct pre-computes all landmark positions in image coordinates (CIImage's bottom-left origin) so effects don't need to do coordinate conversion.

**Key coordinate insight:** Vision's `VNFaceObservation.boundingBox` and `VNFaceLandmarkRegion2D.normalizedPoints` are both in normalized coordinates (0-1) with bottom-left origin. CIImage also uses bottom-left origin. So conversion is straightforward: `imageX = (bb.originX + point.x * bb.width) * imageWidth`. No Y-flip needed between Vision and CIImage (unlike Vision → SwiftUI, which needs a Y-flip for the face overlay).

**Scaling for preview:** The downscaled preview (650x650) means face coordinates from the full image must be scaled proportionally. The `EditorViewModel.scaleFace()` method computes `scaleX = previewWidth / fullWidth` and applies it to all landmark points. The same scaling logic exists in `GIFGenerator.applyFaceEffect()` for the GIF output resolution.

**Rule:** When adding spatial effects that target specific image regions, create a dedicated protocol rather than overloading the existing one. Cache detection results aggressively — Vision face detection is ~50-100ms and shouldn't run on every preview update. Pre-compute coordinates in the detection service rather than converting in each effect.

---

## 2026-03-11: Procedural googly eyes with CIRadialGradient

**Problem:** Googly eyes need to be composited at detected pupil positions with an animated wobble effect. External asset images would need to match the eye size precisely and wouldn't animate.

**Fix:** Generated eyes procedurally using `CIRadialGradient` — a white circle for the sclera and a smaller dark circle for the pupil. The pupil position within the white circle is offset using a xorshift PRNG seeded by `frameIndex`, creating deterministic wobble that's consistent across GIF regenerations. The eye size is derived from `leftEyeWidth * sizeMultiplier`.

**Rule:** For simple geometric overlays (circles, shapes), generate them procedurally with CIFilter generators rather than bundling asset images. This keeps sizes dynamic, avoids resolution mismatches, and allows per-frame animation via the frameIndex seed.

---

## 2026-03-12: FaceVisualEffect adapter — configurable delay and progress curves

**Problem:** The `FaceVisualEffect` adapter (which wraps any `VisualEffect` into a `FaceEffect`) hardcoded a delay (`progress > 0.3`) and quadratic ramp. This was wrong for effects like Pixelate (which needs to start immediately and use its own internal curve) and caused blank previews since the preview calls with `progress=1.0`.

**Fix:** Added two parameters to `FaceVisualEffect`:
- `skipDelay: Bool` — starts the effect from progress=0 instead of waiting until 0.3.
- `passRawProgress: Bool` — sends progress directly to the underlying effect without applying a quadratic ramp (for effects like Pixelate that have their own easing).

Also added `previewProgress` to `FaceFilterType` — most effects preview at 1.0 (full strength), but pixelate uses 0.2 because its "full strength" pixelation happens at low progress (it resolves to clear at 1.0). The preview also uses `frameIndex: 5` instead of 0 for better pseudo-random variety.

**Rule:** When wrapping effects with an adapter, make timing parameters configurable rather than hardcoded. Effects have different relationships between progress and intensity — some ramp up (fisheye), some ramp down (pixelate), some need to start immediately (shake). The adapter shouldn't impose a single timing model on all effects.

---

## 2026-03-12: SVG icons in Xcode asset catalog as template images

**Problem:** Needed custom pixel-art SVG icons for the editor's tab bar that could change color based on active/inactive state.

**Fix:** Added SVGs to `Assets.xcassets` as `.imageset` entries with `"template-rendering-intent": "template"` in the Contents.json. This tells iOS to treat the SVG fill color as a mask, allowing SwiftUI's `.foregroundColor()` to tint the icon dynamically.

**Contents.json structure:**
```json
{
  "images": [{ "filename": "icon.svg", "idiom": "universal" }],
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

**Rule:** When using SVGs that need to change color at runtime, set `template-rendering-intent` to `template` in the asset catalog. Use `.renderingMode(.template)` in SwiftUI's `Image()` as a belt-and-suspenders measure. The SVG's original fill color is ignored — only the shape is used as a mask.

---

## 2026-03-12: Pinning buttons to bottom of screen across variable-height content

**Problem:** The Enhance/Save/Share buttons moved vertically depending on which tab was active (zoom controls had 3 rows, visual effects had 1 row + optional sliders, face filters had different content). This created jarring layout shifts when switching tabs.

**Fix:** Moved the action buttons out of `controlsSection` into a separate `bottomButtons` view placed after a `Spacer(minLength: 0)` in the main `VStack`. The Spacer absorbs all remaining space between the variable-height controls and the pinned bottom buttons, ensuring the buttons always sit at the same position regardless of content above.

**Rule:** When a bottom action area should stay fixed while content above varies, use `Spacer(minLength: 0)` between the variable content and the pinned buttons inside a `VStack`. Don't place the buttons inside the variable content's container.

---

## 2026-03-12: Ripple effect — whole-image shake vs strip displacement

**Problem:** The original ripple effect displaced individual horizontal strips with a sine wave, creating a "water ripple" look. The user wanted the face to shake rapidly as a whole unit, not have sections shift independently.

**Fix:** Rewrote `RippleEffect` from 40-strip compositing to a single `CGAffineTransform(translationX:y:)` applied to the entire image. Uses `sin(frameIndex * speed)` for rapid horizontal oscillation. The image is `.clamped(to: extent)` before translation to prevent edge gaps. When used as a face effect via the `FaceVisualEffect` adapter, the radial mask isolates the shake to just the face region.

Added a red tint overlay using `CIImage(color:)` composited over the shaken image. The slider controls `redness` (opacity of the red overlay) rather than shake intensity, which is fixed at a "heavy" level.

**Rule:** For vibration/shake effects, translate the entire image as a unit rather than displacing strips. Strip-based approaches create wave patterns, not vibrations. Use `sin(frameIndex * speed)` for smooth oscillation and `.clamped(to:)` to handle edge pixels during translation.

---

## 2026-03-12: Gallery GIF quality vs performance trade-offs

**Problem:** Gallery GIF previews looked choppy and blurry due to aggressive optimization — only 15 frames kept (via `count/15` skip) at 200px resolution.

**Analysis:** On modern iPhones with 4-6GB RAM:
- 200px × 200px × 4 bytes × 15 frames = ~2.4 MB per GIF
- 350px × 350px × 4 bytes × 30 frames = ~14.7 MB per GIF
- With visibility-based loading (~6-9 visible), that's ~90-130 MB total — well within device capabilities

**Fix:** Increased frame count to 30 (`count/30`), resolution to 350px, and GIF cache to 150MB. Also made quality adaptive based on grid layout: single-column mode (zoomed in via pinch) renders at full resolution with full framerate (`lowQuality: false`), while multi-column layouts keep the optimized mode.

**Rule:** Don't over-optimize for performance without measuring actual impact. Modern devices can handle significantly more decoded image data than early optimization assumptions allow. Make quality adaptive based on context — a single large preview can afford full quality while a grid of 9 thumbnails benefits from optimization.

---

## 2026-03-13: Separating generation zoom from canvas zoom

**Problem:** When re-editing an existing GIF, zoom coordinates were hardcoded (`currentScale = 2.0`, `visibleRect = (0.15, 0.15, 0.7, 0.7)`) regardless of the original zoom point. Additionally, navigating the image in face filter mode (panning/zooming to find faces) would modify `currentScale`/`visibleRect`, causing subsequent GIF regeneration to use the wrong zoom point.

**Fix:** Introduced `generationScale` and `generationVisibleRect` as separate private properties in `EditorViewModel`. `generateGIF()` captures `currentScale`/`visibleRect` into these properties at generation time. `regenerateGIF()` always uses the generation properties, not the live canvas state. For existing GIFs, generation params are restored from UserDefaults (keyed by PHAsset identifier) when available, falling back to hardcoded values for first-time edits.

**Rule:** When a view model property serves dual purposes (display state AND data input to a processing pipeline), split it into two: one for the UI binding and one frozen at the point of commitment. This prevents UI exploration from corrupting processing inputs.

---

## 2026-03-13: CGContext-based overlays for custom shapes in CIImage pipelines

**Problem:** CIImage/CIFilter has no built-in heart shapes, speed lines, or complex geometry primitives. Face effects like heart vignette, heart eyes, and anime background require custom shapes composited onto CIImage.

**Fix:** Render custom shapes into a CGImage via `UIGraphicsBeginImageContextWithOptions` + `CGContext` drawing (Bézier paths for hearts, line strokes for speed lines), convert to CIImage, then composite using `.composited(over:)` or `CIBlendWithMask`. Position by applying `CGAffineTransform(translationX:y:)` to align with face landmarks.

**Rule:** Use CGContext as a bridge when CIFilter lacks the geometric primitives you need. Render to a bitmap at the target resolution, convert to CIImage, then use CIFilter compositing operations to blend. Keep the CGContext rendering isolated in a helper method for testability.

---

## 2026-03-13: Removing effects from enums while keeping underlying implementations

**Problem:** Removing image effects (scanlines, fade to B&W, ripple) from `VisualEffectType` while their underlying effect classes (`FadeToBWEffect`, `RippleEffect`) are still used by `FaceFilterType` via `FaceVisualEffect` adapter.

**Fix:** Removed only the enum cases from `VisualEffectType` and their `switch` branches. Kept the effect implementation files (`FadeToBWEffect.swift`, `RippleEffect.swift`) since they're instantiated directly by `FaceFilterType.effect()`. Only deleted `ScanlinesEffect.swift` (no face filter counterpart) and the stale `GlitchEffect.swift`.

**Rule:** When removing features from a user-facing enum, trace all usages of the underlying implementation before deleting files. An effect class may be used directly by another subsystem even after it's removed from the primary enum.

---

## 2026-03-13: Replacing SwiftUI gestures with UIScrollView for smooth pinch/zoom

**Problem:** The editor canvas used SwiftUI `MagnificationGesture` + `scaleEffect` + `DragGesture` for pinch/zoom. Every gesture frame triggered a full SwiftUI view body re-evaluation, causing janky, laggy zoom — especially with the `ZoomFrameOverlay` minimap and face box overlays also redrawing on each change.

**Fix:** Rewrote `ImageCanvasView` as a two-layer architecture: a `UIViewRepresentable` wrapping `UIScrollView` (with `UIImageView` as zoomable content) for hardware-accelerated `CALayer` transforms, wrapped in a SwiftUI `View` that layers `ZoomFrameOverlay` on top. Face box overlays became `UIView` subviews of the `UIImageView` (scaling naturally with the zoom transform) with `CAShapeLayer` borders and `CABasicAnimation` pulse. The public API stayed identical so `EditorView` required zero changes.

**Rule:** When SwiftUI gesture-driven transforms cause frame drops, replace with `UIScrollView` via `UIViewRepresentable`. UIScrollView provides native 60fps zoom with inertia, rubber-banding, and no layout passes. Keep SwiftUI overlays (like minimaps) outside the `UIViewRepresentable` in a `ZStack`, reading the same bindings.

---

## 2026-03-13: UIViewRepresentable image swap must not reset scroll state

**Problem:** After switching to `UIScrollView`, applying a face effect caused the image to jump to the top-right corner. The effect pipeline generates a new `UIImage` on every preview update, and `updateUIView` detected this via `imageView.image !== image` (identity check), triggering a full content size reconfiguration that reset the scroll offset. The preview images are also downscaled (650px max) compared to the source, so the offset restoration math produced wrong values.

**Fix:** Changed `updateUIView` to only swap `imageView.image` without touching `contentSize`, `zoomScale`, or `contentOffset`. The scroll geometry is configured once in `makeUIView` based on the source image. Since `UIImageView` uses `.scaleAspectFill`, images of different resolutions display identically within the same frame — no content size reconfiguration needed for preview swaps.

**Rule:** In `UIViewRepresentable.updateUIView`, distinguish between state changes that require scroll geometry reconfiguration (source image with different aspect ratio) versus cosmetic updates (preview image swap at same or different resolution). For the latter, only update `UIImageView.image` and leave all scroll view properties untouched. Never use `!==` identity comparison to decide whether to reconfigure layout — preview pipelines create new `UIImage` instances every frame.

---

## 2026-03-13: Snapshot-based undo/redo for editor state

**Problem:** The editor has many interrelated state properties (effect type, intensity, speed, pause, face selection, etc.) and no way to step backward after making changes. Users who accidentally reset or change effects lose their previous configuration.

**Fix:** Created an `EditorSnapshot` struct capturing all undoable state. `EditorViewModel` maintains `undoStack` and `redoStack` arrays (capped at 50 entries). `pushUndo()` is called before every user-initiated change — button taps call it directly, sliders call it on drag start only (via a `sliderUndoPushed` flag) to avoid flooding the stack. `undo()`/`redo()` pop from one stack, push to the other, and restore the snapshot. `resetEffects()` pushes undo first so reset itself is undoable.

**Rule:** For undo in a multi-property editor, use lightweight value-type snapshots rather than command objects. Push snapshots *before* changes (not after). For continuous gestures like sliders, push on drag start and use a boolean flag to prevent duplicate pushes during the drag. Cap the stack to prevent unbounded memory growth.

---

## 2026-03-13: SegmentedBar onWillChange for pre-mutation hooks

**Problem:** `SegmentedBar` writes to a `@Binding` inside its button action. Undo requires capturing state *before* the binding changes, but the `onChange` callback fires *after* the write.

**Fix:** Added an `onWillChange` closure parameter to `SegmentedBar` that fires before the binding is updated. Also added a `guard selection != item` to skip the callback when tapping the already-selected item. This gives callers a clean pre-mutation hook for undo pushes.

**Rule:** When a reusable component writes to a binding and callers need a pre-mutation hook, add an explicit `onWillChange` callback that fires before the binding write. Don't rely on SwiftUI's `.onChange(of:)` view modifier — it fires after the state change.

---

## 2026-03-13: SwiftUI Button + onLongPressGesture conflict

**Problem:** In the gallery grid, `GifGridItem` uses a `Button` for tap handling and `.onLongPressGesture` for entering multi-select mode. When the long press fires and the finger lifts, the `Button`'s tap action also fires — causing `enterSelectMode` to add the index and `toggleSelection` to immediately remove it, exiting select mode.

**Fix:** Two changes: (1) Replaced `.onLongPressGesture` with `.simultaneousGesture(LongPressGesture(...))` so both gestures can coexist. (2) Added a `@State var longPressTriggered` flag — set `true` when long press fires, checked and reset in the button action to suppress the phantom tap.

**Rule:** Never combine SwiftUI `Button` with `.onLongPressGesture` on the same view — the long press end will trigger the button tap. Use `.simultaneousGesture(LongPressGesture)` instead, and add a flag to suppress the tap that fires on finger-up after a long press.

---

## 2026-03-13: SVG fill-opacity compounds with SwiftUI template rendering

**Problem:** Custom pixel-art SVG icons added to the asset catalog as template images appeared gray instead of white, even with `.foregroundColor(.white)`. The SVGs had `fill-opacity="0.5"` baked into every rect element.

**Fix:** Removed `fill-opacity="0.5"` from all SVG rects, setting them to solid `fill="white"`. Template rendering uses the SVG's alpha channel as a mask — the 50% opacity in the SVG compounded with the SwiftUI foreground color, making the icons permanently dimmed.

**Rule:** When using SVG assets with `template-rendering-intent: template`, ensure all fill elements use full opacity (`fill-opacity="1.0"` or omit it). Control opacity exclusively via SwiftUI's `.foregroundColor` or `.opacity` modifiers. Any alpha baked into the SVG source will multiply with the runtime tint.

---

## 2026-03-13: Toggle buttons vs segmented bars for optional selection

**Problem:** The zoom type (ZOOM IN / ZOOM OUT / PULSE) and modifier (STRAIGHT / SHAKE / SPIRAL) controls used `SegmentedBar` — a component that always has one item selected. The design called for making all options deselectable so the user can create GIFs with only visual/face effects and no zoom animation.

**Fix:** Replaced `SegmentedBar` (which binds to a non-optional `T`) with inline toggle buttons that bind to optional types (`AnimatorType?`, `ModifierType?`). Tapping a selected button sets the value to `nil`; tapping an unselected one sets it. The toggle button style matches the existing `SegmentedBar` appearance (green-tinted bg, mint border, mint text when selected).

**Key design decision:** Rather than making `SegmentedBar` support optional bindings (which would complicate its API for a single use case), the toggle buttons were built inline in `EditorView` — they reuse the same visual pattern as `visualEffectToggle` and `faceFilterToggle`. This keeps `SegmentedBar` simple for cases where mandatory selection is needed.

**Rule:** When converting from mandatory selection (always-one-selected) to optional selection (deselectable), prefer individual toggle buttons over modifying a segmented control. Optional bindings in segmented controls create confusing UX (which segment shows as "none"?) and complicate the component's generic API.

---

## 2026-03-13: StaticAnimator for effects-only GIF generation

**Problem:** When the user deselects all zoom types, `activeAnimator` had nothing to return. The GIF generator still needs an `Animator` conformant to produce frames — each frame requires `AnimationParameters` (scale, centerX, centerY).

**Fix:** Created `StaticAnimator` — a simple struct conforming to `Animator` that returns `context.userZoomParams` for every progress value. This holds the camera at the user's current zoom position without any movement. When the user hasn't zoomed in (`currentScale = 1.0`), the params represent the full image at 1x scale — each frame shows the identical view while visual/face effects animate over it.

**Rule:** When an animation system requires a non-nil animator but the user wants "no animation," provide an identity/no-op implementation rather than making the animator optional throughout the pipeline. This avoids nil-checking in every consumer (GIF generator, preview, etc.) and keeps the type system clean.

---

## 2026-03-13: Removing the zoom requirement for GIF generation

**Problem:** `GIFGenerator.prepareDrawingContext()` had a hard `guard currentScale > 1.0 else { return nil }` that prevented GIF generation at 1x scale. When the user applied visual/face effects without zooming in, the generator returned nil and the app showed "Error creating GIF."

**Fix:** Two changes:
1. **GIFGenerator:** Replaced the guard with `let effectiveScale = max(1.0, currentScale)` so the pipeline always proceeds. At 1x scale, the full image is rendered into each frame — effects still animate across frames.
2. **EditorViewModel:** Added conditional validation in `generateGIF()` — if a zoom type is selected, zoom-in is required; if no zoom type but effects are applied, generation proceeds at 1x; if neither zoom nor effects, shows "Select an effect or zoom type first!" Also relaxed `regenerateGIF()` to allow regeneration at 1x when no zoom type is selected.

**Rule:** When loosening a precondition in a lower-level service (GIF generator), move the user-facing validation to the calling layer (ViewModel) where context about user intent is available. The service should be permissive; the caller should be opinionated about when to invoke it.

---

## 2026-03-13: Parameterizing CIFilter effect colors via enum

**Problem:** `LazerEyesEffect` had hardcoded red CIColor values for all glow layers (core, inner glow, bloom, flares). Adding color selection required replacing 5 separate color values that were carefully tuned relative to each other.

**Fix:** Created a `LaserColor` enum with 6 presets, each providing an `rgb: (CGFloat, CGFloat, CGFloat)` tuple. The effect derives all layer colors from the base RGB:
- **Core:** `0.5 + color * 0.5` — keeps a white-hot center with a slight tint
- **Inner glow:** raw color at full saturation
- **Bloom:** `color * 0.8` — slightly deeper for depth
- **Narrow flare:** raw color — bright and punchy
- **Wide flare:** `color * 0.7` — softer atmospheric glow

The enum also provides `swiftUIColor` for the UI picker circles, keeping the color definition in one place.

**Rule:** When parameterizing a multi-layer visual effect with color, define the base color once and derive all layer variants mathematically (multiply for deeper, add white for brighter). Don't store separate color values per layer — the relationships between layers should be formulaic so any base color produces a coherent result.

---

## 2026-03-13: Slider fill shape must be Rectangle, not RoundedRectangle

**Problem:** Custom slider bars used a `RoundedRectangle(cornerRadius: 16)` for the fill indicator inside a `ZStack` that was clipped by `.clipShape(RoundedRectangle(cornerRadius: 16))`. At small fill widths, the fill's own rounded corners rendered correctly on the left but on the right edge the fill's independent rounding poked outside the expected region, creating a visible bulge.

**Fix:** Changed the fill shape to `Rectangle()`. The parent `ZStack`'s `.clipShape()` already rounds the outer corners, so the fill only needs to be a flat rectangle that gets masked by the container.

**Rule:** When building custom slider/progress bars with a rounded container, always use `Rectangle()` for the fill and let the parent's `clipShape` handle the rounding. If the fill itself is a `RoundedRectangle`, its corners fight with the container's corners at small and large fill fractions.

---

## 2026-03-13: Regeneration guard must account for effects-only existing GIFs

**Problem:** `regenerateGIF()` had a guard `canRegenerate = generationScale > 1.0 || selectedAnimatorType == nil` that silently failed for existing GIFs that were originally created with effects-only (no zoom, scale = 1.0). When the user re-opened such a GIF and modified settings, `generationScale` was 1.0 (from persisted zoom params) and `selectedAnimatorType` was `.zoomIn` (default), so the guard returned early. The GIF was never regenerated, and saving showed an error.

**Fix:** Added `hasEffectsWithoutZoom` to the guard: `canRegenerate = generationScale > 1.0 || selectedAnimatorType == nil || hasEffectsWithoutZoom`. This allows regeneration at 1x scale when visual effects, face filters, or modifiers are applied.

**Rule:** When a precondition guard in a generation/regeneration path was loosened for the initial generation flow, apply the same loosening to the re-generation flow. Both paths share the same constraints — scale, effects, zoom type — and diverging their guards creates silent regressions for saved content that was produced under the loosened rules.

---

## 2026-03-13: ButtonStyle vs ViewModifier for press animations

**Problem:** The existing `EnhanceButtonPressAnimationModifier` uses `DragGesture(minimumDistance: 0)` via `.simultaneousGesture()` to detect press/release. This works for regular `Button` views but fails with `PhotosPicker` because `PhotosPicker` internally consumes gestures, preventing the `DragGesture` from firing. The "MAKE A GIF" button had no press animation.

**Fix:** Created `EnhancePressButtonStyle` as a `ButtonStyle` conformance that uses `configuration.isPressed` — a system-provided press state that works with all button types including `PhotosPicker`. The `ButtonStyle` approach is applied via `.buttonStyle(EnhancePressButtonStyle())` and doesn't interfere with the control's own gesture handling.

**Rule:** For press animations on standard `Button` views, either approach works. For `PhotosPicker`, `ShareLink`, or any UIKit-bridged control that swallows gestures, you must use `ButtonStyle` with `configuration.isPressed`. Prefer `ButtonStyle` as the universal approach for consistency.

---

## 2026-03-13: ScrollViewReader for restoring carousel scroll position

**Problem:** When switching between effect category tabs (zoom → face → image), the `ScrollView` for each tab is recreated by SwiftUI's conditional rendering (`switch viewModel.selectedEffectCategory`). This means the scroll offset resets to zero every time the user returns to a tab, even if they had scrolled to a specific effect.

**Fix:** Wrapped each horizontal `ScrollView` in a `ScrollViewReader` and added `.onAppear` to auto-scroll to the currently selected effect using `proxy.scrollTo(selected, anchor: .center)` with a small delay (0.05s) to let the layout settle. Each effect toggle is tagged with `.id(effectType)`.

**Rule:** When SwiftUI recreates a `ScrollView` on tab switch, use `ScrollViewReader` + `.onAppear` + `.scrollTo()` to restore position. The `.id()` on each item and a brief async delay are both necessary — without the delay, the scroll target may not be laid out yet.

---

## 2026-03-14: PHPhotoLibrary.register() triggers permission dialog when status is .notDetermined

**Problem:** The app was rejected by Apple (Guideline 2.1a — App Completeness) because it showed a blank screen on first launch. Root cause: `PHPhotoLibrary.shared().register(self)` was called in `PhotoManager.init()`, which runs at app startup via `@StateObject`. When permission status is `.notDetermined`, registering as a change observer triggers the system permission dialog immediately — before the user has any context about why the app needs access.

Additionally, when the user denied permission, `hasLoadedGifs` was never set to `true` (since `fetchMyGifs()` was never called), leaving the UI stuck on an empty `Spacer()`.

**Fix:** Deferred observer registration behind a `registerObserverIfAuthorized()` guard that only calls `PHPhotoLibrary.shared().register(self)` when status is `.authorized` or `.limited`. The registration is retried after `requestAuthorization()` succeeds and when `checkAuthorizationStatus()` finds the user is authorized. Also set `hasLoadedGifs = true` when permission is denied so the UI always progresses past the loading state.

**Rule:** Never call `PHPhotoLibrary.shared().register(self)` unconditionally at init time. Check `authorizationStatus(for:)` first and only register when already authorized. Calling register with `.notDetermined` status triggers the permission dialog as a side effect — the system needs to observe the library to notify you, which requires access.

---

## 2026-03-14: Infinite carousel with center-scale requires cumulative position math

**Problem:** A uniform `itemStep` for carousel positioning caused items to overlap when sizes varied. The center item was 305pt wide but the step was based on the smaller 265pt edge size, resulting in `step = 265 + 16 = 281` — less than the center item's half-width (152.5) plus the neighbor's half-width (132.5) plus spacing (16) = 301.

**Fix:** Replaced uniform `itemStep * displayOffset` with cumulative `xPosition()` that walks from center outward, summing `(thisItemHalf + spacing + nextItemHalf)` for each step. This guarantees exactly `spacing` pixels between any two adjacent items regardless of their individual sizes.

**Rule:** When items in a carousel have different sizes based on position (e.g., center-scale effect), you cannot use a uniform step for positioning. Compute positions cumulatively from center, using each item's actual half-width at its specific position. The gap between any two adjacent items is `halfWidth_A + spacing + halfWidth_B`.

---

## 2026-03-14: Drag gesture snap direction must account for auto-scroll offset

**Problem:** The carousel auto-scrolled forward, making `dragStart` a non-integer (e.g., 2.3). For tiny swipes, `dragStart.rounded()` snapped to the nearest integer. Swiping left-to-right accidentally worked (round(2.3) = 2.0 matched the swipe direction), but swiping right-to-left also snapped to 2.0 — against the swipe direction.

**Fix:** Lowered the directional drag threshold from 0.2 to 0.05 items so even small intentional swipes use `ceil(dragStart)` or `floor(dragStart)` based on drag direction. The fallback for truly accidental touches uses `position.rounded()` (current finger-up position) instead of `dragStart.rounded()`.

**Rule:** When a carousel has auto-scroll, the drag start position is fractional. Never use plain `.rounded()` for snap targets — it ignores swipe direction. Always use `ceil`/`floor` based on the sign of the drag translation, with a very low threshold to distinguish intentional swipes from accidental touches.

---

## 2026-08-07: Caches/ is purged for apps that sit unused — the recovery path is the feature

**Problem:** Users reported that GIFs vanished from the gallery if the app hadn't been opened for a while. The assets were intact in Photos the whole time — the gallery simply stopped showing them, and reinstalling was the only apparent fix.

**Root cause — four defects composing into one failure:**

1. GIF originals are cached in `Library/Caches/MyGIFs/`. iOS purges `Caches` under storage pressure and **preferentially targets apps the user hasn't opened recently** — which is precisely the reported trigger.
2. The cache-miss recovery path could not reach iCloud. `PHContentEditingInputRequestOptions` never set `isNetworkAccessAllowed = true`, while the thumbnail options *in the same fetch* did. A device that sits unused also offloads photos to iCloud, so `input?.fullSizeImageURL` came back nil exactly when recovery mattered most.
3. The nil fallback called `requestAVAsset(forVideo:)` on a **photo** asset — an API that can never succeed for a photo. So the fallback was structurally dead code.
4. `cleanupStaleCacheFiles()` then deleted cache files for every asset that had failed to resolve, converting a transient network failure into permanent cache loss. If the whole fetch failed, it wiped everything.

The amplifier: a GIF is only displayed when **both** its thumbnail and its file URL resolve (`Set(gifResults.keys).intersection(urlResults.keys)`), and `GalleryView` only renders the grid when both arrays are non-empty. So a URL failure didn't degrade the cell — it removed the GIF entirely, and a total failure dropped the user to the empty/onboarding state.

**Fix:** Replaced the photo path with `PHImageManager.requestImageDataAndOrientation(for:options:)` using `version = .original` and `isNetworkAccessAllowed = true`. This is the correct API for retrieving original animated-GIF bytes — `requestContentEditingInput` is designed for edit sessions, returns a URL that may not exist locally, and offers no clean network policy. `requestAVAsset` is now used only for genuine video assets. `cleanupStaleCacheFiles()` runs only after a complete fetch that resolved every asset.

**Rule:** `Caches/` is not storage, it is a hint. Anything placed there **will** be deleted, and specifically when the app has been idle — the worst possible moment, because that is also when the source may have been offloaded to iCloud. If you cache derived copies of Photos assets, the re-fetch path must set `isNetworkAccessAllowed = true` and must be exercised in testing, because it is the only thing standing between a routine system purge and what users experience as data loss. Test it by deleting the cache directory out from under a running app, not by waiting for the system to do it.

**Rule:** Never let a cleanup routine act on a partial result set. Derive "what is still valid" only from a fetch known to be complete; otherwise a transient failure teaches the cache to delete data it will need again. Gate the sweep on an explicit completeness flag, never on "whatever we happened to load this time."

---

## 2026-08-07: requestImageDataAndOrientation vs requestContentEditingInput for original bytes

Three ways to get pixel data back out of a `PHAsset`, and they are not interchangeable:

- **`requestImageDataAndOrientation`** — returns the original file's `Data`. With `version = .original` this preserves animated GIF frames intact. Honours `isNetworkAccessAllowed`, so it can pull an iCloud-offloaded asset back down. **This is the right call for "give me the original file."**
- **`requestContentEditingInput`** — designed for building an *edit session*. Its `fullSizeImageURL` points at a local file that may simply not exist for an offloaded asset, and `PHContentEditingInputRequestOptions` has no straightforward network policy. Reaching for it to copy a file is using an edit API as a download API.
- **`requestImage`** — returns a rendered `UIImage` at a target size. Fine for thumbnails, useless for GIFs: it flattens the animation to a single frame.

**Rule:** To copy an asset's original bytes, use `requestImageDataAndOrientation` with `version = .original`. Reserve `requestContentEditingInput` for actual editing flows. And whenever a fetch sets `isNetworkAccessAllowed` on one request, check every *other* request in the same operation — the bug here was one options object having it and its sibling not.

---

## 2026-08-07: DispatchGroup + Photos callbacks needs idempotent leaves and a timeout

**Problem:** `PHImageManager.requestImage` with `deliveryMode = .highQualityFormat` can invoke its handler more than once — a degraded placeholder followed by the final image. The fetch handled this by returning early on `PHImageResultIsDegradedKey` without calling `group.leave()`, so only the final delivery balanced the group. Correct — but only if a final delivery always arrives. When an iCloud download stalled, it never did: `group.notify` never fired, `isFetching` stayed `true`, and the `guard !isFetching` at the top of the fetch turned every subsequent refresh into a silent no-op for the rest of the session. Only relaunching recovered.

**Fix:** Two changes. Every `enter()`/`leave()` pair is now brokered by a small `LeaveGuard` class that holds a lock and a `hasLeft` flag, so a repeated callback cannot over-balance the group (a runtime trap) and the intent stays readable at the call site. And `group.notify` was replaced with `group.wait(timeout: 30s)` on a background queue, so the completion path runs whether or not every request reported in — `isFetching` always clears.

**Rule:** Never balance a `DispatchGroup` directly inside a Photos callback. Those handlers may fire twice, once, or never, and each of those has a different failure: a trap, a hang, or a silent stall. Route leaves through an idempotent token, and always pair `DispatchGroup` with `wait(timeout:)` rather than `notify` when the work depends on the network. Any "is in flight" boolean guarding re-entry must have a guaranteed path back to `false` — otherwise one stalled request disables the feature until the process restarts.

---

## 2026-08-07: Never sweep a directory that contains another cache's directory

**Problem:** `ThumbnailCache` stored disk thumbnails at `Caches/MyGIFs/Thumbs/` — *inside* the directory that `GIFLibraryService.cleanupStaleCacheFiles()` sweeps for stale files. The sweep listed the directory's contents, found the entry `Thumbs`, failed to match it against the set of valid `.gif` filenames, and recursively deleted it. Because `thumbsDir` was created only in the singleton's `init`, it never came back: every later write failed silently through `try?`. The disk thumbnail cache had almost certainly never survived past the first gallery refresh.

**Fix:** Exposed the name as `ThumbnailCache.directoryName` so the sweep skips it by shared constant rather than a duplicated string literal, and moved directory creation into an `ensureDirectory()` call on every write instead of once at `init`.

**Rule:** A "delete everything I don't recognise" sweep is only safe over a directory it exclusively owns. If two caches share a parent, the sweep must skip the other's entries via a shared constant — never a hardcoded string in the sweeping file. And any directory under `Caches/` must be re-created lazily at write time, because `init`-time creation assumes a lifetime the system does not guarantee. Silent `try?` writes into a missing directory fail invisibly, so this class of bug produces no logs at all.

---

## 2026-08-07: Stale tests encode behaviour you deliberately removed

**Problem:** The suite had three tests failing on `main`, and had for several sessions. None represented a real defect — each asserted a contract that had been intentionally changed:

- `generateGIF_withScaleTooLow_returnsNil` — Phase 13c removed the hard `currentScale > 1.0` guard so effects-only GIFs could be generated. There is no longer any low-scale nil path.
- `resetEffects_restoresDefaults` — asserted `selectedModifier == .straight` and `playbackSpeed == 1.0`. Phase 13c made modifiers deselectable (reset is `nil`), and the default speed is 0.5.
- `pixelate_atZeroProgress_returnsUnchanged` — the 2026-03-11 progress inversion made progress 0 *maximum* pixelation. The pass-through moved to progress 1.

**Cost:** A permanently red suite is worse than no suite. It trains you to ignore failures, so it could not be used to check the cache fix for regressions until it was repaired first — exactly when a trustworthy signal was most useful.

**Rule:** When you deliberately change a contract, grep the test suite for it *in the same change* — the tests encoding the old behaviour are a feature of having tests, not noise to triage later. Before trusting a suite as a regression signal, confirm it is green on the untouched baseline; if it is not, fix that first and separately, so a pre-existing failure is never mistaken for one you just introduced. Stashing changes and re-running is the cheap way to tell those apart.

---

## 2026-08-07: Retiring features via a `retired` set, not deletion or comments

**Problem:** Six image effects (Monotone, Duotone, Bloom, Inversion, Vintage Grain, Pop Art) needed to come out of the app, but not out of the codebase — they might be wanted again after a redesign. The obvious options are both bad. Deleting means re-deriving them later from git archaeology. Commenting them out means they stop compiling against the rest of the app and quietly rot until re-enabling turns into a debugging session.

**Fix:** Keep every case in `VisualEffectType` and gate visibility on a static set:

```swift
static let retired: Set<VisualEffectType> = [.monotone, .duotone, .bloom, ...]
static var selectable: [VisualEffectType] { allCases.filter { !retired.contains($0) } }
```

Then split the callers by audience. Anything enumerating effects *for the user* — the picker carousel, thumbnail generation — walks `selectable`. The test that renders every effect deliberately keeps walking `allCases`, so retired implementations stay compiled **and** exercised. Re-enabling is deleting one entry from the set; nothing else changes.

The order matters too: `selectable` filters `allCases`, so it inherits declaration order and retiring an effect can't reshuffle the ones still on show.

**Second-order consequence to watch:** retiring an effect can strand shared UI plumbing. Duotone was the only effect with `supportsColorPicker`, so retiring it left the whole `duotoneColor` path (view model property, `EditorSnapshot` field, picker view, regeneration handler) intact but with no visible consumer — exactly the shape that looks like dead code to a future tidy-up. The defence is a test that asserts the dormant state (`no selectable effect supports the color picker`), which both documents the situation and fails the moment a new effect claims it.

**Rule:** To withdraw a feature you may want back, hide it behind a `retired` set rather than deleting or commenting it. Route user-facing enumeration through a filtered list and leave test enumeration on the unfiltered one — that combination is what keeps retired code honest. Before retiring, grep for other subsystems consuming the same implementation (see the 2026-03-13 entry: face filters use visual effect classes directly), and afterwards check whether any shared UI hook has just lost its last consumer.

---

## 2026-08-07: The CIContext working space is linear — additive brightness lies

**Problem:** `ColoredEdgesEffect` darkens the photo so tinted edges read as neon. `CIColorControls` with `kCIInputBrightnessKey: -0.55` looked like it should more than halve the brightness. Rendered, the image was barely dimmed and the edges were swamped.

**Root cause:** `CIContext(options: [.useSoftwareRenderer: false])` — used in both `GIFGenerator` and `EditorViewModel` — has a **linear sRGB** working space. `CIColorControls` brightness is an *additive offset applied in that space*. White at 1.0 linear minus 0.55 is 0.45 linear, which converts back to roughly **0.70 sRGB**. A parameter that reads as "darken by 55%" delivers about 30%.

**Fix:** Darken **multiplicatively** with `CIColorMatrix` scaling the RGB rows. Scaling is proportional, so it behaves the same in either space. The coefficient still has to account for the gamma curve — keeping 12% of a linear value renders near 38% in sRGB, so genuinely dark backgrounds need to keep 4% or less.

**A second trap in the same effect:** tinting the edges by multiplying magnitude by `tint * gain` with `gain > 1` clipped channels *unevenly*. `LaserColor.green` is `(0, 0.8, 0.467)`; at `gain = 3` that becomes `(0, 2.4, 1.4)`, which clamps to `(0, 1, 1)` — the edges rendered **cyan instead of green**. Core Image works in unclamped float, so this doesn't clip until the final render, well after the hue is destroyed. Fix: normalise the tint so its brightest channel is 1, and boost magnitude only *before* the tint multiply, never after.

**Rule:** Never reason about a Core Image chain's brightness or contrast in sRGB terms — the working space is linear unless you explicitly set `workingColorSpace`, and don't change that globally because every existing effect is tuned against the current one. Prefer multiplicative scaling (`CIColorMatrix`) over additive offsets (`CIColorControls` brightness) whenever the intent is "make this a fraction as bright." And when tinting a grayscale mask, keep the colour coefficients within [0,1]: scaling past 1 clips per channel and silently shifts hue.

**Corollary — structural tests cannot catch any of this.** Both bugs passed `output.extent == input.extent` and `createCGImage != nil`. They were only found by rendering the effects to PNG against a test image with a full luminance sweep, colour patches, and hard edges, then *looking at them*. Build that dump harness when adding visual effects; a solid-colour fixture would have shown nothing.

---

## 2026-08-07: SwiftUI ColorPicker cannot be restyled — three dead ends

**Problem:** The Gradient Map effect needs three arbitrary colours, so it uses SwiftUI `ColorPicker`. The editor's own colour swatches (`colorSwatchRow`, used by face filters and Colored Edges) are 26pt circles inside an offset 32pt mint ring, and the goal was to make the gradient stops match. Three approaches were tried and all three failed:

**1. Draw a custom swatch over an almost-invisible `ColorPicker`.** The `ColorPicker` was given `.opacity(0.02)` and a 32pt frame, with the styled circle as an `.overlay(...).allowsHitTesting(false)` so taps would fall through. It looked right and **taps stopped landing entirely.** A `ColorPicker` is a `UIColorWell`, and a well's hit area is its own internal swatch — not whatever SwiftUI frame is wrapped around it. The visible geometry and the tap target diverge, and no amount of frame juggling reconciles them.

**2. Leave the well visible and just ring it.** Hit testing stays entirely with the well, so taps work. But `UIColorWell` draws its own **rainbow spectrum ring** — Apple's "tap for colours" affordance — which then sits *inside* the mint ring, giving each swatch two concentric borders. There is no API to hide or restyle it.

**3. Drive `UIColorPickerViewController` directly from a plain `Button`.** This is the theoretically correct answer: full visual control, real system colour wheel, ordinary SwiftUI hit testing. Wrapping it in a `UIViewControllerRepresentable` and presenting that as `.sheet` content **crashed**: `NSInvalidArgumentException — Application tried to present a nil modal view controller`. `UIColorPickerViewController` manages its own presentation and cannot be hosted as sheet content this way.

**Resolution:** ship the unstyled native wells. The spectrum ring is a recognisable affordance and the inconsistency with `colorSwatchRow` is a smaller cost than any of the above.

**Rule (ColorPicker):** treat SwiftUI `ColorPicker` as unstyleable. If a design calls for a custom colour swatch that opens a colour wheel, either accept the system well's appearance or budget real time for a bespoke picker — do not assume the well can be dressed up. More generally: when a UIKit-backed control is wrapped by SwiftUI, its hit area belongs to the UIKit view, so overlay-plus-`allowsHitTesting(false)` restyling is unsafe for *any* such control, not just this one. And `UIViewControllerRepresentable` is not a universal escape hatch — controllers that present themselves (colour pickers, share sheets, document pickers) need their own presentation path.

---

## 2026-08-07: Asking "how should X look" presumes the answer to "do we want X"

**Problem:** Phase 1 of the effects work shipped nine colour-grade presets (sepia, vintage, noir…) that were immediately cut on review. The user's reaction was "why did we implement those? I don't recall those being part of Phase 1."

**Root cause:** They *were* in the written plan, and the plan was approved. But the only question ever put to the user about them was **"how should the 9 filter presets appear in the UI — one entry with a sub-picker, a new category, or nine separate entries?"** That question smuggles in its own premise. Answering it required engaging with layout, so the more important question — *do you want nine colour grades at all?* — was never asked and never noticed as unasked. Plan approval doesn't repair this: a plan is long, and a reader scanning it will calibrate on the parts they were consulted about.

**Fix (process, not code):** When a proposal bundles several items, ask about *inclusion* before *presentation*. A single "which of these do you actually want?" multi-select ahead of any design question would have cut nine effects before they were built. Presentation questions are for things already agreed on.

**Rule:** A question that offers only *how* options implicitly asserts *whether*, and the user will not always catch the substitution — they are answering what you asked. Before asking how to present something, confirm it is wanted. Signals you have skipped this: the options all differ in layout, or you find yourself explaining trade-offs about UI real estate for a feature the user has never named out loud. When a user later says "I don't recall asking for this", check what you actually asked rather than what the plan recorded — the plan is your reasoning, not their consent.

---

## 2026-08-07: Continuous controls need coalescing, and undo needs the *pre*-change value

**Problem:** Replacing Gradient Map's six preset ramps with three `ColorPicker` slots broke two assumptions the codebase had baked in. Sliders in this app push undo on drag *start* and regenerate on drag *end* (`onIntensityDragEnded`). `ColorPicker` has neither: it writes a new value on every drag frame of the system colour wheel and never signals completion. Wiring it to the existing `.onChange` pattern would have pushed dozens of undo entries per interaction and kicked off a full GIF regeneration per frame.

**Fix:** Two coalescing helpers on the view model.

- `pushUndoCoalesced(previousStops:)` — pushes at most once per 0.7s. Critically it takes the **previous** value: undo snapshots must capture pre-change state, and by the time `onChange` fires the mutation has already happened. SwiftUI's two-parameter `onChange(of:) { old, new in }` supplies exactly that. The alternative — writing the old value back, snapshotting, then restoring — would re-enter `onChange` on an `@Observable` property.
- `scheduleRegenerate(after:)` — a cancel-and-reschedule `DispatchWorkItem`, standing in for the drag-end commit that doesn't exist.

The move from a preset enum to arbitrary colours also invalidated the memoisation strategy: a 32³ colour cube could be precomputed for six fixed ramps, but users can generate unlimited distinct ramps. The cache became a bounded dictionary keyed on *resolved RGB components* rather than on `Color` (whose equality is opaque) — with the useful property that intensity never affects the cube, so dragging the intensity slider always hits the cache.

**One more trap:** `ColorPicker` can return Display P3 colours whose sRGB components fall **outside 0–1**. Unclamped, those corrupt the colour cube. Clamp every channel at the boundary where `Color` becomes numbers.

**Rule:** Before wiring a control to an existing change-handler pattern, ask whether it emits a *stream* or a *commit*. Sliders, steppers and toggles commit; colour wheels, text fields and continuous gestures stream. Streaming controls need debounced side effects and coalesced undo, and their undo must read the pre-change value from `onChange`'s `old` parameter rather than snapshotting after the fact. And any cache keyed on a preset enum needs rethinking the moment the input becomes user-authored — bound it, and key it on canonical values.

---

## 2026-08-07: Preview and GIF apply effects in different spaces — pass the frame scale

**Problem:** The dither effect looked like a static pattern pasted over the photo while the GIF zoomed, and the GIF didn't match what the live preview showed.

**Root cause:** The two pipelines apply effects at opposite ends of the zoom transform.

- **GIF:** `GIFGenerator.createFrameImage` renders the zoomed, cropped 600×600 frame *first*, then `applyVisualEffects` runs on that output. Any effect with a spatial frequency measured in pixels — dither cells, halftone screens — therefore has a cell size fixed in **output** space. The image content scales and pans beneath a pattern that never moves, which is exactly the "overlay pasted on top" look.
- **Preview:** `EditorViewModel.updateCombinedPreview` applies effects to the **un-zoomed** 650px source, and `ImageCanvasView`'s scroll view magnifies the result afterwards. The same pattern is baked into image space and grows as you zoom in — locked to content.

So the effect wasn't broken in either place; the two paths just disagreed about which space the pattern lives in, and only one of them can match the other.

**Fix:** Added a `FrameGeometry` parameter to `VisualEffect`, following the same non-breaking pattern as `viewportCenter`: a third overload with a default implementation that ignores it, so only effects with a spatial grid opt in. `GIFGenerator` builds one per frame; the preview passes `.identity` because it works on the unzoomed source.

**Two things have to track the motion, and scaling alone is not enough.** The first attempt passed only `scale`, which made the cell *size* correct — and the pattern still visibly crawled. The reason is that the zoom animation **pans as it zooms**: `AnimationParameters.centerX/centerY` move every frame, so a grid anchored to the frame's corner slides across the subject even when its cells are the right size. `FrameGeometry` therefore carries both:

- `scale` — keeps cell size proportional to the subject.
- `contentOrigin` — keeps the grid's *phase* aligned, so cells stay over the same image features. `DitherEffect` offsets its grid by `contentOrigin` modulo the cell size before the downscale, and back afterwards.

Computing `contentOrigin` needs the Y flip: the frame is drawn through `UIGraphics` (top-left origin) and read back as a `CIImage` (bottom-left), so it is `outputHeight - transformedOrigin.y`. Shifting the grid also has to be padded (`clampedToExtent().cropped(to: extent.insetBy(-cell*2))`) or the offset exposes an uncovered strip at the edge once the result is cropped back.

**How to actually verify phase alignment.** Extent and non-nil checks cannot see it, and comparing animation frames by eye does not work either because cell size changes every frame too. The decisive property is periodicity: at a fixed scale, shifting `contentOrigin` by exactly one cell must render **byte-identical** output, while a half-cell shift must not. That is a precise, cheap assertion — and it needs a gradient fixture, since a solid colour posterises flat and would pass trivially.

**Consequence worth accepting deliberately:** matching the preview *necessarily* means the cells magnify as the GIF zooms in — at 8x zoom they are 8x larger. That is what "locked to content" means, and it is what the preview has always shown. A `maxCell` ceiling keeps extreme zoom from reducing the frame to a handful of blocks. If the growth is ever too aggressive, partial compensation (`pow(frameScale, 0.5)`) sits between "static overlay" and "fully locked" — but it will then match the preview only approximately.

**Second finding — chunky dither has to be generated at its final size.** `CIDither` has only an intensity input and always works at native pixel resolution, so the obvious "pixelate then dither" ordering fails: it produces flat blocks with fine speckle inside them, not coarse dither. The pattern has to be *generated* at the size it will be displayed: downscale by the cell size, dither and posterise there, then scale back up with `.samplingNearest()` so each dot becomes a solid cell-sized block.

**Rule:** whenever an effect's output has a spatial grid, establish which coordinate space it lives in, and remember that a moving frame needs both its *scale* and its *offset* tracked — fixing size alone leaves a crawl that is easy to mistake for the original bug being unfixed. Check both the preview and the export path — they are separate render paths in this codebase and will silently disagree. Extend the `VisualEffect` protocol with a defaulted overload rather than changing existing signatures; that is how `viewportCenter` was added and it keeps all twenty other effects untouched. And never generate a pattern at one resolution intending to resample it to another: resampling averages the pattern away.
