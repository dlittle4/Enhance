import Testing
import CoreImage
import Foundation
@testable import Enhance

/// ROADMAP §1c — the CIKernel de-risking gate.
///
/// These tests guard *infrastructure*, not an effect. The hazard they exist for is specific and
/// nasty: `-fcikernel` at target scope would also hit `Shaders/Pixellate.metal`, a SwiftUI
/// `[[stitchable]]` shader, and `-cikernel` makes `metallib` emit a Core Image library that
/// cannot serve `ShaderLibrary.default`. The animated canvas border would then fail to find its
/// function **at runtime, in visible chrome** — never at build time, and never in a test that
/// only checks the kernel it was trying to add.
///
/// So both halves are asserted here: the Core Image library loads *and* the stock library the
/// border depends on is still a stock library. A future change that widens the build rule's
/// `*.ci.metal` pattern, or moves the flags to target scope, fails `defaultMetallib…` below
/// rather than silently blanking the border on device.
///
/// Tests are hosted, so `Bundle.main` is `Enhance.app`.
struct CIKernelGateTests {

    /// `$INPUT_FILE_BASE` strips only the *last* extension, so `Passthrough.ci.metal` builds to
    /// `Passthrough.ci.metallib` and loads as resource "Passthrough.ci". Naming it "Passthrough"
    /// here would yield a silent nil kernel, which is the documented trap.
    private static let resourceName = "Passthrough.ci"

    private func metallibURL() throws -> URL {
        try #require(
            Bundle.main.url(forResource: Self.resourceName, withExtension: "metallib"),
            "\(Self.resourceName).metallib is not in the app bundle — the *.ci.metal build rule did not run."
        )
    }

    @Test("the Core Image metallib is copied into the app bundle")
    func ciMetallib_isBundled() throws {
        let url = try metallibURL()
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    /// The gate's actual question: does a kernel compiled through the custom rule load at all?
    /// A nil return here means the rule produced a file that is not a Core Image library —
    /// which is what happens if `-fcikernel`/`-cikernel` are dropped from the script.
    @Test("a kernel built by the *.ci.metal rule loads")
    func ciKernel_loadsFromTheBuiltLibrary() throws {
        let data = try Data(contentsOf: try metallibURL())
        let kernel = try CIKernel(functionName: "passthrough", fromMetalLibraryData: data)
        #expect(kernel.name == "passthrough")
    }

    /// Loading is not the same as running: a kernel can construct and still fail to produce
    /// pixels. Passthrough returns its sample unchanged, so a red fixture must come back red.
    @Test("the passthrough kernel actually renders, and returns its input unchanged")
    func passthroughKernel_rendersIdentity() throws {
        let data = try Data(contentsOf: try metallibURL())
        let kernel = try CIKernel(functionName: "passthrough", fromMetalLibraryData: data)

        let side = 16
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)

        let output = try #require(
            kernel.apply(
                extent: bounds,
                roiCallback: { _, rect in rect },
                arguments: [source]
            ),
            "the kernel loaded but produced no image"
        )

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: side / 2, y: side / 2, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        #expect(pixel[0] > 200, "red channel should survive a passthrough, got \(pixel[0])")
        #expect(pixel[1] < 60, "green channel should stay low, got \(pixel[1])")
        #expect(pixel[2] < 60, "blue channel should stay low, got \(pixel[2])")
    }

    /// The other half of the gate, and the one that catches the regression this phase was
    /// actually afraid of. `default.metallib` must remain the *stock* Metal library — if the
    /// -cikernel flag ever reaches it, this file becomes a Core Image library and the canvas
    /// border loses its `pixellate` function at runtime.
    @Test("default.metallib is still a stock Metal library, so the canvas border keeps working")
    func defaultMetallib_isNotACoreImageLibrary() throws {
        let url = try #require(
            Bundle.main.url(forResource: "default", withExtension: "metallib"),
            "default.metallib is missing — the SwiftUI [[stitchable]] shader path is broken."
        )
        let data = try Data(contentsOf: url)

        // A Core Image kernel library is tagged `air.ci_builtin`; a stock one is not. Comparing
        // the marker beats comparing file sizes, which drift with every shader added.
        let marker = Data("air.ci_builtin".utf8)
        #expect(
            data.range(of: marker) == nil,
            "default.metallib was compiled as a Core Image library — the *.ci.metal build rule has leaked onto Pixellate.metal, and the animated border will not render."
        )

        // And the CI library genuinely is one, which keeps the assertion above honest: if the
        // marker ever stopped appearing at all, the check would pass for the wrong reason.
        let ciData = try Data(contentsOf: try metallibURL())
        #expect(
            ciData.range(of: marker) != nil,
            "Passthrough.ci.metallib is not a Core Image library — the -fcikernel/-cikernel flags are not reaching the build rule."
        )
    }
}
