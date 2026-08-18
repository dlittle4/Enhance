#!/usr/bin/env swift

// Subject-segmentation spike harness (ROADMAP §1g).
//
// Answers one question and nothing else: is VNGenerateForegroundInstanceMaskRequest good
// enough to build the §2f subject-mask effects on, at the size and colour depth this app
// actually exports? Per EFFECTS.md a structural test cannot see a wrong-looking effect, so
// this renders and you look — it asserts nothing.
//
// It deliberately mirrors the real export path rather than approximating it: 600×600, and
// CGImageDestination GIF with HasGlobalColorMap, matching GIFGenerator.swift:128-141. The
// one global palette across all frames is the harsh part, and an approximation that wrote
// PNGs would have missed the finding that mattered (background banding, not edge fringing).
//
// The background treatment here is a deliberate placeholder — desaturate + blur — standing
// in for "any shipped VisualEffect, applied to the background only". It is also the worst
// case for palettisation, because it leaves a smooth gradient.
//
// Runs on macOS as a plain script, so it has no app-target build dependency — same trade as
// export-tokens.swift. Note that this means it exercises the *macOS* Vision model; see the
// caveat recorded on §1g before trusting the hit rate for iOS.
//
// Usage:  swift Tools/segmentation-spike.swift <output-dir> <image.png> [more images...]
//
// Per image it writes: -mask.png (what Vision returned), -cutout.png (composite, pre-GIF),
// -cutout.gif (through the real path), -gif-frame0.png (read back, post-palettisation —
// compare against -cutout.png to separate palettisation damage from mask damage).

import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AppKit

let ctx = CIContext(options: [.useSoftwareRenderer: false])
let outDir = CommandLine.arguments[1]
let inputs = Array(CommandLine.arguments.dropFirst(2))
let SIDE: CGFloat = 600

func writePNG(_ img: CIImage, _ path: String) {
    guard let cg = ctx.createCGImage(img, from: img.extent) else { print("  !! render fail \(path)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

/// The app's palettisation: ImageIO GIF, one global colour map across all frames.
func writeGIF(frames: [CIImage], _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil) else { return }
    CGImageDestinationSetProperties(dest, [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFLoopCount as String: 0,
            kCGImagePropertyGIFHasGlobalColorMap as String: true
        ]
    ] as CFDictionary)
    for f in frames {
        guard let cg = ctx.createCGImage(f, from: f.extent) else { continue }
        CGImageDestinationAddImage(dest, cg, [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 0.06,
                kCGImagePropertyGIFHasGlobalColorMap as String: true
            ]
        ] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
}

/// Pull one frame back out of the written GIF, so we look at post-palettisation pixels.
func extractGIFFrame(_ gifPath: String, index: Int, to pngPath: String) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: gifPath) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, index, nil) else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pngPath))
}

for input in inputs {
    let name = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
    print("\n=== \(name) ===")
    guard let nsImage = NSImage(contentsOfFile: input),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("  !! load fail"); continue
    }
    let source = CIImage(cgImage: cgImage)
    print("  source: \(Int(source.extent.width))x\(Int(source.extent.height))")

    // --- segmentation ---
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let t0 = CFAbsoluteTimeGetCurrent()
    do { try handler.perform([request]) } catch { print("  !! vision: \(error)"); continue }
    let tSeg = (CFAbsoluteTimeGetCurrent() - t0) * 1000

    guard let obs = request.results?.first else { print("  !! no observation — NO SUBJECT FOUND"); continue }
    let instances = obs.allInstances
    print(String(format: "  segmentation: %.0f ms, %d instance(s)", tSeg, instances.count))

    // union of all instances = single subject cutout
    let t1 = CFAbsoluteTimeGetCurrent()
    guard let maskBuffer = try? obs.generateScaledMaskForImage(forInstances: instances, from: handler) else {
        print("  !! mask generation failed"); continue
    }
    let tMask = (CFAbsoluteTimeGetCurrent() - t1) * 1000
    var mask = CIImage(cvPixelBuffer: maskBuffer)
    print(String(format: "  mask: %.0f ms, %dx%d", tMask, Int(mask.extent.width), Int(mask.extent.height)))

    // scale mask to source space if Vision returned a different resolution
    if mask.extent.size != source.extent.size {
        let sx = source.extent.width / mask.extent.width
        let sy = source.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        print(String(format: "  mask rescaled x%.3f", sx))
    }

    // --- how soft is the edge? count partial-alpha pixels ---
    // Downscale-free histogram: render mask to 8-bit gray and count mid values.
    if let cgMask = ctx.createCGImage(mask, from: mask.extent) {
        let w = cgMask.width, h = cgMask.height
        var buf = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        if let bctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            bctx.draw(cgMask, in: CGRect(x: 0, y: 0, width: w, height: h))
            var solid = 0, empty = 0, partial = 0
            for v in buf {
                if v > 240 { solid += 1 } else if v < 15 { empty += 1 } else { partial += 1 }
            }
            let total = Double(w * h)
            print(String(format: "  mask coverage: subject %.1f%%, background %.1f%%, feathered edge %.2f%% (%d px)",
                         Double(solid)/total*100, Double(empty)/total*100, Double(partial)/total*100, partial))
        }
    }

    writePNG(mask, "\(outDir)/\(name)-mask.png")

    // --- naive cutout composite: subject held, background effected ---
    // Stand-in for "face cutout + background effect": desaturate + blur the background.
    let bg = source
        .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0, "inputBrightness": -0.1])
        .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8.0])
        .cropped(to: source.extent)
    let composite = source.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: bg,
        kCIInputMaskImageKey: mask
    ])
    writePNG(composite, "\(outDir)/\(name)-cutout.png")

    // --- through the real GIF path, with a zoom like the app's ---
    var frames: [CIImage] = []
    for i in 0..<8 {
        let p = CGFloat(i) / 7.0
        let zoom = 1.0 + 0.35 * p
        let c = CGPoint(x: source.extent.midX, y: source.extent.midY)
        let t = CGAffineTransform(translationX: c.x, y: c.y)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -c.x, y: -c.y)
        let f = composite.transformed(by: t).cropped(to: source.extent)
        frames.append(f)
    }
    let gifPath = "\(outDir)/\(name)-cutout.gif"
    writeGIF(frames: frames, gifPath)
    extractGIFFrame(gifPath, index: 0, to: "\(outDir)/\(name)-gif-frame0.png")
    let attrs = try? FileManager.default.attributesOfItem(atPath: gifPath)
    let sz = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    print("  gif: \(gifPath) (\(sz/1024) KB, 8 frames)")
}
print("\nDONE")
