// ROADMAP §1c — the CIKernel de-risking gate.
//
// This kernel does nothing on purpose. It exists to prove the *infrastructure* works before any
// effect math depends on it, because the risk in this phase was never the math: setting
// -fcikernel at target scope would hit Shaders/Pixellate.metal, a SwiftUI [[stitchable]] shader,
// and -cikernel makes metallib emit a Core Image library that cannot serve ShaderLibrary.default.
// The animated canvas border would then fail to find its function **at runtime, in visible
// chrome** — never at build time. See EFFECTS.md → "The hazard, and the resolution".
//
// The .ci.metal suffix is load-bearing: a custom build rule matches it and takes precedence over
// Xcode's built-in Metal rule *for matching files only*, so Pixellate.metal keeps going through
// the stock path untouched.
//
// Note $INPUT_FILE_BASE strips only the last extension, so this builds Passthrough.ci.metallib
// and must be loaded with forResource: "Passthrough.ci". Getting that wrong yields a silent nil
// kernel rather than an error.

#include <CoreImage/CoreImage.h>

extern "C" float4 passthrough(coreimage::sample_t s) {
    return s;
}
