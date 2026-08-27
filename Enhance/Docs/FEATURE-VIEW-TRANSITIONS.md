# Feature: View Transitions — Product and Implementation Plan

> ## Status: all six ideas built — 2026-08-14, branch `motion-lab`
>
> **Every stage in this document is implemented, all behind flags that default off.** Eight
> `FeatureFlags` keys, one per animation, listed in Settings → EXPERIMENTS.
>
> | Idea | Built as |
> |---|---|
> | 1 — staged editor open | `ChromeEntrance` (shared by editor and lab) + `SharedZoomModifier`, with `isSource:` handover in `GifGridItem` |
> | 2 — save reveal | `Shaders/PixelReveal.metal`, `PhotoManager.justSavedIdentifier`, `PixelRevealModifier` |
> | 3a — shimmer | `ShimmerSweep` + idle-tick in `GalleryView` |
> | 3b — parallax | `Services/DeviceMotionService.swift` |
> | 4 — category switch | consolidated animation in `EditorView.controlsSection` |
> | 5 — tab selection | `Components/EffectCategoryTabs.swift`, extracted from `EditorView` |
> | 6 — tile press | `EffectCardButtonStyle` + `EnvironmentValues.effectCardPressMotion` |
> | Tuning | `MotionCurve` / `MotionTuning` / `MotionTuningStore` / `MotionPreset`, `MotionCurveGraphView`, `MotionLabView` |
>
> **Verified:** full suite green (471 cases, 14 in `MotionTuningTests`); lab, Settings, gallery and
> editor render correctly in the simulator; opening the editor with the shared zoom on logs no
> "multiple matching geometry" warning and no CoreMotion error.
>
> **Two deliberate omissions**, both recorded in the sections below rather than silently dropped:
> the matched-geometry **close** leg (Idea 2's reveal gives the grid its own arrival, and a zoom
> back down would collide with it), and a curve control for the three gallery animations (none of
> them takes a spring).
>
> **Still not done: the on-device pass.** Every gate below asks for one and none has happened.
> The simulator cannot judge feel, cannot exercise the accelerometer at all, and cannot show the
> save reveal without a real save.
>
> Original status: proposed
>
> Scope: six animation ideas spanning the app's Gallery ↔ Editor transition, ambient Gallery
> motion, and effect-browsing motion inside the Editor (category tabs, the card carousel, and
> card press feedback) — plus a **MOTION LAB** to tune all of it live, on the same pattern as
> `GradientTuning`/GRADIENT LAB and `FaceMarkerTuning`/FACE MARKER LAB. This document specifies
> current behavior with file/line citations, then the proposed behavior, technical approach, and
> delivery stages for each.

## Summary

1. **Gallery → Editor (open):** the canvas image appears first; the chrome (top bar, controls,
   buttons) animates in afterward in a staggered, move+scale+fade entrance rather than today's
   single flat fade.
2. **Editor → Gallery (save):** the newly saved GIF's grid cell plays a pixel-dissolve "build in"
   reveal — appearing in randomized cells rather than popping in fully formed — using the slot the
   grid already reserves for it at index 0.
3. **Gallery ambient easter eggs:** a periodic shimmer sweep across the grid (~every 20s of
   idling), and a subtle accelerometer-driven parallax tilt on the grid. Both are genuinely new
   subsystems with nothing to extend, unlike 1 and 2, and are scoped as a separate, later stage.
4. **Effect category switch (Editor tabs):** the card gallery's switch between ZOOM / FACE /
   IMAGE / TEXT should read as fast and snappy, not slow — a quick scale+fade rather than today's
   plain 0.25s cross-fade, and consolidated onto one animation instead of the two different
   durations currently driving it.
5. **Tab selection state:** the active category icon's pill background should scale up as its
   color changes, rather than just fading in place as it does today.
6. **Effect tile press bounce:** tapping an effect card in the browse gallery should get the same
   kind of press-down feedback the gallery's GIF thumbnails already have (`GifGridItem`) — bouncier
   on release, since effect tiles currently have **no press feedback at all**.

Ideas 4–6, like 1, build on real code that already exists (a duration already driving the category
switch, a selection state already toggling, a press style that exists on a sibling component but
not this one) — none of them are guesses about infrastructure that isn't there.

**All of this is tunable, not guessed.** Rather than pick final spring values by reading code,
every numeric knob in Ideas 1 and 4–6 goes into a **MOTION LAB**, following the same shape as the
app's two existing (unmerged) tuning labs — live sliders, a preset strip, and a **COPY
PARAMETERS** button that hands back paste-ready Swift once a feel is settled. The spring curve
itself is visible and editable, not just its two numbers: **one global curve** is the default
every idea rides, shown as a live graph, and each idea can nudge away from it with a small,
visible **micro-adjustment** rather than owning a disconnected curve of its own. See
[Tuning Lab — MOTION LAB](#tuning-lab--motion-lab).

Ideas 1 and 2 build directly on mechanisms that already exist in the code (a `Namespace.ID`
already threaded but unused, a `showControls` flag already driving a delayed fade, a
`[[stitchable]]` SwiftUI Metal shader already shipping for `Pixellate.metal`, an index-0 insertion
point the gallery already produces). Idea 3 has no such anchor and should be spiked separately.

---

## Current behavior (grounding)

There is no `NavigationStack`/`NavigationLink` anywhere in the app — `GalleryView` is the sole
root (`EnhanceApp.swift:18`) and the Editor is presented as a conditionally-rendered overlay, not a
pushed or sheeted screen:

```swift
// GalleryView.swift:483-491
private var editorOverlay: some View {
    Group {
        if isEditorPresented, let vm = editorViewModel {
            EditorView(viewModel: vm, isPresented: $isEditorPresented, namespace: animation)
                .environmentObject(photoManager)
                .onDisappear { editorViewModel = nil }
        }
    }
}
```

**The shared `Namespace.ID` is dead plumbing today.** `GalleryView` declares `@Namespace private
var animation` (`GalleryView.swift:27`) and passes it into `EditorView`, and `GifGridItem` applies
`.matchedGeometryEffect(id: "gif\(index)", in: namespace)` to its image content
(`GifGridItem.swift:48`) — but `EditorView` never calls `.matchedGeometryEffect` on anything itself
(confirmed by grep). So despite the plumbing suggesting a shared-element zoom, **today's open/close
is a plain cross-fade**: `isEditorPresented` toggles under `withAnimation(.spring(response: ...,
dampingFraction: 0.8))` at both call sites — `GalleryView.swift:497` (`.newImage`, response via
the named `AppConstants.Animation.standard` constant, currently 0.3) and `GalleryView.swift:509`
(`.existingGif`, response as the literal `0.3`) — and the overlay's default implicit transition
applies.

**Chrome already has a delayed-entrance skeleton, but it is flat, not staggered:**

```swift
// EditorView.swift:105-108
.onAppear {
    DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Animation.standard) {
        withAnimation { viewModel.showControls = true }
    }
    ...
```

`showControls` then gates a single `.opacity` on the controls section and the bottom buttons
(`EditorView.swift:56-58`, `:78-83`) — one wait, then everything fades in together. There is no
move, no scale, and no per-element stagger today.

**Gallery ordering already reserves the "new item" slot.** `GIFLibraryService` fetches with
`fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]`
(`GIFLibraryService.swift:51`), so the newest GIF always lands at **index 0** — top-left of the
grid. No placeholder-reservation logic is needed; the array update alone puts a fresh item there.

**Save timeline** (`EditorViewModel.swift:1407-1431`, same shape in `updateOriginalGIF`,
`:1459-1483`):

```
success
  → +0.0s   showToast("GIF saved to My GIFs"); enhanceState = .saved
  → +0.5s   photoManager.forceRefreshGifs()      // new item lands at index 0 here
  → +1.5s   self.onSaveComplete?()                // isPresented = false — editor closes
```

That's roughly a **1-second window** where the new GIF is already sitting in
`photoManager.myGifs` / `myGifURLs` while the editor overlay is still on top of it — usable real
estate for staging a reveal instead of the item just being "already there" when the fade clears.

Note also: `updateOriginalGIF` is a **delete-then-recreate**, not a true in-place update — the
comment at `EditorViewModel.swift:1450-1453` confirms the replacement asset gets a *new*
identifier. So re-saving an existing GIF is honestly the same "a new item appeared" event as a
first-time save, not a special case.

**Shader precedent already exists.** `Shaders/Pixellate.metal` is a SwiftUI `[[stitchable]]`
shader applied directly to a UI layer (not a Core Image kernel):

```metal
[[ stitchable ]] half4 pixellate(float2 position, SwiftUI::Layer layer, float size, float2 bounds)
```

This is the exact mechanism to reuse for a pixel-reveal effect, and — important simplification —
it sits entirely outside the `.ci.metal` / CIKernel build-rule gate documented in `ROADMAP.md`
§1c. That gate exists for Core Image kernels used in GIF *generation*; a UI-layer `layerEffect` on
a grid thumbnail needs none of it.

**Motion conventions to respect.** `Design/Motion.swift` documents a deliberate, user-made
decision: chrome (presses, panels, the carousel) all share one curve,
`.spring(response: 0.3, dampingFraction: 0.6)`, "on the user's call 2026-08-12. Three different
springs used to do that job for no reason anyone could name." New chrome-entrance animation should
reuse `Motion.panel` rather than introduce a fourth. `gridReflow`'s `interactiveSpring` is
deliberately excluded from that consolidation because it tracks a live gesture — the staggered
chrome entrance is not a gesture, so it belongs on the shared curve, not a bespoke one.

`EditorView` already has an `accessibilityReduceMotion` precedent, with its own rationale in
comments (`EditorView.swift:10-11`): *"Looping card previews are decorative motion, so they hold
on their settled frame when the user has asked the system for less of it."* Every new animation in
this doc — staggered entrance, pixel reveal, shimmer, parallax — should follow that same rule:
decorative motion collapses to a settled/instant state under reduce motion; it does not just play
slower.

---

## Idea 1 — Gallery → Editor: staged open

> **Update 2026-08-26 — the canvas is seeded so the zoom carries the picture.** An existing
> GIF reaches the canvas only after `AnimatedGifView` decodes every frame off the main thread,
> and that window covers the whole flight — the A/B against the pre-camera build proved the
> morph had *always* flown an empty black card, which the eye reads as "gallery fades to black,
> editor pops in". `GalleryView.selectGif` now hands the tapped cell's `ThumbnailCache` image to
> `EditorViewModel.canvasPlaceholder`, and the canvas draws it *under* `GIFPreviewView` until
> the first decoded frame covers it. Display-only by design: the placeholder never feeds
> generation, detection, or `sourceImage`. The pixel-entrance overlay deliberately still ignores
> it — `PixelBuildOverlay` keeps its "nil renders nothing" contract.
>
> **Second finding, same day (device pass): the matched-geometry open leg never actually flew,
> and was rebuilt as a manual overlay.** What shipped as "the shared zoom" read on device as the
> editor simply appearing. The measured record, frame by frame in the simulator:
>
> - The whole editor fades in on the flight's own spring, **and** the canvas sits at index 1 of
>   the chrome cascade (opacity 0 until `showControls`) — so whatever the geometry did, the
>   hero was invisible for most of the flight and the static grid cell anchored the eye.
> - As the id's inserted **source**, the canvas never interpolates — sources do not fly, and
>   `.identity`, `.scale(0.998)` and both spring paces all popped it to full size in one frame.
> - A flyer chasing the handover as a **non-source** ballooned through its natural full-screen
>   layout: for one frame of the handoff the id has *no* source (the cell has yielded, the
>   canvas has not laid out), and the animation retargets through wherever layout puts it. The
>   camera flight never shows this only because its freeze frame's natural layout *is* its
>   starting spot.
>
> The rebuilt open leg (`GalleryView.ZoomFlight`) keeps the camera's layering but none of its
> geometry: the tapped cell reports its global frame with the tap (`GifGridItem.onTap`), the
> editor reports the canvas's inner rect on layout (`EditorView.onCanvasFrameChange`) — from
> *outside* the chrome entrance, whose scale would contaminate `frame(in: .global)`, and with
> later reports re-aiming the flight because the first layout runs on `contentWidth`'s
> placeholder and lands the flyer short of the border on wider devices — and a
> dedicated overlay above the editor flies the cell's thumbnail between the two measured rects
> while the editor makes its ordinary fade beneath. **One copy of the picture, ever:** the cell
> hides under the flyer (`isHiddenForZoomFlight`), and the canvas keeps its own picture hidden
> too (`hidesPictureForZoomFlight`) — with it visible, the incoming copy rode the chrome
> entrance's scale-and-rise behind the flyer and read as two images *(user's device pass)*.
> The reveal is unanimated, in the same commit the flyer starts dissolving, so it lands under
> an opaque cover; the flyer also flies its corner radius (card 16pt → the canvas's reported
> clip) so the dissolve doesn't flash mismatched corners. The grid's `matchedGeometryEffect`
> plumbing is gone — `sharedZoomID` now serves the camera pair alone. Camera, new-photo,
> flag-off and Reduce Motion entrances are untouched.
>
> **Third finding, same day:** even a working flight is imperceptible on the chrome's 0.3s
> spring — ~90% of its travel is over in ~130ms, which the eye files as a pop. The flight's
> pace is a MOTION LAB knob (`MotionTuning.zoomFlightCurve`, GALLERY ZOOM section), frozen by
> default at 0.5/0.8 rather than inheriting the global — a hero transition wants to be
> *watched*, which is the opposite of what chrome timing optimises for. Decodes by the camera's
> rule (absent = frozen default, not inherit), so pre-knob installs pick the new pace up on
> next launch.

### Behavior

1. **Image first.** The canvas/photo appears immediately — for `.existingGif` content, as a real
   shared-element zoom from the tapped grid cell (finally consuming the namespace that's already
   threaded through); for `.newImage` content (picked via `PhotosPicker`, no originating grid
   cell), a scale+fade pop since there's nothing to zoom from.
2. **Chrome staggers in after.** `topBar`, `controlsSection`, and `bottomButtons` animate in on a
   short cascade (~40–60ms apart) rather than one flat fade, each combining a small upward
   `offset`, a `scaleEffect` from ~0.92→1, and opacity — on `Motion.panel`.

### Technical approach

- **Wire the namespace.** Apply `.matchedGeometryEffect(id: "gif\(index)", in: namespace)` to the
  canvas image in `EditorView` for the `.existingGif(_, index, _)` case, matching the id
  `GifGridItem` already uses. This makes the currently-dead plumbing do real work for the first
  time.
  - **Open question to flag, not silently resolve:** if the editor is closed by Idea 2's new
    reveal-driven flow rather than a symmetric zoom-back-down, the matched-geometry *close* leg
    may not be wanted at all — Idea 2 proposes the grid handles its own reveal instead. Treat the
    matched-geometry wiring as **open-only**; decide the close leg once Idea 2 is built, don't
    build a symmetric close animation that Idea 2 immediately replaces.
  - `.newImage` has no origin cell — no matched geometry is available; use a plain scale+fade pop.
- **Convert `showControls` from flat to staggered.** Smallest diff: keep the single `showControls`
  Bool, but give each chrome view its own `.animation(Motion.panel.delay(index * 0.05), value:
  showControls)` instead of the current one shared implicit animation. No new state machine
  needed.
- **Per-element transition:** replace `.opacity(showControls ? 1 : 0)` with something like
  `.scaleEffect(showControls ? 1 : 0.92).opacity(showControls ? 1 : 0).offset(y: showControls ? 0
  : 12)` on each chrome element.
- **`reduceMotion`:** collapse all delays to 0 and drop scale/offset to a plain cross-fade — same
  pattern already used for looping card previews.

- **Two-source hazard:** the editor is an overlay, so the gallery — including the tapped
  `GifGridItem`, which applies `.matchedGeometryEffect` unconditionally today — **stays in the
  hierarchy underneath while the editor is up**. Two live views claiming the same geometry id
  produces the "multiple inserted views with matching geometry" runtime warning and a broken
  animation. `GifGridItem` therefore needs an `isSource:` parameter (or conditional application),
  driven from `GalleryView` so the grid cell stops being the source once `isEditorPresented` is
  true. The plan's earlier claim that `GifGridItem` needs no changes was wrong; corrected here.

### Files touched

`EditorView.swift` (canvas section, `topBar`, `controlsSection`, `bottomButtons`, `onAppear`
timing). `GifGridItem.swift` + `GalleryView.swift` for `isSource` gating — the namespace/id
contract itself is already in place there.

### Risk

Stagger adds perceived latency before controls are tappable — keep the whole cascade under
~300–400ms total; users start reaching for controls quickly. This needs an on-device feel pass,
not just a code read, consistent with how this repo gates every animation change (ROADMAP.md §1a,
§2c device-check items).

---

## Idea 2 — Editor → Gallery on save: reserved slot + pixel-dissolve reveal

### Behavior

When a save completes, the grid cell at index 0 doesn't just appear — it builds in, pixel region
by pixel region, in randomized order, over about half a second, then settles.

### Technical approach

- **Track "the freshly saved identifier."** Add `@Published var justSavedIdentifier: String?` to
  `PhotoManager`, set it from `saveGIFToLibrary`'s / `updateOriginalGIF`'s success callback (both
  already receive `newIdentifier`), and clear it once the reveal has played.
- **New stitchable shader, `Shaders/PixelReveal.metal`,** sibling to `Pixellate.metal` — plain
  Metal, not `.ci.metal`, so it never touches the CIKernel gate at all:

  ```metal
  [[ stitchable ]] half4 pixelReveal(float2 position, SwiftUI::Layer layer, float progress,
                                      float cellSize, float seed)
  ```

  Hash a per-cell pseudo-random threshold from `position` (quantized by `cellSize`) and `seed`;
  sample and return `layer.sample(position)` once `threshold < progress`, otherwise transparent.
  Animate `progress` 0→1 with `withAnimation(.easeOut(duration: AppConstants.Animation.slow))`
  (0.6s already exists as a constant — reuse it) or a new named curve in `Motion.swift` if the
  feel calls for something else (e.g. `Motion.reveal`), following the file's "name what is
  moving" convention rather than reusing `.panel` for something that isn't chrome.
- **The shader must target the SwiftUI thumbnail layer, not the animated GIF.** SwiftUI shader
  effects (`.layerEffect` et al.) only apply to SwiftUI-rendered content — and `GifGridItem`'s
  animated layer is `AnimatedGifViewWithLoading`, a `UIViewRepresentable` wrapping a `UIImageView`
  (`AnimatedGifView.swift`), which SwiftUI's Metal renderer cannot sample. Applying `.layerEffect`
  there silently does nothing. The workable sequencing: during the reveal, show the **static
  `Image(uiImage: thumbnail)`** (already the cell's base layer, `GifGridItem.swift:37-44`) with the
  shader on it and hold the animated view's opacity at 0; when `progress` reaches 1, drop the
  shader and let the animated view fade in exactly as it does today. The reveal builds in a still
  frame, then the GIF starts moving — which also reads better than revealing a moving target.
- **Gate the reveal on the thumbnail actually existing.** The cell shows a `ProgressView` until
  its thumbnail generates (`GifGridItem.loadThumbnail`, async); a reveal that fires while the cell
  is still a spinner reveals nothing. The ~1s between `forceRefreshGifs()` (+0.5s) and editor
  close (+1.5s) will usually cover generation, but "usually" isn't a sequencing contract — start
  the reveal on (editor closed **AND** thumbnail non-nil), whichever completes last.
- **Cell granularity — flag as a decision, don't assume:** "pixel by pixel" read literally means
  actual image pixels, which at a ~114px grid thumbnail (`GifGridItem.swift:119`,
  `maxPixel = 114 * scale`) would be both expensive per-cell noise and hard to read. **Recommend
  small blocky cells** (e.g. 4–8pt) instead of literal 1px — cheaper, reads more clearly at grid
  size, and is on-brand with the app's existing pixel-art identity (`DitherEffect`,
  `Pixellate.metal` are both cell-based, not literal-pixel). Confirm this against the user's intent
  before building.
- **No manual placeholder needed.** `LazyVGrid`/`ForEach` is keyed over `photoManager.myGifs`
  (`GalleryView.swift:361`), so the slot exists the instant `forceRefreshGifs()` updates the array
  — nothing to reserve by hand. The only new state is "this specific cell renders via the reveal
  shader instead of normally," gated on `justSavedIdentifier`.
- **Sequence the reveal off the editor closing, not off the array update.** The array updates at
  +0.5s while the editor overlay is still covering the grid (see timeline above); starting the
  reveal there would waste it off-screen. Gate the reveal start on `GalleryView.onChange(of:
  isEditorPresented)` transitioning to `false`, checking `photoManager.justSavedIdentifier`.

### Files touched

New `Shaders/PixelReveal.metal`; `PhotoManager.swift` (`justSavedIdentifier` publish/clear);
`GifGridItem.swift` (reveal state + shader application); `GalleryView.swift` (trigger wiring);
optionally `Design/Motion.swift` for a named reveal curve.

### Risk

- Needs a defined recovery path if the user backgrounds the app or re-enters select mode mid-reveal
  — the reveal should just complete or snap to done, never leave a cell stuck partially
  transparent.
- `forceRefreshGifs()` can in principle re-fetch again before the reveal finishes (e.g. rapid
  repeat saves); `justSavedIdentifier` should be keyed per-identifier so a second save doesn't
  corrupt an in-flight reveal for the first.

---

## Idea 3 — Gallery ambient easter eggs (separate, later stage)

Both sub-ideas are genuinely new subsystems — there is no existing `Timer`/`TimelineView`-driven
ambient loop and no `CMMotionManager` usage anywhere in the codebase today (confirmed by grep).
Unlike Ideas 1–2, neither extends something already there, so this is scoped as its own delivery
stage rather than bundled in.

### 3a. Periodic shimmer sweep (~every 20s)

- A `Timer.publish` or `TimelineView(.periodic(from:by:))` on `GalleryView`, firing roughly every
  20s while `galleryContent` is visible, foregrounded (`scenePhase == .active`, already tracked at
  `GalleryView.swift:26`), and idle.
- **Must not fire mid-interaction** — skip/reschedule while `isSelectMode`, `isPinching`,
  `isLoadingPhoto`, or `isEditorPresented` are true. A shimmer sweeping the grid behind an active
  edit is the kind of motion that reads as a bug, not delight.
- Implementation: a diagonal `LinearGradient` strip clipped to the grid bounds, animated via
  `offset(x:)` off-screen-left → off-screen-right over ~0.8–1.2s, easing in/out.
- `reduceMotion`: skip entirely.

### 3b. Accelerometer-driven grid parallax

- A small new `MotionService` under `Services/` (matching the existing `HapticService`,
  `PermissionManager` naming convention), wrapping `CMMotionManager`, publishing a
  low-pass-filtered `@Published var tilt: CGSize`, with start/stop lifecycle tied to
  `GalleryView` appear/disappear and `scenePhase`.
- Map `roll`/`pitch` (or raw accelerometer x/y) to a small offset (±3–6pt) applied to **the whole
  grid as one transform**, not per-cell — per-cell independent motion reads as jittery/broken
  rather than "considered," which was the user's stated goal.
- Damping: raw accelerometer data is noisy; smooth with simple exponential smoothing
  (`smoothed = smoothed * 0.9 + raw * 0.1`) so the grid drifts rather than twitches.
- No `Info.plist` permission entry is needed for basic `CMMotionManager` device-motion/accelerometer
  access (that's only required for `CMMotionActivity`/pedometer APIs, which this doesn't use) —
  worth a final check against whichever specific API is chosen before shipping.
- Runs only while gallery content is on-screen and foregrounded — stop immediately when the editor
  opens or the app backgrounds, since `CMMotionManager` drains battery continuously while active.
- `reduceMotion`: skip entirely.

---

## Idea 4 — Effect category switch (Editor tabs → carousel/grid content)

### Current behavior

Two different animations currently share the job of one transition, at two different durations:

```swift
// EditorView.swift:1185-1191 — the tap site
Button {
    guard viewModel.selectedEffectCategory != category else { return }
    viewModel.pushUndo()
    HapticService.selection()
    withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.selectedEffectCategory = category
    }
}
```

```swift
// EditorView.swift:449-479 — the content switch
private func controlsSection(cardSize: CGFloat) -> some View {
    VStack(spacing: 8) {
        effectCategoryTabs.frame(width: borderedSize)
        switch viewModel.selectedEffectCategory {
        case .zoomEffects: /* ... */ .transition(.opacity)
        case .visualEffects: /* ... */ .transition(.opacity)
        case .faceFilters: /* ... */ .transition(.opacity)
        case .text: /* ... */ .transition(.opacity)
        }
    }
    .animation(.easeInOut(duration: 0.25), value: viewModel.selectedEffectCategory)
}
```

The tap site's `withAnimation(.easeInOut(duration: 0.2))` is what actually drives the state
change; `controlsSection`'s own `.animation(.easeInOut(duration: 0.25), value:
selectedEffectCategory)` is a second, separately-durationed animation racing it for the same
state change. Both are plain eased fades — no scale, matching this doc's earlier finding in
`Design/Motion.swift` that this codebase has repeatedly ended up with more than one curve doing
one job "for no reason anyone could name."

### Behavior

Fast and snappy — explicitly **not slow**, so repeated tab switching never reads as the app
dragging. The outgoing grid/carousel content fades out quickly; the incoming content fades in
while scaling up slightly from a shrunk starting point (e.g. 0.96→1), on one spring, not a linear
ease.

### Technical approach

- Replace both `.easeInOut` calls with **one** shared spring driving the switch — and the one
  that survives must be **`controlsSection`'s container-level `.animation(_:value:)`**, not the
  tap site's `withAnimation`. The tap is not the only writer: `selectedEffectCategory` is also set
  by undo/redo restore (`EditorViewModel.swift:480`) and by `resetEffects`
  (`EditorViewModel.swift:639`), neither of which runs inside the tap's `withAnimation`. Keeping
  only the tap-site call would make an undo that crosses categories snap with no transition. So:
  drop the tap site's `withAnimation` wrapper, keep (and retune) the container modifier, which
  covers every writer.
- Change each case's `.transition(.opacity)` to `.transition(.opacity.combined(with: .scale(scale:
  0.96, anchor: .center)))` (or the tuned value from MOTION LAB).
- Keep it fast: this is exactly why the value is a MOTION LAB slider rather than a guessed
  constant — "fast" is a feel, not a number you can pick from reading the code.

### Files touched

`EditorView.swift` (`effectCategoryIcon`'s tap handler, `controlsSection`).

### Risk

A scale transition on four different grid layouts (zoom cards, visual-effect cards, face-filter
cards, text presets) needs to be checked against all four — a scale that looks right on the
3-card zoom row might clip or look different against a denser grid. Confirm on-device across all
four tabs, not just one.

---

## Idea 5 — Tab (category icon) selection state

### Current behavior

```swift
// EditorView.swift:1183-1204
private func effectCategoryIcon(_ assetName: String, category: EffectCategory) -> some View {
    let isActive = viewModel.selectedEffectCategory == category
    return Button { /* ... */ } label: {
        Image(assetName)
            .renderingMode(.template)
            .foregroundColor(isActive ? mintGreen : .textInactive)
            .frame(width: 72, height: 40)
            .background(
                Capsule().fill(isActive ? Color.mintDim : Color.clear)
            )
            .overlay(/* ... */)
    }
}
```

Because `isActive` is read inside whatever `withAnimation` wraps the state change (today, Idea 4's
tap-site animation), the capsule's fill color and the icon's tint already cross-fade — but the
capsule itself never scales. It fades into existence at full size rather than growing in.

### Behavior

The pill background scales up as its color changes — a small pop, not just a fade — per the
user's framing: *"scales up the background while the color changes."*

### Technical approach

Add a scale to the capsule tied to `isActive`:

```swift
.background(
    Capsule()
        .fill(isActive ? Color.mintDim : Color.clear)
        .scaleEffect(isActive ? 1 : 0.7)
)
.animation(tuning.effectiveCurve(tuning.tabCurve).animation, value: isActive)
```

**Note this needs its own explicit `.animation(_:value:)` on the capsule.** If `tabCurve` and
`categorySwitchCurve` are independently tunable — which is the entire point of a per-idea
micro-adjustment — they cannot both simply be "whatever one animation call happens to carry."
Under Idea 4's consolidation, the content switch is driven by `controlsSection`'s container-level
`.animation(_:value:)` — but that modifier is scoped to `controlsSection`'s subtree, and the tabs
sit inside it, so without their own modifier the capsules would inherit `categorySwitchCurve`.
The capsule's own `.animation(tabCurve, value: isActive)` sits closer to the view, wins for the
capsule's properties, and is what lets the tab pop diverge once MOTION LAB's tab section is
switched to CUSTOM. When both stay on USE GLOBAL, both modifiers resolve to the identical
`globalCurve` value and behave as one curve.

At the global default (`globalCurve`, seeded from `Motion.panel`'s `spring(response: 0.3,
dampingFraction: 0.6)`, the app's one shared chrome curve), note that a tab tap is a much smaller,
faster gesture than a panel opening, and 0.3s may read as sluggish for it. That's exactly what the
TAB SELECTION section's USE GLOBAL/CUSTOM toggle is for: nudge `tabCurve` snappier without
touching what Idea 4's content switch still inherits from the global.

### Files touched

`EditorView.swift` (`effectCategoryIcon`).

### Risk

None significant — this is a small, contained, single-view change with an existing animation
context to ride.

---

## Idea 6 — Effect tile press bounce

### Current behavior

`EffectCardView`'s button has **no press feedback at all**:

```swift
// EffectCardView.swift:41-83
var body: some View {
    Button(action: action) {
        ZStack(alignment: .bottomLeading) { /* ... */ }
        /* ... */
    }
    .buttonStyle(.plain)
    .disabled(isBlocked)
    .opacity(isBlocked ? 0.35 : 1.0)
}
```

Compare the gallery's own `GifGridItem`, which already solves exactly this problem for GIF
thumbnails:

```swift
// GifGridItem.swift:4-11
private struct GifGridItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
```

Effect cards (the browse gallery inside ZOOM / FACE / IMAGE / TEXT) have no equivalent — this is
the concrete gap, not a guess.

### Behavior

Effect tiles get their own press-down/release feedback — and per the user's ask, **bouncier** than
`GifGridItem`'s fairly damped 0.7 release: the release should overshoot slightly and settle,
reading as springier rather than crisp.

### Technical approach

A new `EffectCardButtonStyle`, same shape as `GifGridItemButtonStyle`, applied in place of
`.buttonStyle(.plain)` in `EffectCardView`:

```swift
private struct EffectCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? /* tuned */ : 1.0)
            .brightness(configuration.isPressed ? /* tuned */ : 0)
            .animation(.spring(response: /* tuned */, dampingFraction: /* tuned, lower than 0.7 */),
                       value: configuration.isPressed)
    }
}
```

The exact scale/brightness/response/damping values are MOTION LAB sliders, not literals picked by
reading this doc — "bouncier" is a feel to tune against the real card, same as every other
value in this plan.

**Plumbing note:** don't have the `ButtonStyle` observe `MotionTuningStore` itself. Dynamic
properties inside `ButtonStyle` are an easy place for update semantics to get subtle; the simpler,
unambiguous wiring is for `EffectCardView` (an ordinary observing view) to read the store and pass
plain values into the style — `EffectCardButtonStyle(scale:brightness:curve:)`. The style stays a
dumb value type, and live tuning still repaints mid-session because the view constructing it
re-evaluates on every store change.

### Files touched

`EffectCardView.swift` (new `ButtonStyle`, applied instead of `.plain`).

### Risk

`EffectCardView.action` already guards nothing about press frequency, and cards can be small (down
to `AppConstants.Layout.effectCardMinSize` = 64pt on short devices) — confirm the bounce doesn't
make small cards feel mushy or delay the tap's actual selection, which must stay effectively
instant regardless of how the visual settles.

---

## Tuning Lab — MOTION LAB

### Precedent

Two tuning labs already exist in this codebase, in the same shape, in two different **unmerged
worktrees** (neither is on `main` yet — cite them as precedent for the pattern, not as shipped
infrastructure to import):

- **GRADIENT LAB** — `.claude/worktrees/new-effects-dev-381e60/Enhance/{Models/GradientTuning.swift,
  Models/GradientTuningStore.swift, Views/GradientLabView.swift}`. Tunes the STATIC/DITHER button
  gradient experiments.
- **FACE MARKER LAB** — `.claude/worktrees/text-effects-resume-726acc/Enhance/{Models/FaceMarkerTuning.swift,
  Models/FaceMarkerTuningStore.swift, Views/FaceMarkerLabView.swift}`. Tunes the face-marker
  overlay experiments (CALM, RETICLE, SPOTLIGHT, SCANLINE, entrance SEQUENCE).

Both follow one shape, and MOTION LAB should follow it exactly:

| Piece | Job |
|---|---|
| `<Feature>Tuning: Codable, Equatable` | Every knob, one property each, heavily commented on *why* each exists. `static let default` carries the app's current hardcoded literals forward unchanged — flags-off behavior must not move. `var swiftSnippet: String` renders a paste-ready `static let tuned = …` block. A tolerant `init(from:)` fills any missing key from `.default`, because the lab is expected to grow fields mid-session and an old saved blob must keep decoding. |
| `<Feature>TuningStore: ObservableObject`, `.shared` singleton | `@Published var tuning`, persisted as one JSON blob under one `UserDefaults` key. `@Published private(set) var savedPresets: [Preset]`, persisted the same way. `presets` computed as `[.original] + savedPresets`. `saveCurrentAsPreset`, `load`, `delete` (built-ins excluded), `reset` (clears live tuning; presets survive). |
| `<Feature>Preset: Codable, Equatable, Identifiable` | A full snapshot of the tuning (not a diff against default, so it survives the defaults moving later) plus whatever ancillary state completes "a look" (e.g. which sub-experiments were on). `.original` is a pinned, undeletable built-in — always one tap back to the known-good state. |
| `<Feature>LabView` | A `BottomSheet`, reached from Settings' EXPERIMENTS section via a `→` row. Preview **pinned above the scroll**, so the thing being judged never moves when you reach for the control that changes it. Sliders via `ParameterSliderRow`, normalized through a `0...1` range helper. Preset strip: tap to load, long-press to delete, `+` to save current. Actions: **APPLY** (pushes preview state to `FeatureFlags`), **COPY PARAMETERS** (`UIPasteboard.general.string = store.tuning.swiftSnippet`), **RESET**. |

**The preview hosts the real shipping components, not a lookalike.** `FaceMarkerLabView`'s own
comment states the reasoning directly: *"the entire point is that the lab tunes the shipping code
path — a SwiftUI lookalike would be a second implementation to keep in step, and it would drift."*
MOTION LAB's preview should embed the real tab row and a real `EffectCarousel` of a few stand-in
`EffectCardView`s, wired to read `MotionTuningStore.shared.tuning` — tapping a tab or a card in
the lab plays the exact animation that ships, not a reconstruction of it.

Two things that principle forces, found by checking the actual code rather than assuming:

- **The tab row must be extracted first.** `effectCategoryTabs` is a `private` computed property
  of `EditorView` (`EditorView.swift:1167`), bound to a live `EditorViewModel` — the lab cannot
  embed it as-is. Stage 0 therefore includes extracting it into a standalone
  `Components/EffectCategoryTabs.swift` taking a `Binding<EffectCategory>` (plus the
  active-tint/undo hooks `EditorView` needs), which both `EditorView` and the lab then share.
  This is the same move FACE MARKER LAB already made with `FaceMarkerVariantList`, shared between
  its lab and Settings, "so the lab and Settings cannot drift into meaning different things by
  the same state." Pure extraction, zero visual change — and it must land before the lab's
  preview can be honest.
- **One-shot animations need a replay affordance.** The Idea-1 entrance plays once per editor
  open; a lab preview of it needs a **REPLAY ENTRANCE** button, driven by a bumped counter — the
  exact `replayToken` mechanism `FaceMarkerLabView` already uses, and for the reason its comment
  gives: "the interesting event is *another* tap, and a bool has nowhere to put the second one."

**Ground truth next to the graph:** alongside the plotted curve, animate a small dot or bar using
the **actual** `curve.animation` (toggle its position on a repeating timer). The graph is a
sampled approximation of SwiftUI's spring (see Open Questions); the dot is the real thing. When
they visibly disagree, the dot is right — having both on screen makes the approximation
self-auditing instead of silently trusted.

### Global curve and micro-adjustments

*(Added on the user's request, after the rest of this plan — see the ideas above for where each
curve applies.)* Rather than four unrelated response/damping pairs, one for each idea, MOTION LAB
has **one global curve** that every idea uses by default, and each idea can **nudge away from it**
rather than own a fully independent curve:

```swift
/// A spring, visualisable and editable as a curve rather than as two abstract numbers.
///
/// Deliberately still a *spring* — `response` + `dampingFraction` — not a second curve type
/// alongside it. `Design/Motion.swift` already made this call once, for chrome specifically:
/// "the app's chrome moves on one curve... Three different springs used to do that job for no
/// reason anyone could name." A cubic-bezier timing curve would be more directly draggable as a
/// shape, but it would also be a second animation vocabulary next to a codebase that just spent
/// effort consolidating down to one — see Open Questions for the tradeoff, flagged rather than
/// decided here.
struct MotionCurve: Codable, Equatable {
    var response: Double
    var dampingFraction: Double

    var animation: Animation { .spring(response: response, dampingFraction: dampingFraction) }

    /// Displacement at normalized time `t` (0...1 spans roughly one `response`-length window),
    /// for the graph. A closed-form damped-harmonic-oscillator approximation of what a SwiftUI
    /// spring looks like — **not** a verified reproduction of SwiftUI's own internal curve, which
    /// is not public. Good enough to compare two settings against each other; see Open Questions
    /// before trusting it to predict exact on-device timing.
    func displacement(at t: Double) -> Double { /* damped harmonic oscillator sampling */ 0 }
}

struct MotionTuning: Codable, Equatable {
    /// The default every idea below uses until it is explicitly nudged. Seeded from
    /// `Motion.panel` (`response: 0.3, dampingFraction: 0.6`) — today's one shared chrome curve —
    /// so a lab session that touches nothing changes nothing.
    var globalCurve: MotionCurve

    // MARK: Editor open (Idea 1)
    var entranceStagger: Double        // seconds between chrome elements
    var entranceScale: Double          // start scale, e.g. 0.92
    var entranceOffsetY: Double        // start Y offset in points
    /// `nil` = inherits `globalCurve`. Non-nil is a full `MotionCurve`, not a delta — see the
    /// note below on why a resolved snapshot beats storing an offset.
    var entranceCurve: MotionCurve?

    // MARK: Category switch (Idea 4)
    var categorySwitchScale: Double    // incoming content's start scale
    var categorySwitchCurve: MotionCurve?

    // MARK: Tab selection (Idea 5)
    var tabScaleFrom: Double           // capsule's start scale
    var tabCurve: MotionCurve?

    // MARK: Effect tile press (Idea 6)
    var tilePressScale: Double
    var tileBrightnessDelta: Double
    var tilePressCurve: MotionCurve?   // expected to end up lower-damping than global — bouncier

    static let `default` = MotionTuning(/* today's literals, unchanged; every *Curve is nil */)

    /// Paste-ready block, same shape as GradientTuning's. Must render the optionals honestly:
    /// `entranceCurve: nil` for an inherited curve, a full `MotionCurve(response:damping:)`
    /// literal for a set one — so the pasted snippet reproduces the inherit-vs-frozen split,
    /// not just the resolved numbers.
    var swiftSnippet: String { /* ... */ "" }

    func effectiveCurve(_ override: MotionCurve?) -> MotionCurve { override ?? globalCurve }
}

final class MotionTuningStore: ObservableObject {
    static let shared = MotionTuningStore()
    @Published var tuning: MotionTuning
    @Published private(set) var savedPresets: [MotionPreset]
    var presets: [MotionPreset] { [.original] + savedPresets }
    // saveCurrentAsPreset / load / delete / reset — same shape as GradientTuningStore
}
```

**Why a resolved snapshot per idea, not a stored delta.** `entranceCurve: MotionCurve?` holds a
full `response`/`dampingFraction` pair once set, rather than `entranceResponseDelta: Double`
added to the global at read time. A delta would mean an idea's curve keeps moving every time the
global is retuned, silently, after the idea was already judged and set — the opposite of what
"micro adjustment" should mean once you've settled on one. `nil` (inherit) is what makes the
global cascade; a set value is a deliberate, frozen decision that only the global's *own* section
being retuned should not disturb. It also matches how `GradientPreset`/`FaceMarkerTuning` already
store full snapshots rather than diffs, for the same reason stated there: a preset must still mean
the same thing after the defaults move.

**`MotionCurveGraphView`** — a small `Canvas`-based chart, new under `Components/`, plotting
`displacement(at:)` across 0...1 as a line, visible in two places:

- **Once at the top of the GLOBAL CURVE section**, with its own response/damping sliders under it.
- **Once per idea section**, drawn twice on the same axes: the global curve dimmed as a reference
  line behind it, and that idea's effective curve in front, in the accent color. A visible gap
  between the two lines *is* the micro-adjustment, seen rather than inferred from two numbers.
  Below the graph, a segmented control: **USE GLOBAL** / **CUSTOM**. Switching to CUSTOM seeds
  `entranceCurve` (etc.) from the *current* global values, not from some other default, so the
  first thing CUSTOM shows is a graph with zero visible gap — the sliders underneath then move it
  away from that starting point, which is the tactile "micro adjustment" the user asked for.
  Switching back to USE GLOBAL sets the override back to `nil` rather than merely hiding it, so a
  later global retune actually reaches that idea again.

`FeatureFlags.swift` gains one `@AppStorage` key per idea (`motionEntranceKey`,
`motionCategorySwitchKey`, `motionTabScaleKey`, `motionTilePressKey`) rather than one umbrella
flag — these are four independent, unrelated visual changes, closer to FACE MARKER LAB's five
independent flags than to GRADIENT LAB's two related ones. Each real call site
(`EditorView.controlsSection`, `effectCategoryIcon`, the new `EffectCardButtonStyle`) reads
`MotionTuningStore.shared.tuning.effectiveCurve(_:)` when its flag is on, and today's literal
`.spring(...)` call when it's off — so the lab can graduate ideas one at a time rather than
all-or-nothing.

### Files touched

New: `Models/MotionTuning.swift`, `Models/MotionTuningStore.swift`, `Views/MotionLabView.swift`,
`Components/MotionCurveGraphView.swift`, `Components/EffectCategoryTabs.swift` (extracted from
`EditorView`), `EnhanceTests/MotionTuningTests.swift` (round-trip + tolerant-decode coverage,
mirroring `GradientTuningTests`/`FaceMarkerTests`, plus a case asserting `entranceCurve == nil`
still resolves to the *current* global rather than a stale copy). Modified: `FeatureFlags.swift`
(new keys), `SettingsView.swift` (`MOTION LAB →` row + `.sheet`), `EditorView.swift`,
`EffectCardView.swift`.

**One deliberate divergence from `GradientPreset`:** `MotionPreset` snapshots only the tuning,
not the feature flags. `GradientPreset` carries `staticOn`/`ditherOn` because the same palette
under a different effect state *is a different look* — the toggles are part of what's being
judged. MOTION LAB's flags don't shape the look; they only gate which call sites read the tuning
at all. A motion preset is fully described by its numbers, so the flags stay out of it.

### Workflow this unlocks

Tune live on device → **COPY PARAMETERS** → paste the snippet back into a message here → the
final values get committed into `EditorView.swift` / `EffectCardView.swift` / `Design/Motion.swift`
as the new defaults, and the lab scaffolding is deleted — the exact "scaffolding, meant to be
deleted" contract both existing labs already document.

**One graduation boundary to respect:** `globalCurve` governs *the four animations in this plan*,
nothing more. It is seeded from `Motion.panel`'s values, but graduating it does **not** mean
writing the tuned value back into `Motion.panel` — that constant also drives button presses,
panels, and the carousel app-wide, none of which this lab previews or tunes. If the tuned global
ends up different from `(0.3, 0.6)`, it lands as a *new* named curve in `Motion.swift` (the file's
own convention: names say what is moving), and whether `Motion.panel` should follow it is a
separate, deliberate decision made while looking at presses and panels — not a silent side effect
of tuning tab switches.

---

## Delivery stages

### Stage 0 — MOTION LAB scaffolding

- `MotionTuning`, `MotionTuningStore`, `MotionPreset`, following the `GradientTuning`/
  `FaceMarkerTuning` shape exactly (see [Tuning Lab](#tuning-lab--motion-lab)).
- Extract `effectCategoryTabs` from `EditorView` into `Components/EffectCategoryTabs.swift`
  (pure refactor, zero visual change) — prerequisite for an honest preview; see the tuning-lab
  section for why.
- `MotionLabView` with a live preview hosting the **real** extracted tab row and a real
  `EffectCarousel` of stand-in `EffectCardView`s, plus a REPLAY ENTRANCE button (`replayToken`
  counter, per `FaceMarkerLabView` precedent) for the one-shot Idea-1 entrance.
- `MOTION LAB →` row in Settings' EXPERIMENTS section.
- `default` seeded from today's literals across Ideas 1, 4, 5, 6 — `globalCurve` from
  `Motion.panel`'s `(0.3, 0.6)`, every idea's `*Curve` left `nil` — so turning every flag on with
  no tuning applied changes nothing visually. Same "flags-off is unchanged" contract both existing
  labs hold themselves to.
- `MotionCurveGraphView`, and the GLOBAL CURVE section (graph + response/damping sliders) plus the
  per-idea graph-and-USE-GLOBAL/CUSTOM pairing described above.

**Gate:** opens from Settings; the global curve's graph visibly changes shape as its sliders move
(overshoot appears below `dampingFraction ≈ 1`, disappears above it); an idea switched to CUSTOM
shows a graph with no visible gap from the dimmed global line until its own sliders move; preview
plays the real tab-switch, selection, and press animations; **COPY PARAMETERS** produces a valid
paste-ready snippet; a decode test against a blob missing a newer field still loads
(tolerant-decode coverage, mirroring `GradientTuningTests`).

Do this stage before A/D/E below — each of those wires its real call site to read from the store
this stage creates, so there's nothing to point them at until it exists.

### Stage A — Staged editor open (Idea 1)

- Wire `matchedGeometryEffect` for `.existingGif`; scale+fade pop for `.newImage`.
- Convert `showControls` from flat fade to per-element staggered move+scale+fade via `.delay()`,
  reading `entranceStagger`/`entranceScale`/`entranceOffsetY` and
  `tuning.effectiveCurve(tuning.entranceCurve)` from `MotionTuningStore` behind
  `motionEntranceKey`, falling back to `Motion.panel` and today's literals when the flag is off.
- `reduceMotion` fallback.

**Gate:** on-device pass on iPhone SE 3 (shortest supported device, per repo precedent in
ROADMAP.md §1a) and one larger device; total time-to-interactive-chrome stays under ~400ms;
repeated rapid taps into the editor don't glitch the matched-geometry zoom.

### Stage B — Save reveal (Idea 2)

- `justSavedIdentifier` on `PhotoManager`.
- `PixelReveal.metal` + `.layerEffect` wiring in `GifGridItem`.
- Trigger sequencing off `isEditorPresented` → `false`.

**Gate:** reveal plays exactly once per save; resolves cleanly (completes or snaps done) if the
user backgrounds the app or enters select mode mid-reveal; no stuck partial-reveal state survives
a second rapid save.

### Stage C — Ambient easter eggs (Idea 3), spike

- Shimmer sweep first — cheaper, no new service, proves the "idle ambient trigger" pattern.
- `MotionService` + accelerometer parallax second, once the idle-trigger pattern is proven.

**Gate:** neither effect fires during active interaction (select mode, pinch, editor open,
backgrounded); both respect `reduceMotion`; a quick Instruments pass confirms `CMMotionManager`
isn't running when the gallery isn't visible.

### Stage D — Category switch + tab selection (Ideas 4, 5), behind the lab

- Consolidate the two competing durations (tap-site 0.2s vs. `controlsSection`'s 0.25s) into one
  animation call, reading `categorySwitchScale` and `tuning.effectiveCurve(tuning.categorySwitchCurve)`
  from the store behind `motionCategorySwitchKey`.
- Add capsule scale-in to `effectCategoryIcon`, reading `tabScaleFrom` and its own explicit
  `.animation(tuning.effectiveCurve(tuning.tabCurve).animation, value: isActive)` behind
  `motionTabScaleKey` — separate from the ambient `withAnimation` driving the state change above,
  so it can diverge once MOTION LAB's tab section goes CUSTOM (see Idea 5's technical approach).

**Gate:** switching categories reads as fast/snappy per the explicit "shouldn't be slow" brief,
confirmed on-device across all four tabs (zoom, face, image, text card layouts); exactly one
animation governs the switch, not two racing ones; undo/redo across a category change still
animates (the non-tap writers at `EditorViewModel.swift:480,639` are covered); under
`reduceMotion`, the scale components collapse to plain cross-fades per this doc's standing rule.

### Stage E — Effect tile press bounce (Idea 6), behind the lab

- New `EffectCardButtonStyle`, reading `tilePressScale`/`tileBrightnessDelta` and
  `tuning.effectiveCurve(tuning.tilePressCurve)` from the store behind `motionTilePressKey`,
  applied to `EffectCardView` in place of `.buttonStyle(.plain)`.

**Gate:** press/release reads as bouncier than `GifGridItem`'s existing press style — a deliberate
difference, confirmed side-by-side on device, not an accidental mismatch; small (64pt) cards on
short devices still feel responsive rather than mushy; under `reduceMotion` the bounce settles
without overshoot (a press-state change is functional feedback, not decoration, so it dampens
rather than disappears — unlike the shimmer/parallax, which skip entirely).

---

## Open questions

1. **Pixel-reveal granularity** — literal per-pixel vs. small blocky cells. Recommend cells
   (cheaper, reads better at grid-thumbnail size, on-brand with the app's pixel-art identity);
   confirm before building.
2. **Does the save-reveal replay on every save**, including re-editing an existing GIF (a
   delete+recreate under the hood), or only first-time saves? Recommend: every save — the
   identifier genuinely changes every time, so "a new item appeared" is accurate every time, not a
   special first-save case.
3. **Shimmer cadence** — "~every 20 seconds" was a rough figure; treat it as a starting point to
   tune during the on-device feel pass in Stage C, not a value to lock into code comments as final.
4. **Parallax magnitude** — confirmed as whole-grid single-transform for v1 rather than per-row
   parallax, both for the "subtle" framing requested and because it's far cheaper. Revisit only if
   the whole-grid version reads as too flat once it's actually on a device.
5. **Does MOTION LAB's scope include Idea 1 and, later, Ideas 2–3's numeric knobs, or stay to just
   4–6?** This doc includes Idea 1 now (same category of "chrome timing," cheap to add as one more
   section) and treats Ideas 2–3's knobs (reveal cell size/duration, shimmer interval, parallax
   magnitude) as additions to make once those are actually built, rather than tuning parameters
   for effects that don't exist in the app yet. Revisit once Stage B/C land.
6. **One `FeatureFlags` toggle per idea vs. one umbrella flag?** This doc recommends one per idea
   (`motionEntranceKey`, `motionCategorySwitchKey`, `motionTabScaleKey`, `motionTilePressKey`),
   matching FACE MARKER LAB's five independent flags — these are unrelated visual changes in
   unrelated parts of the UI, unlike GRADIENT LAB's two genuinely related experiments, so grading
   them together would block shipping one while another is still being tuned.
7. **How faithful is `MotionCurve.displacement(at:)` to SwiftUI's actual spring?** It's a
   closed-form damped-harmonic-oscillator approximation chosen because SwiftUI does not publish
   its internal spring formula — reasonable for *comparing* two settings against each other inside
   the lab, unverified for predicting exact on-device frame timing. Worth a real check before
   trusting the graph over what a device actually shows: capture a few frames of a known
   `response`/`dampingFraction` on device and compare against the sampled curve before shipping
   Stage 0, rather than assuming the approximation is close enough.
8. **Spring only, or a second curve type for direct handle-dragging?** This doc deliberately keeps
   `MotionCurve` a spring (`response`/`dampingFraction`), matching `Design/Motion.swift`'s existing
   one-curve-type discipline for chrome, rather than adding a cubic-bezier timing curve alongside
   it. A bezier is more directly "grab a handle and drag" editable, but it would be a second
   animation vocabulary next to real call sites that use `.spring(...)` everywhere else in the app.
   Flagged rather than decided — revisit if sliders-plus-graph turns out not to feel like "editing
   the curve" once it's actually in front of you.

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Staggered chrome entrance delays perceived responsiveness | Cap total cascade under ~300–400ms; verify on SE 3 |
| Matched-geometry zoom targets a stale grid index after a mid-session re-save reorders the grid | Scope the wiring to the *open* leg only; decide the close leg alongside Idea 2, which replaces it |
| Pixel-reveal shader reads as noise rather than a build-in at small thumbnail size | Use blocky cells, not literal pixels; tune cell size against a real device, not the simulator |
| Reveal state gets stuck if the app backgrounds or a second save lands mid-reveal | Key `justSavedIdentifier` per-identifier; force-complete on interruption |
| Shimmer or parallax fires during active interaction and reads as a bug | Gate both on `scenePhase`, select mode, pinch, and `isEditorPresented`; test explicitly |
| `CMMotionManager` drains battery if left running | Start/stop strictly tied to `GalleryView` visibility and `scenePhase`, verified with Instruments |
| New chrome-entrance curve drifts from the app's one-curve-for-chrome decision | Reuse `Motion.panel`; only add a new named curve in `Motion.swift` for motion that isn't chrome (e.g. the pixel reveal) |
| Two animations already race each other on the category switch (0.2s vs. 0.25s) | Consolidate to one call in Stage D rather than adding a third value on top |
| MOTION LAB drifts from what actually ships, the way a lookalike preview always risks | Preview hosts the real `effectCategoryTabs`/`EffectCarousel`/`EffectCardView`, per `FaceMarkerLabView`'s precedent — never a SwiftUI reconstruction |
| Effect-tile bounce feels mushy on 64pt cards on short devices | Confirm Stage E on an SE 3 specifically, not just a larger simulator |
| `MotionCurveGraphView`'s sampled curve doesn't match what the device actually renders, so tuning by eye on the graph produces a different feel than tuning by eye on the real preview | Preview panels always show the real animated component alongside the graph, never the graph alone; validate the sampling formula against captured on-device timing before Stage 0 ships |
| A per-idea override silently drifts stale if `globalCurve` changes after the override was set | Not a risk under this design — `entranceCurve` etc. are frozen snapshots, not deltas, so only `nil` (inherit) tracks the global; covered by the `MotionTuningTests` case noted above |
| Reveal shader applied to the UIKit-backed animated GIF layer silently does nothing | Shader targets the SwiftUI thumbnail `Image`; animated view stays at opacity 0 until `progress` hits 1 (see Idea 2's technical approach) |
| Grid cell and editor canvas both claim the matched-geometry id while the editor overlay is up | `isSource:` gating in `GifGridItem`, driven off `isEditorPresented` |
| Consolidating the category-switch animation onto the tap site breaks animation for non-tap writers (undo/redo, reset) | The container-level `.animation(_:value:)` is the survivor — it covers `EditorViewModel.swift:480,639` too |
| Graduating `globalCurve` silently retunes `Motion.panel` — and with it presses, panels, and the carousel app-wide | Graduation lands the value as a new named curve in `Motion.swift`; touching `Motion.panel` is a separate deliberate decision (see the graduation boundary note) |

---

## Follow-on opportunities

Once the pixel-reveal shader exists for Idea 2, the same `[[stitchable]]` mechanism is reusable
for other build-in moments the app might want later — e.g. a reveal on first launch's onboarding
carousel, or on the effect-detail panel's thumbnail grid.
