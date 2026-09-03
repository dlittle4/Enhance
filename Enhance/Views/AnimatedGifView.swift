import SwiftUI
import UIKit
import CoreGraphics
import ImageIO
import os

// Simple GIF cache to avoid reloading the same GIFs
class GIFCache {
    static let shared = GIFCache()
    private var cache: NSCache<NSURL, NSArray> = {
        let c = NSCache<NSURL, NSArray>()
        c.countLimit = 50
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    func getImages(for url: URL) -> [UIImage]? {
        return cache.object(forKey: url as NSURL) as? [UIImage]
    }

    func setImages(_ images: [UIImage], for url: URL) {
        let perFrame = images.first.map { Int($0.size.width * $0.size.height * 4) } ?? 0
        let cost = perFrame * images.count
        cache.setObject(images as NSArray, forKey: url as NSURL, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// UIViewRepresentable for displaying animated GIFs with loading state
struct AnimatedGifView: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var lowQuality: Bool = false
    var isVisible: Bool = true
    var playbackSpeed: Double = 1.0

    /// SCRUB THE PREVIEW. With this on the frames are driven by the coordinator's own
    /// display-link player rather than `UIImageView.animationImages`, because the image view's
    /// animation cannot be paused on a frame or resumed from one — and a scrub is exactly that.
    /// Off, the view is byte-for-byte the one that shipped.
    var isScrubInteractive: Bool = false
    /// Points of horizontal drag per full loop.
    var scrubSpan: Double = 300
    /// Frames between haptic ticks while scrubbing.
    var scrubTickEvery: Int = 4
    /// Thumb side of the filmstrip shown under a scrubbing finger.
    var scrubStripThumb: Double = 40

    @State private var isLoading = true

    // UIViewRepresentable implementation
    func makeUIView(context: Context) -> UIView {
        // Create a simple container view
        let containerView = UIView()
        containerView.backgroundColor = .clear

        // Create a centered image view that takes the full size
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true

        // Add the image view to the container
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)

        // Simple constraints to make the image view fill the container
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // The scrub: a zero-duration long press — UIKit's track-from-touch-down recogniser — so
        // holding freezes the frame the moment the finger lands and a drag scrubs from there.
        // Installed always and enabled by `isScrubInteractive`, so a flag flip needs no rebuild
        // of the view.
        let scrub = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScrub(_:)))
        scrub.minimumPressDuration = 0
        scrub.allowableMovement = .greatestFiniteMagnitude
        scrub.isEnabled = isScrubInteractive
        containerView.addGestureRecognizer(scrub)
        context.coordinator.scrubRecognizer = scrub
        context.coordinator.imageView = imageView

        // The filmstrip cue, hidden until a hold. Pinned to the bottom of the GIF, inset so
        // it reads as chrome over the picture rather than a bar cut off it.
        let filmstrip = ScrubFilmstripView()
        filmstrip.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(filmstrip)
        let stripHeight = filmstrip.heightAnchor.constraint(equalToConstant: ScrubFilmstripView.height(forThumb: CGFloat(scrubStripThumb)))
        NSLayoutConstraint.activate([
            filmstrip.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            filmstrip.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            filmstrip.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            stripHeight
        ])
        context.coordinator.filmstrip = filmstrip
        context.coordinator.filmstripHeight = stripHeight
        context.coordinator.apply(self)

        context.coordinator.currentURL = url
        loadGIF(from: url, into: imageView, context: context)

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.apply(self)

        if let imageView = uiView.subviews.first as? UIImageView {
            imageView.contentMode = contentMode

            if coordinator.currentURL != url {
                coordinator.currentURL = url
                coordinator.stopPlayer()
                imageView.stopAnimating()
                imageView.animationImages = nil
                imageView.image = nil
                loadGIF(from: url, into: imageView, context: context)
                return
            }

            if isScrubInteractive {
                // Own player. Hand it the frames if the image view is still animating them.
                if coordinator.frames.isEmpty, let frames = imageView.animationImages, !frames.isEmpty {
                    coordinator.adoptFrames(frames, totalDuration: coordinator.baseDuration ?? Double(frames.count) * 0.1)
                    imageView.stopAnimating()
                    imageView.animationImages = nil
                }
                coordinator.setPlaying(isVisible)
                return
            }

            // The shipped path. If the player had the frames (flag just turned off), hand back.
            if !coordinator.frames.isEmpty {
                let frames = coordinator.frames
                coordinator.stopPlayer()
                imageView.animationImages = frames
                imageView.animationDuration = coordinator.baseDuration ?? Double(frames.count) * 0.1
                imageView.animationRepeatCount = 0
            }

            if let baseDuration = coordinator.baseDuration {
                imageView.animationDuration = baseDuration
            }

            if isVisible && !imageView.isAnimating && imageView.animationImages != nil {
                imageView.startAnimating()
            } else if !isVisible && imageView.isAnimating {
                imageView.stopAnimating()
                if let lastFrame = imageView.animationImages?.last {
                    imageView.image = lastFrame
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopPlayer()
    }

    /// Shows the decoded frames, on whichever path the flag selects.
    private func present(_ images: [UIImage], totalDuration: Double, in imageView: UIImageView, context: Context) {
        context.coordinator.baseDuration = totalDuration
        if isScrubInteractive {
            context.coordinator.adoptFrames(images, totalDuration: totalDuration)
            context.coordinator.setPlaying(isVisible)
        } else {
            imageView.animationImages = images
            imageView.animationDuration = totalDuration
            imageView.animationRepeatCount = 0
            imageView.startAnimating()
        }
    }

    private func loadGIF(from url: URL, into imageView: UIImageView, context: Context) {
        // Set loading state to true
        DispatchQueue.main.async {
            context.coordinator.isLoading = true
        }

        if let cachedImages = GIFCache.shared.getImages(for: url) {
            let baseDuration = Double(cachedImages.count) * 0.1
            context.coordinator.isLoading = false
            present(cachedImages, totalDuration: baseDuration, in: imageView, context: context)
            return
        }

        DispatchQueue.global().async {
            do {
                let data = try Data(contentsOf: url)

                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    print("Error: Could not create image source from data for URL: \(url.lastPathComponent)")
                    setPlaceholder(for: imageView)
                    return
                }

                let count = CGImageSourceGetCount(source)

                if count == 0 {
                    print("Error: No frames found in GIF at URL: \(url.lastPathComponent)")
                    setPlaceholder(for: imageView)
                    return
                }

                var images: [UIImage] = []
                var totalDuration: TimeInterval = 0

                // Create downsampling options for lower quality if needed
                let options: [CFString: Any]? = lowQuality ? [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 350,
                    kCGImageSourceShouldCacheImmediately: false // Don't cache immediately to reduce memory
                ] : nil

                // For low quality mode, we'll also skip frames to improve performance
                let frameSkip = lowQuality ? max(1, count / 30) : 1

                for i in stride(from: 0, to: count, by: frameSkip) {
                    // Use the downsampling options if in low quality mode
                    let cgImage: CGImage?
                    if lowQuality {
                        cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary?)
                    } else {
                        cgImage = CGImageSourceCreateImageAtIndex(source, i, nil)
                    }

                    if let cgImage = cgImage {
                        // Get frame duration
                        let frameDuration = Self.frameDurationAtIndex(i, source: source) * Double(frameSkip)
                        totalDuration += frameDuration

                        let image = UIImage(cgImage: cgImage)
                        images.append(image)
                    }
                }

                DispatchQueue.main.async {
                    if images.count == 1, let firstImage = images.first {
                        imageView.image = firstImage
                    } else if !images.isEmpty {
                        GIFCache.shared.setImages(images, for: url)
                        present(images, totalDuration: totalDuration, in: imageView, context: context)
                    } else {
                        setPlaceholder(for: imageView)
                    }

                    context.coordinator.isLoading = false
                }
            } catch {
                print("Error loading GIF data for \(url.lastPathComponent): \(error.localizedDescription)")
                setPlaceholder(for: imageView)
            }
        }
    }

    private func setPlaceholder(for imageView: UIImageView) {
        DispatchQueue.main.async {
            // Set a placeholder for failed GIFs
            imageView.image = UIImage(systemName: "photo")
            imageView.tintColor = .gray
        }
    }

    static func frameDurationAtIndex(_ index: Int, source: CGImageSource) -> TimeInterval {
        var frameDuration: TimeInterval = 0.1 // Default duration

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
           let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {

            // Get the unclamped delay time
            if let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval,
               unclampedDelay > 0 {
                frameDuration = unclampedDelay
            } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? TimeInterval,
                      delay > 0 {
                frameDuration = delay
            }
        }

        // Check for too small duration that would make animation too fast
        if frameDuration < 0.02 {
            frameDuration = 0.1
        }

        return frameDuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Holds the load state and, under SCRUB THE PREVIEW, the frame player.
    ///
    /// The player is a `CADisplayLink` stepping `imageView.image` through `frames` at the GIF's
    /// average frame delay divided by `playbackSpeed`. Deliberately not `UIImageView`'s own
    /// animation, which has no notion of a current frame: it can be started and stopped, and
    /// stopping shows whatever `image` is set to, not the frame it was on.
    class Coordinator {
        var isLoading = true
        var baseDuration: Double?
        var currentURL: URL?

        weak var imageView: UIImageView?
        weak var scrubRecognizer: UILongPressGestureRecognizer?
        weak var filmstrip: ScrubFilmstripView?
        var filmstripHeight: NSLayoutConstraint?

        private(set) var frames: [UIImage] = []
        private var frameDuration: Double = 0.04
        private var playbackSpeed: Double = 1
        private var scrubSpan: Double = 300
        private var scrubTickEvery: Int = 4

        private var displayLink: CADisplayLink?
        private(set) var frameIndex = 0
        private var accumulated: CFTimeInterval = 0
        /// True while a finger holds the frame. The link keeps running so lift resumes on the
        /// very next tick; it simply does not advance.
        private var isHeld = false
        private var wantsPlaying = true

        private var scrubStartIndex = 0
        private var scrubStartX: CGFloat = 0
        private var lastTickIndex = 0

        /// Debug-level only. A scrub cannot be screenshotted mid-hold from outside the process,
        /// so this is how a QA pass confirms the hold froze and where the drag landed:
        /// `log show --debug --predicate 'subsystem == "Enhance" && category == "scrub"'`.
        private let log = Logger(subsystem: "Enhance", category: "scrub")

        deinit {
            displayLink?.invalidate()
        }

        /// Copies the representable's current knobs. Cheap, and called on every update so the
        /// lab's sliders take effect mid-session.
        func apply(_ view: AnimatedGifView) {
            playbackSpeed = max(0.1, view.playbackSpeed)
            scrubSpan = view.scrubSpan
            scrubTickEvery = max(1, view.scrubTickEvery)
            scrubRecognizer?.isEnabled = view.isScrubInteractive
            let thumb = CGFloat(max(16, view.scrubStripThumb))
            if filmstrip?.thumbSide != thumb {
                filmstrip?.thumbSide = thumb
                filmstripHeight?.constant = ScrubFilmstripView.height(forThumb: thumb)
            }
        }

        func adoptFrames(_ images: [UIImage], totalDuration: Double) {
            frames = images
            frameDuration = max(0.01, totalDuration / Double(max(1, images.count)))
            frameIndex = min(frameIndex, max(0, images.count - 1))
            accumulated = 0
            imageView?.image = images[frameIndex]
            startLinkIfNeeded()
        }

        func setPlaying(_ playing: Bool) {
            wantsPlaying = playing
            if playing { startLinkIfNeeded() } else { displayLink?.isPaused = true }
        }

        func stopPlayer() {
            displayLink?.invalidate()
            displayLink = nil
            frames = []
            frameIndex = 0
            accumulated = 0
            isHeld = false
        }

        private func startLinkIfNeeded() {
            guard !frames.isEmpty, wantsPlaying else { return }
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            displayLink?.isPaused = false
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard !frames.isEmpty, !isHeld else { return }
            accumulated += link.targetTimestamp - link.timestamp
            // The GIF's own delays already carry SPEED (the generator wrote them), so the
            // player must not apply it again — that double-applied it to a PATH's stop pauses.
            let step = frameDuration
            var advanced = false
            while accumulated >= step {
                accumulated -= step
                frameIndex = (frameIndex + 1) % frames.count
                advanced = true
            }
            if advanced { imageView?.image = frames[frameIndex] }
        }

        // MARK: Scrub

        @objc func handleScrub(_ recognizer: UILongPressGestureRecognizer) {
            guard !frames.isEmpty, let host = recognizer.view else { return }
            let x = recognizer.location(in: host).x
            switch recognizer.state {
            case .began:
                isHeld = true
                scrubStartIndex = frameIndex
                scrubStartX = x
                lastTickIndex = frameIndex
                HapticService.prepareSelection()
                HapticService.light()
                if let filmstrip {
                    filmstrip.setFrames(frames)
                    filmstrip.show(index: frameIndex, animated: false)
                    filmstrip.setVisible(true)
                }
                log.debug("hold began at frame \(self.frameIndex, privacy: .public) of \(self.frames.count, privacy: .public)")
            case .changed:
                let target = CanvasTuning.scrubbedFrame(
                    from: scrubStartIndex, dragX: x - scrubStartX, span: scrubSpan, frameCount: frames.count
                )
                guard target != frameIndex else { return }
                frameIndex = target
                imageView?.image = frames[target]
                filmstrip?.show(index: target, animated: true)
                // Ticks keyed to frames crossed, not to gesture updates, so the detents follow
                // the GIF's own rhythm rather than the touch sample rate. Distance is measured
                // the short way round the loop so a wrap does not fire a burst.
                let crossed = abs(target - lastTickIndex)
                let wrapped = min(crossed, frames.count - crossed)
                if wrapped >= scrubTickEvery {
                    HapticService.selection()
                    lastTickIndex = target
                }
            case .ended, .cancelled, .failed:
                isHeld = false
                accumulated = 0
                filmstrip?.setVisible(false)
                log.debug("hold ended at frame \(self.frameIndex, privacy: .public), started \(self.scrubStartIndex, privacy: .public)")
            default:
                break
            }
        }
    }
}

struct AnimatedGifViewWithLoading: View {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var lowQuality: Bool = false
    var isVisible: Bool = true
    var playbackSpeed: Double = 1.0
    var isScrubInteractive: Bool = false
    var scrubSpan: Double = 300
    var scrubTickEvery: Int = 4
    var scrubStripThumb: Double = 40

    var body: some View {
        AnimatedGifView(
            url: url, contentMode: contentMode, lowQuality: lowQuality, isVisible: isVisible,
            playbackSpeed: playbackSpeed, isScrubInteractive: isScrubInteractive,
            scrubSpan: scrubSpan, scrubTickEvery: scrubTickEvery, scrubStripThumb: scrubStripThumb
        )
    }
}

// Preview for AnimatedGifView
struct AnimatedGifView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("AnimatedGifView Preview")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 10)

            // Note: This will show a placeholder in previews
            // since URL cannot be loaded in preview context
            AnimatedGifViewWithLoading(
                url: URL(string: "placeholder.gif")!,
                contentMode: .scaleAspectFit
            )
            .frame(width: 300, height: 300)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(AppConstants.CornerRadius.standard)

            Text("Note: Actual GIFs will only display in simulator or device")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 10)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
