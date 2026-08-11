import CoreGraphics
import CoreText
import UIKit

/// Where a tile came from.
enum TileOrigin: Sendable {
    /// A cut of the master raster. These partition the master exactly.
    case cut
    /// Drawn separately — only the TYPE cursor, which has no glyph behind it.
    case synthetic
}

/// One piece of the rendered text.
///
/// Deliberately **not** `Sendable`: it holds a `CGImage`, whose conformance varies by SDK, and the
/// prepared pass is handed to the generator's queue as a whole rather than piecewise.
struct TextTile {
    /// Index into the array `TextAnimationType.tileStates` returns.
    let slotIndex: Int

    /// A crop of the master, sharing its backing store — `CGImage.cropping(to:)` does not copy
    /// pixels, so a hundred-odd tiles cost about nothing beyond the one master.
    let image: CGImage

    /// Placement in raster-pixel space, top-left origin, always integral.
    let pixelRect: CGRect

    /// This tile's own pivot for local scale and rotation, relative to the block centre. Per-tile
    /// rather than per-block: scaling a word about the *block's* centre would also translate it
    /// outward, turning WORD DROP's settle into an explosion.
    let localCentre: CGPoint

    let origin: TileOrigin
}

/// The master raster plus its tiles.
struct RasterizedText {
    let layout: PreparedTextLayout

    /// The whole decorated block, drawn once. Retained because every `.cut` tile is a view onto it.
    let master: CGImage

    /// Non-overlapping and exhaustive. Compositing all of them at rest reproduces `master` byte
    /// for byte, which is the single assertion the architecture rests on.
    let tiles: [TextTile]

    /// Side of the square raster, in pixels, before supersampling.
    let pixelSide: CGFloat

    let granularity: TextTileGranularity

    /// How much larger than resting size the master was drawn, so the transform divides it out.
    let supersample: CGFloat

    /// Block centre in raster-pixel space.
    let centre: CGPoint
}

/// Draws a text overlay once and cuts it into tiles.
///
/// The invariant, stated once because everything else follows from it:
///
/// > **Tiles are never rendered independently. One Core Text layout produces one fully decorated
/// > master raster, and tiles are non-overlapping cuts of that raster.**
///
/// Cutting rather than re-rendering is what keeps Arabic joined, ligatures whole, decoration
/// continuous across seams, and partial-alpha reveals free of double-composited overlaps.
/// Re-laying-out a substring in isolation would render `سلام` as four isolated forms and split
/// `ffi` — silently, with every structural test still passing. See FEATURE-TEXT-EFFECTS.md §7.1.
enum TextRasterizer {

    /// Lays out, draws and cuts. Returns `nil` when there is nothing to draw.
    ///
    /// - Parameter pixelSide: the square raster's side. 600 for the GIF; the canvas's point size
    ///   times the screen scale for the live preview. Preview and export deliberately rasterize at
    ///   their own native size — sharing one bitmap would mean a 0.54× non-integer downscale of a
    ///   pixel font, which is the most visible thing in the feature.
    static func prepare(overlay: TextOverlay?, pixelSide: CGFloat) -> RasterizedText? {
        guard let overlay, overlay.isActive, pixelSide > 0 else { return nil }
        guard let layout = TextLayoutEngine.layout(overlay: overlay, outputSide: pixelSide) else {
            return nil
        }

        let supersample = supersampleFactor(for: overlay)
        let side = Int((pixelSide * supersample).rounded())
        guard side > 0 else { return nil }

        guard let mask = drawMask(overlay: overlay, layout: layout,
                                  pixelSide: pixelSide, supersample: supersample, side: side),
              let master = fill(mask: mask, overlay: overlay,
                                inkRect: gradientInkRect(layout: layout, supersample: supersample,
                                                         side: side)) else { return nil }

        let centre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let tiles = cut(master: master, layout: layout, overlay: overlay,
                        supersample: supersample, centre: centre, side: side)
        guard !tiles.isEmpty else { return nil }

        return RasterizedText(
            layout: layout, master: master, tiles: tiles, pixelSide: pixelSide,
            granularity: overlay.animation.granularity, supersample: supersample, centre: centre
        )
    }

    /// How much larger than resting size to draw.
    ///
    /// Two independent reasons, multiplied. `peakScale` makes POP's overshoot frame 1:1 instead of
    /// an upscale. The off-axis factor is because rotation is applied at composite time, so a
    /// raster drawn upright and redrawn at 37° resamples — doubling it makes that resample clean.
    /// Axis-aligned text, the common case, skips the cost.
    static func supersampleFactor(for overlay: TextOverlay) -> CGFloat {
        let axisAligned = TextLayoutLimits.snapAngle(overlay.angle, current: nil).detent != nil
        return overlay.animation.peakScale * (axisAligned ? 1 : 2)
    }

    // MARK: - Drawing

    /// Draws the glyph coverage mask: decoration and text as alpha only, no colour.
    ///
    /// Kept as its own step even though V1 immediately fills it with a solid colour. The planned
    /// gradient and sparkle fills are all *fills over fixed glyph geometry* — with a mask they are
    /// a different fill through the same tiles; without one they are a re-architecture. Cheap now,
    /// expensive to retrofit. See FEATURE-TEXT-EFFECTS.md §16.
    private static func drawMask(overlay: TextOverlay, layout: PreparedTextLayout,
                                 pixelSide: CGFloat, supersample: CGFloat,
                                 side: Int) -> CGImage? {
        guard let recipe = TextLayoutEngine.makeFrame(overlay: overlay, outputSide: pixelSide,
                                                      scale: supersample) else { return nil }

        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(!overlay.font.isPixelFont)
        context.textMatrix = .identity

        // The context stays in Core Graphics' native bottom-left orientation, because that is what
        // `CTFrameDraw` expects. The layout's top-left coordinates are converted where needed
        // rather than by flipping the context, which would draw the text upside down.
        let pointSize = layout.resolvedPointSize * supersample
        let inkCentreCT = CGPoint(
            x: layout.inkCentreInPath.x * supersample,
            y: (layout.pathSize.height - layout.inkCentreInPath.y) * supersample
        )
        let rasterCentre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let offset = CGPoint(x: rasterCentre.x - inkCentreCT.x,
                             y: rasterCentre.y - inkCentreCT.y)

        // Decoration order is fixed and drawn into this one pass: plate, shadow, fill, outline.
        if overlay.decoration.drawsBackgroundPlate {
            let padding = overlay.decoration.platePadding * pointSize
            let plate = rasterRect(layout.inkBounds, centre: rasterCentre, scale: supersample)
                .insetBy(dx: -padding, dy: -padding)
            context.setFillColor(UIColor.white.cgColor)
            // `plate` is top-left; mirror it into the bottom-left context.
            context.fill(CGRect(x: plate.minX, y: CGFloat(side) - plate.maxY,
                                width: plate.width, height: plate.height))
        }

        if overlay.decoration == .shadow {
            context.saveGState()
            let shadow = overlay.decoration.shadowOffset
            context.setShadow(
                offset: CGSize(width: shadow.width * pointSize,
                               height: -shadow.height * pointSize),
                blur: overlay.decoration.shadowBlur * pointSize,
                color: UIColor.white.withAlphaComponent(0.85).cgColor
            )
            draw(recipe: recipe, offset: offset, in: context)
            context.restoreGState()
        }

        draw(recipe: recipe, offset: offset, in: context)

        if overlay.decoration == .outline {
            context.saveGState()
            context.setLineWidth(overlay.decoration.outlineWidth * pointSize)
            context.setLineJoin(.round)
            context.setTextDrawingMode(.stroke)
            context.setStrokeColor(UIColor.white.cgColor)
            draw(recipe: recipe, offset: offset, in: context)
            context.restoreGState()
        }

        return context.makeImage()
    }

    /// Draws the measured frame itself.
    ///
    /// `CTFrameDraw` is the whole point: it paints the shaped runs Core Text already produced, so
    /// joining forms, ligatures, bidi ordering and fallback fonts are all preserved for free.
    /// Nothing here re-shapes or re-positions anything.
    private static func draw(recipe: TextLayoutEngine.FrameRecipe, offset: CGPoint,
                             in context: CGContext) {
        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)
        CTFrameDraw(recipe.frame, context)
        context.restoreGState()
    }

    /// Ink bounds in the *fill context's* space, for ramping a gradient across the glyphs.
    ///
    /// The fill context is Core Graphics' native bottom-left, while `layout.inkBounds` is top-left
    /// and centred on the block — so this both scales it into raster pixels and flips it. Getting
    /// that wrong would not crash: the ramp would simply run the wrong way, which is exactly the
    /// class of silent error LEARNINGS records twice for Y-flips.
    private static func gradientInkRect(layout: PreparedTextLayout,
                                        supersample: CGFloat, side: Int) -> CGRect {
        let centre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let topLeft = rasterRect(layout.inkBounds, centre: centre, scale: supersample)
        guard topLeft.width > 0, topLeft.height > 0 else { return .zero }
        return CGRect(x: topLeft.minX, y: CGFloat(side) - topLeft.maxY,
                      width: topLeft.width, height: topLeft.height)
    }

    /// Converts a local-space rect (origin at the block centre, y down) into raster-pixel space,
    /// which is top-left origin to match `CGImage.cropping(to:)`.
    static func rasterRect(_ rect: CGRect, centre: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(x: centre.x + rect.origin.x * scale,
               y: centre.y + rect.origin.y * scale,
               width: rect.width * scale,
               height: rect.height * scale)
    }

    /// Applies the overlay's fill through the coverage mask.
    ///
    /// This is the seam §7.1 insisted on keeping: the mask carries the glyph geometry, and the fill
    /// is drawn *through* it. Adding gradients therefore changes only what is painted inside the
    /// clip — the layout, the tiles, the seams and every transform are untouched, and the partition
    /// invariant still holds because the tiles are cut from whatever this returns.
    private static func fill(mask: CGImage, overlay: TextOverlay, inkRect: CGRect) -> CGImage? {
        let width = mask.width, height = mask.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.clip(to: full, mask: mask)

        switch overlay.fillMode {
        case .color:
            context.setFillColor(overlay.color.uiColor.cgColor)
            context.fill(full)

        case .gradient:
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: overlay.gradient.cgColors as CFArray,
                locations: TextGradient.locations
            ) else {
                // A gradient that cannot be built must not produce invisible text.
                context.setFillColor(overlay.color.uiColor.cgColor)
                context.fill(full)
                break
            }
            // Ramped across the *ink*, not the raster. The raster is a square canvas mostly full of
            // empty space — running the ramp over that would spend most of its range outside the
            // glyphs, so short text would show a single flat slice of the gradient rather than the
            // whole thing.
            let ink = inkRect.isEmpty ? full : inkRect
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: ink.minX, y: ink.maxY),
                end: CGPoint(x: ink.maxX, y: ink.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        return context.makeImage()
    }


    // MARK: - Cutting

    /// Cuts the master into tiles that partition it exactly.
    ///
    /// Seams are computed as **integers** before any rect is built, and each tile spans one
    /// integer interval to the next. Rounding rects individually with `.integral` would round
    /// outward on both sides of a seam and leave neighbouring tiles overlapping by a pixel —
    /// which reads as a faint double-darkened seam under a partial-alpha reveal, and fails the
    /// partition test for a reason that looks like a rendering bug.
    private static func cut(master: CGImage, layout: PreparedTextLayout, overlay: TextOverlay,
                            supersample: CGFloat, centre: CGPoint, side: Int) -> [TextTile] {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)

        let groups: [Range<Int>]
        switch overlay.animation.granularity {
        case .whole:
            return [tile(slot: 0, rect: bounds, master: master, centre: centre)].compactMap { $0 }
        case .unit:
            groups = layout.units.map { $0.order ..< ($0.order + 1) }
        case .word:
            groups = layout.wordRanges
        }

        // Ink rect and line for each group, in raster space, dropping the ink-free ones.
        let placed = groups.enumerated().compactMap { slot, range -> (slot: Int, rect: CGRect, line: Int)? in
            let members = layout.units[range].filter { !$0.isWhitespace }
            let ink = members.map(\.inkRect).reduce(CGRect.null) { $0.union($1) }
            guard !ink.isNull, let line = members.first?.lineIndex else { return nil }
            return (slot, rasterRect(ink, centre: centre, scale: supersample), line)
        }
        guard !placed.isEmpty else {
            return [tile(slot: 0, rect: bounds, master: master, centre: centre)].compactMap { $0 }
        }

        // Horizontal bands, one per line, split at the midpoint of each interline gap.
        let lines = Dictionary(grouping: placed, by: \.line).sorted { $0.key < $1.key }
        var bandEdges: [Int] = [Int(bounds.minY)]
        for index in 0..<(lines.count - 1) {
            let upper = lines[index].value.map(\.rect.maxY).max() ?? 0
            let lower = lines[index + 1].value.map(\.rect.minY).min() ?? upper
            bandEdges.append(Int(((upper + lower) / 2).rounded()))
        }
        bandEdges.append(Int(bounds.maxY))

        var tiles: [TextTile] = []
        for (bandIndex, line) in lines.enumerated() {
            let top = bandEdges[bandIndex]
            let bottom = bandEdges[bandIndex + 1]
            guard bottom > top else { continue }

            // Vertical seams within the band, at the midpoint of each gap between neighbours.
            let ordered = line.value.sorted { $0.rect.minX < $1.rect.minX }
            var columnEdges: [Int] = [Int(bounds.minX)]
            for index in 0..<(ordered.count - 1) {
                let left = ordered[index].rect.maxX
                let right = ordered[index + 1].rect.minX
                columnEdges.append(Int(((left + right) / 2).rounded()))
            }
            columnEdges.append(Int(bounds.maxX))

            for (index, entry) in ordered.enumerated() {
                let rect = CGRect(x: columnEdges[index], y: top,
                                  width: columnEdges[index + 1] - columnEdges[index],
                                  height: bottom - top)
                if let made = tile(slot: entry.slot, rect: rect, master: master, centre: centre) {
                    tiles.append(made)
                }
            }
        }
        return tiles
    }

    private static func tile(slot: Int, rect: CGRect, master: CGImage,
                             centre: CGPoint) -> TextTile? {
        guard rect.width >= 1, rect.height >= 1,
              let cropped = master.cropping(to: rect) else { return nil }
        return TextTile(
            slotIndex: slot,
            image: cropped,
            pixelRect: rect,
            localCentre: CGPoint(x: rect.midX - centre.x, y: rect.midY - centre.y),
            origin: .cut
        )
    }
}
