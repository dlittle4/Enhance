import CoreGraphics
import UIKit

/// Where a tile goes, for both the live preview and the GIF export.
///
/// **Neither compositor may compute its own matrix.** The export draws with the transform this
/// returns; the preview converts it with `CATransform3DMakeAffineTransform`. That is what makes
/// preview/export parity a property of the code's shape rather than a list of invariants two
/// drawing paths are asked to honour — LEARNINGS 2026-08-07 and 2026-08-09 both record what
/// happens when two paths are merely *expected* to agree.
enum TextComposer {

    /// The full placement transform for one tile at one instant.
    ///
    /// Read top to bottom, this is: pivot to the tile's own centre, apply the preset's local scale
    /// and rotation, undo the raster's deliberate oversize, apply the user's resting rotation, move
    /// to the overlay's place in the frame, then apply the preset's screen-space translation.
    ///
    /// The order is the contract. Translation lands *after* rotation so it stays in output space —
    /// a 90°-rotated title that RISEs still moves up the screen. Scale and rotation land *before*
    /// it so they stay local — the same title still scales about itself.
    ///
    /// - Parameters:
    ///   - liveScale: the preview's in-flight pinch factor. Defaulted to 1 so the export path
    ///     cannot pass it even by accident; `exportPath_neverAppliesLiveScale` asserts that.
    static func transform(tile: TextTile,
                          state: TextTileState,
                          overlay: TextOverlay,
                          raster: RasterizedText,
                          outputSide: CGFloat,
                          liveScale: CGFloat = 1.0) -> CGAffineTransform {
        // Raster pixels → output units. This already divides out the supersample the rasterizer
        // deliberately added, which is why no separate `1/peakScale` term appears below.
        let rasterToOutput = outputSide / (raster.pixelSide * raster.supersample)

        let centre = CGPoint(x: overlay.center.x * outputSide,
                             y: overlay.center.y * outputSide)
        let translation = CGPoint(x: state.translationDelta.x * outputSide,
                                  y: state.translationDelta.y * outputSide)

        var m = CGAffineTransform(translationX: -tile.localCentre.x, y: -tile.localCentre.y)
        m = m.concatenating(CGAffineTransform(scaleX: state.scaleDelta, y: state.scaleDelta))
        m = m.concatenating(CGAffineTransform(rotationAngle: state.rotationDelta))
        m = m.concatenating(CGAffineTransform(translationX: tile.localCentre.x,
                                              y: tile.localCentre.y))
        let toOutput = rasterToOutput * liveScale
        m = m.concatenating(CGAffineTransform(scaleX: toOutput, y: toOutput))
        m = m.concatenating(CGAffineTransform(rotationAngle: overlay.angle))
        m = m.concatenating(CGAffineTransform(translationX: centre.x + translation.x,
                                              y: centre.y + translation.y))
        return m
    }

    /// Where a tile's own rect sits before the transform, relative to the block centre.
    ///
    /// Split out because the export draws into a rect while the preview positions a layer, and
    /// both need the same untransformed geometry.
    static func localRect(for tile: TextTile, raster: RasterizedText) -> CGRect {
        CGRect(x: tile.pixelRect.minX - raster.centre.x,
               y: tile.pixelRect.minY - raster.centre.y,
               width: tile.pixelRect.width,
               height: tile.pixelRect.height)
    }
}

/// Composites a prepared text pass over one rendered frame.
///
/// This is stage 4 of the generator: `source → face effects → zoom/crop → visual effects → text`.
/// It takes a `CGImage` and returns a `CGImage`, so it splices into `GIFGenerator` without
/// touching the `VisualEffect` protocol or any of its implementations.
enum TextTileCompositor {

    /// Offsets to draw each tile at, in output units.
    ///
    /// One entry — the origin — for every preset but TICKER and GRID, so the common path is
    /// unchanged and costs nothing. TICKER gets a horizontal run so the band never shows an empty
    /// gap sweeping past; GRID gets both axes so the text becomes a texture. Both cover the frame
    /// plus a margin, since the block is drawn from its centre and a copy straddling the edge still
    /// has to appear.
    private static func repeatOffsets(for overlay: TextOverlay, raster: RasterizedText,
                                      outputSide: CGFloat) -> [(offset: CGPoint, row: CGFloat)] {
        let animation = overlay.animation
        guard animation.tiling != .single else { return [(.zero, 0)] }

        let stepX = animation.repeatStep(in: raster.layout, tuning: overlay.tuning) * outputSide
        guard stepX > 1 else { return [(.zero, 0)] }
        let columns = Int((outputSide / stepX).rounded(.up)) + 1

        guard animation.tiling == .grid else {
            return (-columns...columns).map { (CGPoint(x: CGFloat($0) * stepX, y: 0), 0) }
        }

        let stepY = animation.rowStep(in: raster.layout, tuning: overlay.tuning) * outputSide
        guard stepY > 1 else {
            return (-columns...columns).map { (CGPoint(x: CGFloat($0) * stepX, y: 0), 0) }
        }
        let rows = Int((outputSide / stepY).rounded(.up)) + 1

        // Bounded so a tiny font cannot ask for thousands of draws — at that point the frame is a
        // solid block of ink and more copies add nothing but time.
        let maxCopies = 600
        var offsets: [(offset: CGPoint, row: CGFloat)] = []
        offsets.reserveCapacity(min(maxCopies, (columns * 2 + 1) * (rows * 2 + 1)))
        for row in -rows...rows {
            for column in -columns...columns {
                guard offsets.count < maxCopies else { return offsets }
                // 0 at the topmost row, 1 at the bottom, so a preset can fill downward without
                // knowing how many copies there are.
                let normalizedRow = CGFloat(row + rows) / CGFloat(max(1, rows * 2))
                offsets.append((CGPoint(x: CGFloat(column) * stepX, y: CGFloat(row) * stepY),
                                normalizedRow))
            }
        }
        return offsets
    }

    /// Draws the overlay over `base` at a normalized progress.
    ///
    /// Returns `base` unchanged when there is nothing to draw, so the no-overlay path stays
    /// byte-identical to the generator's output before this existed.
    static func composite(_ raster: RasterizedText,
                          overlay: TextOverlay,
                          progress: CGFloat,
                          over base: CGImage) -> CGImage {
        let width = base.width, height = base.height
        guard width > 0, height > 0 else { return base }

        // The preset's controls ride on the overlay, so the preview and the GIF read the same values.
        let states = overlay.animation.tileStates(at: progress, layout: raster.layout,
                                                  tuning: overlay.tuning,
                                                  direction: overlay.slideDirection)
        guard !states.isEmpty else { return base }

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: full)

        // Match the generator's frame context: `UIGraphicsBeginImageContextWithOptions(size,
        // false, 1.0)` is top-left, and the layout is top-left, so flip once here and let every
        // coordinate downstream stay in one orientation.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // Silkscreen is a pixel font, so a non-integer downscale of a supersampled raster is the
        // one place this feature can look soft. High interpolation is right for the ~7% POP
        // overshoot; nearest would alias it.
        context.interpolationQuality = .high

        let outputSide = CGFloat(min(width, height))

        // TICKER tiles the block across the frame so the band reads as continuous; every other
        // preset draws one copy. The step is the same number the preset travels, which is what
        // makes the settled frame identical to the start of the scroll.
        let repeats = Self.repeatOffsets(for: overlay, raster: raster, outputSide: outputSide)

        for tile in raster.tiles {
            guard tile.slotIndex >= 0, tile.slotIndex < states.count else { continue }
            let state = states[tile.slotIndex]
            guard state.alpha > 0.001 else { continue }

            for repeat_ in repeats {
                // Per-copy choreography, composed on top of the tile's own state. The preset owns
                // both halves; the compositor only multiplies them together.
                let copy = overlay.animation.tiledCopyState(normalizedRow: repeat_.row,
                                                            at: progress, tuning: overlay.tuning,
                                                            origin: overlay.gridOrigin)
                let alpha = state.alpha * copy.alpha
                guard alpha > 0.001 else { continue }

                var composed = state
                composed.translationDelta = CGPoint(
                    x: state.translationDelta.x + copy.translationDelta.x,
                    y: state.translationDelta.y + copy.translationDelta.y
                )

                context.saveGState()
                context.setAlpha(alpha)
                context.translateBy(x: repeat_.offset.x, y: repeat_.offset.y)
                context.concatenate(TextComposer.transform(
                    tile: tile, state: composed, overlay: overlay,
                    raster: raster, outputSide: outputSide
                ))
                // `context` is flipped to top-left, so each image needs its own local flip to land
                // the same way up as it was cut. Standard form: move to the box's bottom-left in
                // the flipped space, invert y, then draw at the origin.
                let rect = TextComposer.localRect(for: tile, raster: raster)
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(tile.image, in: CGRect(origin: .zero, size: rect.size))
                context.restoreGState()
            }
        }

        return context.makeImage() ?? base
    }
}
