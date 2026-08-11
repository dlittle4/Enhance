import CoreImage
import CoreGraphics

/// Feature Scrambler — copies face features into a deliberately wrong arrangement over the
/// course of the zoom, then holds it steady. A landmark-aware Core Image compositor, not a
/// kernel. The `ScrambleLayout` chooses which features move where; THIRD EYE (V1) copies one
/// eye to the forehead, the Stage E pack adds mouth/eye swaps.
///
/// The reveal is driven by normalized GIF `progress`, not instantaneous zoom scale, so it
/// assembles monotonically under Zoom In, Zoom Out, and Pulse alike:
///   - `0.00...0.15` — untouched original.
///   - `0.15...0.75` — each copied feature travels from its source to its destination, growing
///     from roughly two-thirds of its final size with one eased settle.
///   - `0.75...1.00` — the final arrangement, stable for the pause.
///
/// Padding and feather are tuned constants rather than user controls, matching Snap's separate
/// inner/outer border concepts while keeping the panel to three rows (LAYOUT, INTENSITY, SIZE).
struct FeatureScramblerEffect: FaceEffect {

    private let size: CGFloat
    private let intensity: CGFloat
    private let layout: ScrambleLayout
    private let compositor = FaceRegionCompositor()

    // MARK: - Tuned constants (Stage A)
    // Chosen from rendered output, not the live preview. See FEATURE-SCRAMBLER.md Stage A.

    /// Source area kept around the feature landmark bounds, as a fraction of those bounds.
    /// Gives the feather room and retains eyelashes / lip edges beyond the tight polygon.
    private let padding: CGFloat = 0.35
    /// Mask edge softness (fraction of the ellipse radius spent fading out).
    private let feather: CGFloat = 0.55

    /// The skin heal covers the *replaced* feature, so it is larger and firmer than a
    /// placement — a soft heal lets the old eye/mouth bleed through at the edges. More
    /// padding reaches past the landmark polygon (eyelashes, lip corners); a low feather
    /// keeps the core solid.
    private let healPadding: CGFloat = 0.55
    private let healFeather: CGFloat = 0.3

    /// Reveal window, in normalized progress.
    private let revealStart: CGFloat = 0.15
    private let revealEnd: CGFloat = 0.75

    init(size: Double = 0.5, intensity: Double = 0.75, layout: ScrambleLayout = .thirdEye) {
        self.size = CGFloat(max(0, min(1, size)))
        self.intensity = CGFloat(max(0, min(1, intensity)))
        self.layout = layout
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        // Before the reveal begins the frame is the untouched original.
        guard progress > revealStart else { return image }

        // Zero intensity is "off" — identical to the input. Any positive value keeps the
        // tuned opacity floor below, so a low-but-nonzero setting stays visible.
        guard intensity > 0 else { return image }

        let specs = layout.placements(for: face, size: size)
        guard !specs.isEmpty else { return image }

        // Normalized, eased reveal fraction across the travel window.
        let t = smoothstep(min(1, max(0, (progress - revealStart) / (revealEnd - revealStart))))

        // INTENSITY is the final opacity; fade it in over the first quarter of the travel so
        // each copy emerges from its source feature instead of popping in at progress 0.15.
        let finalOpacity = 0.4 + intensity * 0.6
        let opacity = finalOpacity * min(1, t / 0.25)
        guard opacity > 0.01 else { return image }

        // Heal the features being replaced: cover each with skin sampled from just around it
        // (fading in with the reveal) so the moved copies read as replacements rather than
        // overlays. Local sampling tracks each feature's own lighting instead of forcing one
        // global tone. THIRD EYE heals nothing. Done before the placements.
        var result = image
        for region in layout.healRegions() {
            guard let fill = localSkinFill(around: region, in: image, face: face) else { continue }
            result = compositor.fillRegion(
                region, in: face, with: fill, over: result,
                padding: healPadding, feather: healFeather, opacity: opacity
            )
        }

        // Composite each placement onto the running result, but always sample from the
        // original `image` so a swap is a true swap and copies never stack recursively.
        for spec in specs {
            let center = CGPoint(
                x: lerp(spec.sourceCenter.x, spec.destination.x, t),
                y: lerp(spec.sourceCenter.y, spec.destination.y, t)
            )
            // Each copy grows from two-thirds toward its final size as it travels, so it
            // settles rather than snapping into place.
            let scale = spec.finalScale * lerp(0.65, 1.0, t)

            let placement = FaceRegionPlacement(
                region: spec.region, destinationCenter: center, scale: scale, opacity: opacity
            )
            result = compositor.composite(
                placement, source: image, over: result,
                face: face, padding: padding, feather: feather
            )
        }
        return result
    }

    // MARK: - Skin sampling

    /// A solid infinite fill of the skin just around a feature, so covering it matches the
    /// local tone and shading rather than one global average. Lazy: `CIAreaAverage` yields a
    /// 1×1 image and `clampedToExtent` spreads it, so no `CIContext` is created here.
    private func localSkinFill(around region: FaceRegion, in image: CIImage, face: DetectedFace) -> CIImage? {
        guard let rect = localSkinRect(for: region, face: face, in: image.extent) else { return nil }
        return image.clampedToExtent()
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            .clampedToExtent()
    }

    /// A patch of skin immediately beside a feature, at the *same* vertical level so it
    /// matches the feature's own lighting on a shaded face (sampling below would pick up the
    /// darker cheek/chin under top lighting). Samples *outward* toward the cheek/temple —
    /// reliably skin and clear of the nose between the eyes. The offset is floored to a
    /// fraction of the face so a narrow feature (the nose) still clears itself. Clipped to
    /// the image so the average is well-defined.
    private func localSkinRect(for region: FaceRegion, face: DetectedFace, in extent: CGRect) -> CGRect? {
        guard let b = region.sourceBounds(in: face) else { return nil }
        let outward: CGFloat = b.midX < face.faceCenter.x ? -1 : 1
        let offset = max(b.width * 0.75, face.faceWidth * 0.13)
        let cx = b.midX + outward * offset
        let w = max(4, min(b.width * 0.5, face.faceWidth * 0.12))
        let h = max(4, b.height * 0.6)
        let rect = CGRect(x: cx - w / 2, y: b.midY - h / 2, width: w, height: h)
            .intersection(extent)
        return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
    }

    // MARK: - Math

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Smoothstep easing — a single eased settle, deterministic, no oscillation.
    private func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
}
