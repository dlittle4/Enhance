import SwiftUI

/// The MAKE A GIF button's animated label: the photo text-effect entrances
/// (`TextAnimationType`) playing live on the button, rotating through the phrases in
/// `ButtonLabelTuning`.
///
/// **This renders through the photo pipeline, not a SwiftUI imitation of it.** Each phrase is
/// laid out and rasterized by `TextRasterizer` exactly as an overlay on a GIF would be, and every
/// frame places those tiles with `TextComposer.transform` — the one matrix the preview and the
/// export already share. What you tune here is therefore the preset itself: a BOUNCE that feels
/// right on the button is the same BOUNCE users get on their photos.
///
/// The label's colour is deliberately not a knob. The raster is drawn white and
/// `.colorMultiply`ed with whatever `GradientTuning.labelColor` measures against the button's
/// gradient at this instant, so the animated label inherits the contrast machinery — auto
/// black/white, per-instant, crossfaded — that the plain label already trusts
/// *(user's call, 2026-08-26)*.
struct AnimatedButtonLabel: View {

    /// Must match the role of the `ButtonGradientBackground` this label sits on, for the same
    /// reason `GradientButtonLabel` says so: the contrast answer is a function of the ground
    /// actually behind the glyphs.
    var role: GradientTuning.ButtonRole = .primary

    /// Glyph size in points. Defaults to the plain label's `.silkscreenButtonLabel` size, so
    /// toggling the experiment off and on does not resize the text.
    var pointSize: CGFloat = 16

    /// What the button says when the lab has emptied the rotation down to blanks — the flag being
    /// on must never leave the primary CTA wordless.
    var fallbackText: String = "MAKE A GIF"

    @ObservedObject private var store = ButtonLabelTuningStore.shared
    @ObservedObject private var gradientStore = GradientTuningStore.shared
    @AppStorage(FeatureFlags.staticGradientKey) private var staticOn = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherOn = false
    @Environment(\.displayScale) private var displayScale

    /// A class, not view state that invalidates: rebuilding rasters is keyed off the appearance
    /// inside the draw pass, and the `TimelineView` is already redrawing every tick — publishing
    /// the cache would only add a second, redundant invalidation path.
    @State private var cache = ButtonLabelRasterCache()

    var body: some View {
        if store.tuning.activePhrases.isEmpty {
            // Rendered the way the flag-off path renders, treatment and all, so an emptied lab
            // degrades to exactly the button the app ships rather than to a blank capsule.
            Text(fallbackText)
                .font(.silkscreenButtonLabel)
                .gradientButtonLabel(role: role)
        } else {
            animatedLabel
        }
    }

    private var animatedLabel: some View {
        // 40Hz is plenty for entrances that run the better part of a second, at a fraction of
        // the display-rate updates `.animation` would default to.
        TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let tuning = store.tuning

            Canvas { context, size in
                let phase = tuning.phase(at: now)
                let entries = cache.entries(for: tuning, pointSize: pointSize,
                                            size: size, scale: displayScale)
                guard entries.indices.contains(phase.phraseIndex) else { return }
                let entry = entries[phase.phraseIndex]

                // The lab's parameter, direction and origin land on the overlay at draw time:
                // none of them change the raster (the same split the editor's appearance key
                // documents), so a slider drag re-poses tiles rather than re-rendering text.
                var overlay = entry.overlay
                overlay.tuning = CGFloat(tuning.parameter)
                overlay.slideDirection = tuning.slideDirection
                overlay.gridOrigin = tuning.gridOrigin

                draw(context: context, size: size, overlay: overlay,
                     raster: entry.raster, phase: phase)
            }
            // White raster × label colour = the label colour, with the same 0.35s crossfade
            // `GradientButtonLabel` uses to hide the black/white step at the pulse's crossover.
            .colorMultiply(labelColor(at: now))
            .animation(.easeInOut(duration: 0.35), value: labelColor(at: now))
        }
        // SLIDE and friends travel beyond the resting box on their way in; the button's edge is
        // the mask that makes that read as a reveal rather than as text spilling over the bar.
        .clipped()
    }

    // MARK: - Colour

    /// `GradientButtonLabel`'s decision, re-stated here because that modifier answers with
    /// `.foregroundColor` — which cannot reach into a `Canvas` — while this view needs the same
    /// answer as a multiply colour. The maths is the shared `GradientTuning`, so the two labels
    /// cannot disagree about what readable means.
    private func labelColor(at time: TimeInterval) -> Color {
        let quantized = ButtonGradientStyle
            .resolve(staticOn: staticOn, ditherOn: ditherOn, tuning: gradientStore.tuning)
            .isQuantized
        guard quantized else { return .textOnGradient }
        return gradientStore.tuning.labelColor(at: time, role: role)
    }

    // MARK: - Drawing

    /// One frame: the compositor's tile loop, drawn into the Canvas's CGContext.
    ///
    /// This mirrors `TextTileCompositor.composite` deliberately, sharing `repeatOffsets`,
    /// `tiledCopyState` and `TextComposer.transform` with it — the placement logic is never
    /// duplicated, only the destination differs. The Canvas context is already top-left like the
    /// compositor's flipped context, so the per-tile code carries over verbatim, including each
    /// image's own local flip.
    private func draw(context: GraphicsContext, size: CGSize, overlay: TextOverlay,
                      raster: RasterizedText, phase: ButtonLabelPhase) {
        guard phase.alpha > 0.001 else { return }
        // `withCGContext` is mutating; a local copy of the value-type context keeps this helper's
        // signature honest about not changing the caller's.
        var context = context

        // The pipeline lays out against a square; the button is a wide band. The square's side is
        // the button's long side, centred on the short one, so `fontSize` and every travel
        // distance stay normalized against a length that exists on screen.
        let outputSide = max(size.width, size.height)

        let states = overlay.animation.tileStates(at: phase.progress, layout: raster.layout,
                                                  tuning: overlay.tuning,
                                                  direction: overlay.slideDirection)
        guard !states.isEmpty else { return }

        let repeats = TextTileCompositor.repeatOffsets(for: overlay, raster: raster,
                                                       outputSide: outputSide)

        // GRID fills its whole square with copies, but the button shows only a short band of it —
        // cull the rows that can never intersect the visible strip before paying to draw them.
        let inkHalfHeight = raster.pixelSide > 0
            ? raster.layout.inkBounds.height * (outputSide / raster.pixelSide) / 2
            : 0
        let visibleHalfBand = size.height / 2 + inkHalfHeight + outputSide * 0.1

        context.withCGContext { cg in
            cg.translateBy(x: (size.width - outputSide) / 2,
                           y: (size.height - outputSide) / 2)
            // Same choice as the compositor, for the same reason: nearest would alias POP's
            // overshoot, and the supersampled master keeps `.high` from going soft.
            cg.interpolationQuality = .high

            for tile in raster.tiles {
                guard tile.slotIndex >= 0, tile.slotIndex < states.count else { continue }
                let state = states[tile.slotIndex]
                guard state.alpha > 0.001 else { continue }

                for repeated in repeats {
                    guard abs(repeated.offset.y) <= visibleHalfBand else { continue }

                    let copy = overlay.animation.tiledCopyState(
                        normalizedRow: repeated.row, at: phase.progress,
                        tuning: overlay.tuning, origin: overlay.gridOrigin
                    )
                    let alpha = state.alpha * copy.alpha * phase.alpha
                    guard alpha > 0.001 else { continue }

                    var composed = state
                    composed.translationDelta = CGPoint(
                        x: state.translationDelta.x + copy.translationDelta.x,
                        y: state.translationDelta.y + copy.translationDelta.y
                    )

                    cg.saveGState()
                    cg.setAlpha(alpha)
                    cg.translateBy(x: repeated.offset.x, y: repeated.offset.y)
                    cg.concatenate(TextComposer.transform(
                        tile: tile, state: composed, overlay: overlay,
                        raster: raster, outputSide: outputSide
                    ))
                    let rect = TextComposer.localRect(for: tile, raster: raster)
                    cg.translateBy(x: rect.minX, y: rect.maxY)
                    cg.scaleBy(x: 1, y: -1)
                    cg.draw(tile.image, in: CGRect(origin: .zero, size: rect.size))
                    cg.restoreGState()
                }
            }
        }
    }
}

// MARK: - Raster cache

/// The prepared rasters for the current rotation, rebuilt only when something that changes the
/// *pixels* moves — phrases, preset granularity, size — never on a parameter drag or a clock tick.
/// The same split `TextOverlayHostView.appearanceKey` documents for the editor canvas.
final class ButtonLabelRasterCache {

    struct Entry {
        /// The overlay the raster was built from. Draw-time fields (parameter, direction,
        /// origin) are overwritten by the renderer each frame; everything baked into the master
        /// is fixed here.
        let overlay: TextOverlay
        let raster: RasterizedText
    }

    private var key = ""
    private var entries: [Entry] = []

    /// Rasterizes synchronously on first use of a new key. That is a few square rasters at button
    /// resolution — the same order of work `TextOverlayHostView.update` already does on the main
    /// thread per keystroke in the editor — and it happens once per appearance change, not per
    /// frame.
    func entries(for tuning: ButtonLabelTuning, pointSize: CGFloat,
                 size: CGSize, scale: CGFloat) -> [Entry] {
        let outputSide = max(size.width, size.height)
        guard outputSide > 0, scale > 0 else { return [] }

        let phrases = tuning.activePhrases
        // U+1F is an information separator, not something anyone types on a button.
        let newKey = phrases.joined(separator: "\u{1F}")
            + "|\(tuning.animation.rawValue)|\(pointSize)|\(Int(outputSide))|\(Int(scale))"
        if newKey != key {
            entries = phrases.compactMap { phrase in
                var overlay = TextOverlay.makeDefault(animation: tuning.animation, text: phrase,
                                                      seed: Self.seed(for: phrase))
                // The plain label is Silkscreen Regular at 16pt (`.silkscreenButtonLabel`);
                // matching face and size is what keeps the flag toggle from resizing the button's
                // voice. White fill — colour is applied by the renderer's multiply.
                overlay.font = .silkscreenRegular
                overlay.color = .white
                overlay.fontSize = pointSize / outputSide

                guard let raster = TextRasterizer.prepare(overlay: overlay,
                                                          pixelSide: outputSide * scale) else {
                    return nil
                }
                return Entry(overlay: overlay, raster: raster)
            }
            key = newKey
        }
        return entries
    }

    /// FNV-1a of the phrase, so FLICKER's jitter is deterministic per phrase rather than
    /// reshuffling every time the cache rebuilds. Same recipe as `GalleryView.cellDepth`, and for
    /// the same reason: a stored random seed has nowhere to live for a label that is not a model.
    private static func seed(for phrase: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in phrase.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return hash
    }
}
