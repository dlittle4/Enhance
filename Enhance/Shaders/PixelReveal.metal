#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Per-cell pseudo-random threshold in 0...1.
///
/// The usual sin-fract hash. Deterministic in cell coordinates, so a cell keeps the same
/// threshold for the whole reveal — a hash that drifted between frames would make cells flicker
/// in and out rather than land and stay.
static float cellHash(float2 cell, float seed) {
    return fract(sin(dot(cell, float2(12.9898, 78.233)) + seed) * 43758.5453);
}

/// Builds an image in, one blocky cell at a time, in scattered order.
///
/// `progress` sweeps 0 → 1; a cell appears once the reveal passes its threshold. Deliberately
/// **cells rather than literal pixels** *(user's call)*: at a ~114px grid thumbnail a per-pixel
/// dissolve reads as static rather than as something assembling, and chunky cells match the
/// app's pixel-art identity — `Pixellate.metal` and `DitherEffect` are both cell-based for the
/// same reason.
///
/// A landed cell is a **flat mosaic block** — sampled once at the cell centre, exactly as
/// `Pixellate.metal` does — not a window onto the sharp image *(user's call, 2026-08-14)*. The
/// point of the animation is the picture being *built* from chunky pixels; the sharp image
/// arrives only at the end, when the reveal completes and this shader steps aside.
///
/// Note this is a **plain stitchable SwiftUI shader, not a `.ci.metal` Core Image kernel**, so it
/// is compiled by Xcode's stock Metal rule and never touches the `-fcikernel` build rule that
/// ROADMAP §1c scoped to `Shaders/CI/`. That gate exists for kernels used in GIF generation; a UI
/// layer effect on a grid thumbnail needs none of it.
[[ stitchable ]] half4 pixelReveal(float2 position,
                                   SwiftUI::Layer layer,
                                   float progress,
                                   float cellSize,
                                   float seed,
                                   float4 bounds) {
    float size = max(cellSize, 1.0);
    float2 cell = floor(position / size);

    // The block's one colour: the cell centre, clamped so edge cells do not sample past the
    // layer and come back as a dark fringe.
    float2 centre = cell * size + size * 0.5;
    centre = clamp(centre, float2(0.0), bounds.zw - 1.0);
    half4 color = layer.sample(centre);

    float threshold = cellHash(cell, seed);
    return threshold < progress ? color : half4(0.0h);
}
