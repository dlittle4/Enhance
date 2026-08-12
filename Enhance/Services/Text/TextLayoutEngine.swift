import CoreText
import NaturalLanguage
import UIKit

/// Which way the paragraph reads, as resolved by Core Text from the string itself.
enum TextBaseDirection: Sendable {
    case leftToRight
    case rightToLeft
}

/// One reveal unit: never smaller than a grapheme cluster, and never splitting a glyph.
///
/// The second half of that rule is what makes the whole design safe. Revealing text by grapheme
/// cluster is the obvious approach, and it is wrong: `لا` is two clusters and one glyph, `ffi` is
/// three clusters and one glyph, so a cluster-sized reveal cuts a glyph in half. Merging clusters
/// that share a glyph keeps every reveal step on a glyph boundary.
struct TextUnit: Equatable, Sendable {
    /// Logical (typing) order. Ascending is typing order in both LTR and RTL — the *visual*
    /// position is in `inkRect` and can run the other way.
    let order: Int

    /// UTF-16 offsets into the source string. Diagnostics and accessibility only; never use
    /// these to slice the string for rendering.
    let stringRange: Range<Int>

    /// Opaque glyph identifiers, used only to prove that units partition the glyph set.
    let glyphIDs: [Int]

    /// Tight ink bounds in local space (origin at the block's centre, y down).
    let inkRect: CGRect

    /// Trailing edge along the baseline, in typing direction — where the cursor sits after this
    /// unit. Direction-aware, so in RTL it is to the *left* of the glyph.
    let advanceEnd: CGPoint

    let lineIndex: Int

    /// Zero-ink units still exist so the cursor can sit after a space, but they produce no tile.
    let isWhitespace: Bool
}

/// One laid-out line.
struct TextLine: Equatable, Sendable {
    let index: Int
    /// Units on this line, as a range over `PreparedTextLayout.units`.
    let unitRange: Range<Int>
    /// Tight ink bounds of the line, local space.
    let inkRect: CGRect
    /// Baseline y in local space.
    let baselineY: CGFloat
}

/// The result of one Core Text pass: everything needed to rasterize, cut and animate, with no
/// Core Foundation objects left in it.
///
/// **Resolution-independent by construction.** Every geometric value scales linearly with
/// `resolvedPointSize`, so the same layout drives the 600px export and the 975px preview raster.
/// That is what lets preview and export share this type and a single transform function instead of
/// sharing bitmaps — see FEATURE-TEXT-EFFECTS.md §7.4 — and it is directly asserted by
/// `layoutIsResolutionIndependent`.
struct PreparedTextLayout: Equatable, Sendable {
    let units: [TextUnit]
    let lines: [TextLine]

    /// Linguistic word tokens, as ranges over `units`. From `NLTokenizer`, never a split on
    /// spaces — "don't stop" is two words, and a space split gets that wrong in every language
    /// that does not separate words with spaces at all.
    let wordRanges: [Range<Int>]

    /// Tight ink bounds of the whole block, local space. Centred on the origin, so this is
    /// symmetric about zero and rotation about the origin is rotation about the block's centre.
    let inkBounds: CGRect

    let resolvedPointSize: CGFloat

    /// The output side this layout was measured against, so callers can normalize its pixel
    /// geometry back to `0…1` of the frame. TICKER needs it to express a repeat step that means
    /// the same thing in the 600px export and the 975px preview raster.
    let outputSide: CGFloat

    let baseDirection: TextBaseDirection
    let lineCount: Int

    /// Centre of the ink in the framesetter's own path space, before the block was re-centred on
    /// the origin, at scale 1. The rasterizer needs it to translate the drawn frame so the text
    /// lands in the middle of the raster; without it the drawing and the measurement disagree.
    let inkCentreInPath: CGPoint

    /// The framesetter path's size at scale 1.
    let pathSize: CGSize

    /// Carried from the overlay so the animation evaluator stays a pure function of its
    /// arguments rather than reaching for the model.
    let seed: UInt64
}

/// Lays a `TextOverlay` out exactly once.
///
/// Pure: no graphics context, no main-thread requirement, safe to call from the generator's
/// background queue. The single most important property is that this runs **once per string**,
/// never once per reveal unit — see `TextUnit`.
enum TextLayoutEngine {

    /// A framesetter frame plus everything measured from it.
    ///
    /// Built by one function so measuring and *drawing* cannot diverge. The rasterizer rebuilds
    /// this at raster scale and draws the very frame that was measured, rather than re-deriving
    /// positions and hoping they match.
    struct FrameRecipe {
        let frame: CTFrame
        let lines: [CTLine]
        let origins: [CGPoint]
        let pathSize: CGSize
    }

    /// Builds the frame for an overlay at `scale` times its natural size.
    ///
    /// - Parameter scale: 1 when measuring; the supersample factor when drawing.
    static func makeFrame(overlay: TextOverlay, outputSide: CGFloat,
                          scale: CGFloat) -> FrameRecipe? {
        guard overlay.isActive, outputSide > 0, scale > 0 else { return nil }

        let pointSize = overlay.fontSize * outputSide * scale
        guard pointSize > 0 else { return nil }

        let font = overlay.font.resolved(pointSize: pointSize)
        // Deliberately far wider than the frame, so growing the text scales it instead of
        // reflowing it. Wrapping at a fraction of the frame meant a pinch silently broke the
        // word onto a second line mid-gesture, which is not what "make it bigger" should do.
        // The block is re-centred on its own ink below, so the oversized path costs nothing.
        let wrapWidth = TextLayoutLimits.layoutWidth * outputSide * scale * 12

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = overlay.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping
        // `.natural` lets Core Text resolve direction from the string's own characters, so an
        // Arabic overlay lays out right-to-left without the editor detecting anything.
        paragraph.baseWritingDirection = .natural
        paragraph.lineHeightMultiple = TextLayoutLimits.lineHeightMultiple

        let attributed = NSAttributedString(string: overlay.text, attributes: [
            .font: font,
            .paragraphStyle: paragraph
        ])

        // Generously tall: a short path silently truncates lines, and the extra height costs
        // nothing because the ink bounds are what get used.
        let pathHeight = pointSize * TextLayoutLimits.lineHeightMultiple
            * CGFloat(overlay.text.count + 3)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: wrapWidth, height: pathHeight),
                          transform: nil)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             path, nil)

        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        return FrameRecipe(frame: frame, lines: lines, origins: origins,
                           pathSize: CGSize(width: wrapWidth, height: pathHeight))
    }

    /// Lays the overlay out for a square output frame of `outputSide` points or pixels.
    ///
    /// Returns `nil` for an inactive overlay or one that produces no ink, which the rasterizer
    /// treats as "no text pass" rather than as an error.
    static func layout(overlay: TextOverlay, outputSide: CGFloat) -> PreparedTextLayout? {
        guard let recipe = makeFrame(overlay: overlay, outputSide: outputSide, scale: 1) else {
            return nil
        }

        let pointSize = overlay.fontSize * outputSide
        let font = overlay.font.resolved(pointSize: pointSize)
        let pathHeight = recipe.pathSize.height

        let placed = placedGlyphs(lines: recipe.lines, origins: recipe.origins,
                                  pathHeight: pathHeight, fallback: font)
        guard !placed.isEmpty else { return nil }

        let clusters = clusterRanges(in: overlay.text)
        guard !clusters.isEmpty else { return nil }

        var units = mergeIntoUnits(glyphs: placed, clusters: clusters,
                                   utf16Count: overlay.text.utf16.count,
                                   text: overlay.text)
        guard !units.isEmpty else { return nil }

        units = assignAdvanceEnds(units, lines: recipe.lines, origins: recipe.origins,
                                  pathHeight: pathHeight)

        // Everything above is in a top-left layout space whose origin is the path's top-left.
        // Re-centre on the block's own centre, so rotating about the local origin rotates about
        // the middle of the text.
        let rawBounds = units.filter { !$0.isWhitespace }
            .map(\.inkRect)
            .reduce(CGRect.null) { $0.union($1) }
        guard !rawBounds.isNull, rawBounds.width > 0, rawBounds.height > 0 else { return nil }

        let shift = CGPoint(x: -rawBounds.midX, y: -rawBounds.midY)
        units = units.map { $0.shifted(by: shift) }

        return PreparedTextLayout(
            units: units,
            lines: buildLines(units: units, lineCount: recipe.lines.count),
            wordRanges: wordRanges(in: overlay.text, units: units),
            inkBounds: rawBounds.offsetBy(dx: shift.x, dy: shift.y),
            resolvedPointSize: pointSize,
            outputSide: outputSide,
            baseDirection: baseDirection(of: recipe.lines.first),
            lineCount: recipe.lines.count,
            inkCentreInPath: CGPoint(x: rawBounds.midX, y: rawBounds.midY),
            pathSize: recipe.pathSize,
            seed: overlay.seed
        )
    }

    // MARK: - Glyph collection

    /// One glyph, already converted into top-left layout space.
    private struct PlacedGlyph {
        let stringIndex: Int
        let glyphID: Int
        let inkRect: CGRect
        let lineIndex: Int
        let baselineY: CGFloat
    }

    private static func placedGlyphs(lines: [CTLine], origins: [CGPoint],
                                     pathHeight: CGFloat, fallback: UIFont) -> [PlacedGlyph] {
        var result: [PlacedGlyph] = []

        for (lineIndex, line) in lines.enumerated() {
            let lineOrigin = origins[lineIndex]
            // Core Text works bottom-left, y up; everything downstream of here is top-left, y down.
            let baselineY = pathHeight - lineOrigin.y

            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }

            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let runFont = font(in: run, fallback: fallback)

                // Always the copying form. The direct pointer accessors are allowed to return
                // nil whenever the run does not store that array contiguously, and the optimistic
                // path then silently drops a run.
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                let whole = CFRange(location: 0, length: 0)
                CTRunGetGlyphs(run, whole, &glyphs)
                CTRunGetPositions(run, whole, &positions)
                CTRunGetStringIndices(run, whole, &indices)

                var boxes = [CGRect](repeating: .zero, count: count)
                CTFontGetBoundingRectsForGlyphs(runFont, .default, &glyphs, &boxes, count)

                for i in 0..<count {
                    let box = boxes[i]
                    let originX = lineOrigin.x + positions[i].x + box.minX
                    // box is y-up from the baseline; flip it into y-down layout space.
                    let originY = baselineY - positions[i].y - box.maxY
                    result.append(PlacedGlyph(
                        stringIndex: Int(indices[i]),
                        glyphID: Int(glyphs[i]),
                        inkRect: CGRect(x: originX, y: originY,
                                        width: box.width, height: box.height),
                        lineIndex: lineIndex,
                        baselineY: baselineY
                    ))
                }
            }
        }

        // Logical order. Runs come in visual order and an RTL line reverses them, so sorting by
        // string index is what makes "typing order" mean typing order in every language.
        return result.sorted { $0.stringIndex < $1.stringIndex }
    }

    /// The run's own font, which may be a fallback face Core Text substituted for emoji or for
    /// characters Silkscreen does not cover. Measuring those with the requested font instead
    /// would produce boxes that do not match what was drawn.
    private static func font(in run: CTRun, fallback: UIFont) -> CTFont {
        guard let attributes = CTRunGetAttributes(run) as? [String: Any],
              let value = attributes[kCTFontAttributeName as String] else {
            return fallback as CTFont
        }
        if let uiFont = value as? UIFont {
            return uiFont as CTFont
        }
        return fallback as CTFont
    }

    // MARK: - Cluster and unit construction

    /// Extended grapheme cluster ranges, as UTF-16 offsets.
    private static func clusterRanges(in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for character in text {
            let start = ranges.last?.upperBound ?? 0
            ranges.append(start ..< (start + String(character).utf16.count))
        }
        return ranges
    }

    /// Merges clusters that share a glyph, producing units that never split a glyph.
    ///
    /// The rule: a glyph covers every cluster from its own string index up to the next glyph's
    /// string index. When that span is more than one cluster, the glyph is a ligature or a joined
    /// form and those clusters become a single unit.
    private static func mergeIntoUnits(glyphs: [PlacedGlyph], clusters: [Range<Int>],
                                       utf16Count: Int, text: String) -> [TextUnit] {
        var units: [TextUnit] = []
        var glyphIndex = 0
        var clusterIndex = 0

        while clusterIndex < clusters.count {
            let startCluster = clusterIndex
            var owned: [PlacedGlyph] = []

            while glyphIndex < glyphs.count,
                  glyphs[glyphIndex].stringIndex < clusters[clusterIndex].upperBound {
                owned.append(glyphs[glyphIndex])
                glyphIndex += 1
            }

            let nextStart = glyphIndex < glyphs.count
                ? glyphs[glyphIndex].stringIndex
                : utf16Count

            var end = clusterIndex + 1
            while end < clusters.count, clusters[end].lowerBound < nextStart {
                end += 1
            }

            let range = clusters[startCluster].lowerBound ..< clusters[end - 1].upperBound
            let ink = owned.map(\.inkRect).reduce(CGRect.null) { $0.union($1) }
            let substring = substring(of: text, utf16Range: range)

            units.append(TextUnit(
                order: units.count,
                stringRange: range,
                glyphIDs: owned.map(\.glyphID),
                inkRect: ink.isNull ? .zero : ink,
                advanceEnd: .zero,
                lineIndex: owned.first?.lineIndex ?? units.last?.lineIndex ?? 0,
                isWhitespace: substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ))

            clusterIndex = end
        }

        return units
    }

    /// Slices by UTF-16 offset without ever rebuilding the string from code units — a surrogate
    /// pair reassembled scalar by scalar is not the character it came from.
    private static func substring(of text: String, utf16Range: Range<Int>) -> String {
        let utf16 = text.utf16
        guard let lower = utf16.index(utf16.startIndex, offsetBy: utf16Range.lowerBound,
                                      limitedBy: utf16.endIndex),
              let upper = utf16.index(utf16.startIndex, offsetBy: utf16Range.upperBound,
                                      limitedBy: utf16.endIndex),
              let start = String.Index(lower, within: text),
              let end = String.Index(upper, within: text) else { return "" }
        return String(text[start..<end])
    }

    /// Fills in each unit's cursor position from Core Text, which is direction-aware.
    private static func assignAdvanceEnds(_ units: [TextUnit], lines: [CTLine],
                                          origins: [CGPoint],
                                          pathHeight: CGFloat) -> [TextUnit] {
        units.map { unit in
            guard unit.lineIndex < lines.count else { return unit }
            let line = lines[unit.lineIndex]
            let origin = origins[unit.lineIndex]
            let offset = CTLineGetOffsetForStringIndex(line, unit.stringRange.upperBound, nil)
            return unit.withAdvanceEnd(
                CGPoint(x: origin.x + offset, y: pathHeight - origin.y)
            )
        }
    }

    private static func buildLines(units: [TextUnit], lineCount: Int) -> [TextLine] {
        (0..<lineCount).compactMap { index in
            let onLine = units.filter { $0.lineIndex == index }
            guard let first = onLine.first, let last = onLine.last else { return nil }
            let ink = onLine.filter { !$0.isWhitespace }
                .map(\.inkRect)
                .reduce(CGRect.null) { $0.union($1) }
            return TextLine(
                index: index,
                unitRange: first.order ..< (last.order + 1),
                inkRect: ink.isNull ? .zero : ink,
                baselineY: first.advanceEnd.y
            )
        }
    }

    // MARK: - Word tokens

    /// Word ranges over unit indices, from `NLTokenizer`.
    ///
    /// Never `split(separator: " ")`. That gets "don't stop" wrong in English and gets every
    /// language that does not delimit words with spaces wrong entirely.
    private static func wordRanges(in text: String, units: [TextUnit]) -> [Range<Int>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var ranges: [Range<Int>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let lower = text.utf16.distance(from: text.startIndex,
                                            to: tokenRange.lowerBound)
            let upper = text.utf16.distance(from: text.startIndex,
                                            to: tokenRange.upperBound)
            let covered = units.filter {
                $0.stringRange.lowerBound < upper && $0.stringRange.upperBound > lower
            }
            if let first = covered.first, let last = covered.last {
                ranges.append(first.order ..< (last.order + 1))
            }
            return true
        }

        // A string of pure punctuation or emoji yields no linguistic tokens; treat the whole
        // block as one word so WORD DROP still animates rather than producing nothing.
        if ranges.isEmpty, !units.isEmpty {
            ranges = [0 ..< units.count]
        }
        return ranges
    }

    private static func baseDirection(of line: CTLine?) -> TextBaseDirection {
        guard let line, let runs = CTLineGetGlyphRuns(line) as? [CTRun],
              let first = runs.first else { return .leftToRight }
        return CTRunGetStatus(first).contains(.rightToLeft) ? .rightToLeft : .leftToRight
    }
}

private extension TextUnit {
    /// `TextUnit` is immutable, so the two-pass construction (glyphs first, then Core Text's
    /// direction-aware caret offsets) rebuilds rather than mutates.
    func withAdvanceEnd(_ point: CGPoint) -> TextUnit {
        TextUnit(
            order: order, stringRange: stringRange, glyphIDs: glyphIDs, inkRect: inkRect,
            advanceEnd: point, lineIndex: lineIndex, isWhitespace: isWhitespace
        )
    }

    func shifted(by delta: CGPoint) -> TextUnit {
        TextUnit(
            order: order,
            stringRange: stringRange,
            glyphIDs: glyphIDs,
            inkRect: isWhitespace && inkRect == .zero
                ? .zero
                : inkRect.offsetBy(dx: delta.x, dy: delta.y),
            advanceEnd: CGPoint(x: advanceEnd.x + delta.x, y: advanceEnd.y + delta.y),
            lineIndex: lineIndex,
            isWhitespace: isWhitespace
        )
    }
}
