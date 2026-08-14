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
/// Note this is a **plain stitchable SwiftUI shader, not a `.ci.metal` Core Image kernel**, so it
/// is compiled by Xcode's stock Metal rule and never touches the `-fcikernel` build rule that
/// ROADMAP §1c scoped to `Shaders/CI/`. That gate exists for kernels used in GIF generation; a UI
/// layer effect on a grid thumbnail needs none of it.
[[ stitchable ]] half4 pixelReveal(float2 position,
                                   SwiftUI::Layer layer,
                                   float progress,
                                   float cellSize,
                                   float seed) {
    float size = max(cellSize, 1.0);
    float2 cell = floor(position / size);

    // Sampled at the true position rather than the cell centre: the cell decides *when* a region
    // appears, not what it looks like, so a revealed area is the real image rather than a mosaic.
    half4 color = layer.sample(position);

    // Scale the threshold band so the last cell lands exactly at progress 1. Without this the
    // highest-threshold cells would still be missing when the animation finishes.
    float threshold = cellHash(cell, seed);
    return threshold < progress ? color : half4(0.0h);
}
