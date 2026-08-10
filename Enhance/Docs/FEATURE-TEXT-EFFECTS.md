# Animated text overlays — product and implementation plan

> Status: proposed. No production code written.
>
> Scope: let a user add one text overlay to a photo, position and style it, and animate its
> entrance in sync with the existing zoom animation when the GIF is generated.

---

## 1. Executive recommendation

Ship a deliberately small first version: **one text layer, five entrance presets, direct
drag-to-position, and a compact style editor**. Text should be anchored to the 600×600 output
frame rather than to source-image pixels, so it remains readable while the photo moves beneath
it. Every preset consumes the same normalized `progress` value as the zoom animator, settles by
roughly 70% of the moving portion, and remains fully visible during the pause.

Treat text as its own overlay pass, not as a `VisualEffect`. The current generator has a useful
three-stage order:

1. face effects on the source image;
2. zoom transform and frame crop;
3. visual effects on the transformed frame.

Animated text becomes stage 4. This gives it predictable coordinates, keeps it crisp, prevents
image filters from degrading the lettering, and avoids changing any existing effect protocol.

The first release should optimize for the quick, preset-led interaction used by social creation
apps rather than expose keyframes or a timeline. Instagram's implementation is especially
relevant: it pairs text styles with decorated variants and includes word- and character-level
reveals, while explicitly accounting for emoji, ligatures, and right-to-left languages. Canva,
Adobe Express, and CapCut similarly lead with named animation presets and offer style controls
after selection.

Sources:

- [Meta Engineering — Building text animations for Instagram Stories](https://engineering.fb.com/2022/07/18/developer-tools/building-text-animations-for-instagram-stories/)
- [Canva — Text animations](https://www.canva.com/features/text-animations/)
- [Adobe Express — Animate designs](https://helpx.adobe.com/express/web/audio-and-animation/animate-design.html)
- [CapCut — Add text to video](https://www.capcut.com/tools/add-text-to-video)

---

## 2. Product principles

- **Preset first.** A user should be able to type, position, choose an effect, and generate in
  under 20 seconds.
- **The text and zoom feel choreographed.** They share time, but text is not scaled by the image
  transform. The image can rush toward the viewer while the title independently pops, rises, or
  types into place.
- **The final message is readable.** All entrance motion finishes before the pause frames, and
  the pause always contains the complete text.
- **Preview and export use one animation definition.** SwiftUI may present the live overlay, but
  both preview and GIF rendering must read the same pure `state(at:)` evaluator.
- **Language correctness is part of V1.** Never split a Swift `String` by UTF-16 offsets or plain
  spaces. Emoji, composed characters, ligatures, multiline text, and right-to-left layout must
  remain intact.
- **No hidden timeline.** Duration is derived from the GIF's moving portion. Expose an
  `ENTRANCE` timing control only after the presets feel good at their defaults.

---

## 3. V1 user experience

### Entry point

Add a fourth editor category, **TEXT**, beside Zoom, Face, and Image. Use a simple bundled `T`
icon that matches the existing monochrome category icons.

When TEXT is opened with no overlay, the carousel begins with an **ADD TEXT** card followed by
the five animation presets. Tapping ADD TEXT opens a focused text editor and keyboard. Tapping a
preset with no text should open the same editor with that preset already selected; this removes
an unnecessary dead end.

### Text editing

Use a keyboard-safe sheet or dedicated editor state rather than squeezing a text field into the
existing effect detail panel. It contains:

- a multiline text field, limited to 120 extended grapheme clusters and three rendered lines;
- font choices: Silkscreen Regular, Silkscreen Bold, System Rounded, System Serif, and System
  Condensed (all local/system fonts; no licensing or download dependency);
- a small high-contrast colour palette: white, black, mint, pink, yellow, and blue;
- decoration: **NONE**, **SHADOW**, **BLOCK**, and **OUTLINE**;
- size and alignment controls;
- Cancel and Done, using the same edit-session semantics as the existing effect panel.

Keep animation selection in the horizontal card carousel. This separates “what it says and how
it looks” from “how it enters,” and prevents a single cramped panel from mixing both concepts.

### Canvas interaction

While the TEXT category is active and an overlay exists:

- render the text directly over `ImageCanvasView`;
- tapping the text selects it and reopens the style editor;
- dragging the text moves it; dragging elsewhere continues to pan the photo;
- store the text centre in normalized output coordinates (`0...1`) and clamp its measured bounds
  to a 24-point safe margin;
- show a light selection outline only while editing; it never enters the GIF;
- provide a delete action in the text editor and make RESET clear the overlay too.

V1 deliberately omits rotation, pinch-to-resize, multiple layers, per-word styling, custom
motion paths, and independent in/out timing. Size is a slider; this avoids gesture conflict with
the already pinchable photo canvas.

### Regeneration behavior

Typing and dragging update the local preview immediately but do not regenerate a GIF on every
event. Regenerate only on meaningful commit points:

- Done from the text/style editor;
- drag end;
- animation preset selection;
- undo, redo, reset, or delete.

For an already-generated or existing GIF, use the current regeneration guard and show the
existing regenerating overlay. For a new image before ENHANCE, no background GIF work is needed.

---

## 4. Entrance preset set

All curves consume normalized moving-frame progress `p` from `0...1`. Define a shared entrance
window `q = clamp(p / 0.70, 0, 1)` so every preset is complete before the final 30% of motion and
before all pause frames. Use a pure value type such as `TextAnimationState` containing opacity,
scale, translation, rotation, and reveal progress.

| Preset | Behavior | Default curve | Why it belongs in V1 |
|---|---|---|---|
| **POP** | Fade from 0, scale 0.55 → 1.08 → 1 | spring-like overshoot | The expressive default; complements zoom without duplicating it |
| **RISE** | Move upward ~48 output pixels while fading in | cubic ease-out | Familiar, legible, and works for multiline text |
| **TYPE** | Reveal by extended grapheme cluster with a blinking block cursor | stepped reveal | Direct Instagram inspiration and a strong fit for the pixel font |
| **WORD DROP** | Reveal linguistic word tokens in sequence with a short downward settle | staggered ease-out | More energetic than Type while still readable |
| **FLICKER** | Resolve from 2–3 deterministic opacity/chromatic-offset flashes to stable text | damped deterministic pulses | Matches Enhance's glitch/pixel personality |

The effects are entrance-only. Do not add a looping wiggle or pulse in V1: motion during the
pause makes the message harder to read, increases GIF entropy/file size, and complicates the
promise that the final state is stable.

Use deterministic functions of `progress` and a stable overlay seed. Never call random APIs in
the frame loop, or preview and export will disagree and repeated generations will differ.

---

## 5. Data model

Add models under `Enhance/Models/Text/`:

```swift
struct TextOverlay: Equatable {
    var text: String
    var center: CGPoint             // normalized output-frame coordinates
    var width: CGFloat              // normalized maximum layout width
    var font: TextFont
    var fontSize: CGFloat           // normalized against the 600px output
    var color: TextColor
    var alignment: TextAlignment
    var decoration: TextDecoration
    var animation: TextAnimationType
}

enum TextAnimationType: String, CaseIterable, Identifiable {
    case pop, rise, type, wordDrop, flicker

    func state(at progress: CGFloat, layout: PreparedTextLayout) -> TextAnimationState
}
```

Keep colours as a small semantic enum in V1, with UIKit and SwiftUI projections, as
`LaserColor` does today. Avoid storing `SwiftUI.Color` in snapshots; the project already records
the equality and persistence problems that creates for `GradientStops`.

Add `textOverlay: TextOverlay?` to `EditorSnapshot` and `EditorViewModel`. Include it in
`currentSnapshot`, `restore`, `resetEffects`, `hasNonDefaultSettings`, the generate/regenerate
calls, and the rule that allows effects-only generation at 1× zoom. A non-empty text overlay is
itself sufficient reason to generate.

Use a draft copy while the text sheet is open. Cancel restores the entry snapshot; Done records
one undo entry for the entire visit. During a drag, capture one pre-drag snapshot and commit one
history entry at drag end.

V1 retains the app's current baked-GIF behavior: after leaving the editor and reopening a saved
GIF, the original editable recipe is not reconstructed. The first frame of every entrance must
therefore contain no visible text, which also prevents the baked title from being duplicated
when that frame is later used as the source image. Full recipe persistence should be designed
for all effect families together, not added as a text-only metadata format.

---

## 6. Rendering architecture

### Protocol boundary

Extend `GIFGenerating.generateGIF` with `textOverlay: TextOverlay?`. Update both test stubs in
the same change; they are intentionally compile-time witnesses for this boundary.

In `GIFGenerator`, prepare text once before either frame loop:

```swift
let textPass = textRenderer.prepare(overlay: textOverlay, outputSize: context.outputSize)
```

Then change each path from:

```text
source → face effects → zoom/crop → visual effects → GIF frame
```

to:

```text
source → face effects → zoom/crop → visual effects → text overlay → GIF frame
```

Pause frames use `progress = 1`, so the renderer receives the complete, stable text state.

### `TextOverlayRenderer`

Create `Enhance/Services/Text/TextOverlayRenderer.swift` with two responsibilities:

1. **Prepare:** resolve font, attributed string, paragraph direction/alignment, line wrapping,
   glyph/token ranges, decoration geometry, tight bounds, and any reusable bitmaps.
2. **Composite:** draw the already-prepared layout over one 600×600 base frame using the
   animation state's alpha/transform/reveal mask.

Do not rebuild attributed strings, tokenize words, or measure lines inside the GIF frame loop.
The prepared pass should be immutable and safe to use from the generator's background queue.

Render text after the Core Image visual-effect pass using a `UIGraphicsImageRenderer` or Core
Graphics context at an explicit scale of 1 for the 600×600 pixel target. Pre-render glyphs at
the maximum scale required by POP's overshoot so its sharpest frame is not upscaling a smaller
bitmap. Draw decoration behind glyphs in the same prepared coordinate space.

### Correct text segmentation

- TYPE advances over extended grapheme clusters, not UTF-16 code units.
- WORD DROP uses Apple's `NaturalLanguage` word tokenizer, not `split(separator: " ")`.
- Keep one stable full-string layout so partial reveals do not reflow lines between frames.
- Use the resolved paragraph base direction and alignment for RTL strings.
- Test emoji sequences, combining marks, Arabic/Persian shaping, and mixed RTL/LTR text.

This follows the failure modes documented by Meta's Instagram team: simple character offsets
and space splitting break ligatures, emoji, and right-to-left text.

### Coordinate contract

The text renderer works only in output-frame coordinates:

- `center`, `width`, and `fontSize` are normalized and resolved against `outputSize`;
- `(0, 0)` is top-left in the editor and renderer;
- text is composited after the zoom transform, so it never uses `visibleRect`, `drawRect`, or
  `FrameGeometry`;
- the live SwiftUI overlay uses the same normalized values against the 325-point canvas.

Add unit tests for the 325→600 conversion and for clamping measured text bounds to the safe
area. This contract is what prevents preview/export drift.

---

## 7. Preview architecture

Create a lightweight `TextOverlayView` over `ImageCanvasView`. It should accept the model,
canvas size, selection state, and normalized animation progress.

For the pre-generation canvas, a short `TimelineView(.animation)` can loop only the selected
text entrance while the TEXT category is active. Pause when the category is left, Reduce Motion
is enabled, or the keyboard/style editor is open. Once a GIF exists, the existing
`GIFPreviewView` remains authoritative; do not stack a second live overlay over the baked GIF.

The SwiftUI view and Core Graphics renderer may use different drawing APIs, but they must share:

- font identifiers and normalized sizing;
- line width, line limit, alignment, colour, and decoration metrics;
- `TextAnimationType.state(at:)`;
- normalized coordinate conversion.

Add snapshot/reference-image tests at progress `0`, `0.35`, `0.70`, and `1` for every preset.
The goal is semantic and geometric parity; small antialiasing differences between SwiftUI and
Core Graphics are acceptable.

---

## 8. Implementation stages

### Stage A — animation spike and visual sign-off

- Build the five `state(at:)` evaluators and a temporary in-app/prototype grid using one short
  phrase over the same zooming photo.
- Review each preset at slow/default/fast zoom and with 0/1/5-second pauses.
- Confirm the selected defaults settle by 70% and the first frame has zero visible text.
- Measure representative GIF sizes against the same image without text. Set the performance
  budget from this evidence before production integration.

**Exit:** approved preset curves and names, deterministic output, and no preset that fights the
photo zoom.

### Stage B — model and renderer foundation

- Add `TextOverlay`, style enums, animation state/evaluators, and prepared-layout types.
- Implement normalization, safe-area clamping, line wrapping, decoration drawing, and Core
  Graphics compositing in isolation.
- Add language, coordinate, curve-boundary, and pixel-output tests.

**Exit:** a static base image plus any overlay can be rendered correctly at arbitrary progress
without the editor or GIF generator.

### Stage C — GIF pipeline integration

- Extend `GIFGenerating` and its stubs.
- Prepare one text pass per generation and composite it after visual effects in animated and
  pause frames.
- Pass overlay state through `EditorViewModel.generateGIF` and `regenerateGIF`.
- Include text in `hasNonDefaultSettings`, effects-only generation validation, reset, undo/redo,
  and regeneration commit points.

**Exit:** generated GIFs show every preset, hold the full text during the pause, and generate
unchanged output when `textOverlay == nil`.

### Stage D — editor UX

- Add the TEXT category, icon, animation carousel, style editor, and delete action.
- Add live canvas rendering, hit testing, drag-to-position, safe-area clamping, and selection
  chrome.
- Apply keyboard-safe layout and Reduce Motion behavior.
- Add accessibility labels, values, and non-drag position controls for VoiceOver.

**Exit:** a user can add, edit, move, preview, undo, delete, reset, generate, save, and share
text without losing existing zoom/effect settings.

### Stage E — hardening and release gate

- Run the complete existing suite plus the new text tests.
- Test 1×/maximum zoom, every animator and modifier, visual/face effects, and each pause speed.
- Test short/long/multiline text, emoji, combining marks, Arabic/Persian, mixed direction, and
  Dynamic Type/large keyboard settings.
- Profile generation time, peak memory, and GIF byte size on the oldest supported device class.
- Verify text is crisp at POP's overshoot and identical across repeated generations.

**Exit:** acceptance criteria below pass and no regression occurs when no text is selected.

---

## 9. Test plan

### Unit tests

- every preset returns finite values and exact stable endpoints at progress 0 and 1;
- values outside `0...1` clamp safely;
- FLICKER is deterministic for the same overlay seed;
- TYPE never splits an extended grapheme cluster;
- WORD DROP preserves linguistic word tokens and full layout geometry;
- normalized position and size map identically at 325 and 600 points;
- clamping keeps measured bounds inside the safe area;
- snapshots, undo/redo, reset, and non-default detection include text;
- empty/whitespace-only drafts do not count as active overlays;
- a text-only edit can generate at 1× zoom.

### Renderer and GIF tests

- `textOverlay == nil` remains byte-stable against the prior generator for a fixed fixture;
- progress 0 has no text pixels and progress 1 contains the full overlay;
- pause frames are visually identical to the final moving frame;
- text remains above each visual effect and is not colour-shifted or blurred by it;
- line wrapping and alignment are stable throughout partial reveals;
- generated frame count and delays are unchanged by adding text;
- repeated generation with the same inputs produces the same rendered frames.

### UI tests

- add text → select preset → drag → generate → save/share;
- canceling an edit restores prior text and style;
- Done creates one undo step; one undo removes a newly added overlay;
- delete and RESET remove the live and generated overlay;
- opening the keyboard on a short device leaves the text field and Done visible;
- dragging text does not pan the photo, while dragging elsewhere still does;
- switching categories keeps the overlay and stops its local preview loop.

---

## 10. Accessibility and safety

- Respect Reduce Motion in the editor preview by showing the completed text state. The exported
  GIF may retain the chosen effect because it is authored media, but the choice should be
  explicit and previewable as a still.
- Give animation cards descriptive VoiceOver labels such as “Rise, text fades in while moving
  upward,” not only their names.
- Provide position buttons or an accessibility adjustable action so placement does not require
  drag gestures.
- Enforce a contrast floor for BLOCK and OUTLINE styles. NONE and SHADOW may warn, but should not
  silently change the user's selected colour.
- Keep the text editor local and offline; the feature needs no permissions or network service.

---

## 11. Acceptance criteria

- A user can create one 1–3 line text overlay, style it, drag it anywhere inside the safe area,
  and choose one of five entrance effects.
- The live preview and exported GIF agree on placement, wrapping, size, colour, decoration, and
  animation timing.
- Text entrance is synchronized to the zoom's moving frames, complete by 70%, and fully visible
  in every pause frame.
- Emoji, composed characters, multiline alignment, and tested RTL strings render without broken
  glyphs or mid-animation reflow.
- Undo/redo, Cancel/Done, RESET, regeneration, save, and share all include text state.
- With no text overlay, rendering behavior and output remain unchanged.
- Generation stays within the performance and file-size budgets established in Stage A.

---

## 12. Deliberately deferred

- multiple independently timed text layers;
- rotation and pinch-resize gestures;
- per-word fonts or colours, mentions, hashtags, and rich text spans;
- custom keyframes, motion paths, separate In/Out/Loop animations, or a timeline;
- text that tracks a face or source-image feature through the zoom;
- curved, 3D, particle, or generative text effects;
- reconstructing editable text/effect recipes after a saved GIF is reopened.

The clean follow-on after V1 is **multiple layers plus a layer list**, not more presets. That is
the point at which independent timing and ordering become necessary; adding those concepts to a
single-layer release would make the first interaction much heavier without validating demand.
