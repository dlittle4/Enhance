// STATIC / DITHER — two- or three-colour quantization of whatever gradient is drawn beneath it.
//
// The layer underneath is never shown. It is read purely as a **density field**: the luminance
// of each cell decides which pole that cell takes, so the animated `MeshGradient` supplies the
// falloff across a button while the colours you actually see arrive as arguments. That split is
// what lets the colours pulse without the noise pattern having to know about them.
//
// One kernel serves every look in GRADIENT LAB, weighted by amounts rather than switched by
// mode. Turning STATIC and DITHER on together blends them — a random-jittered ordered dither —
// rather than forcing a precedence rule between two effects that occupy the same slot, and the
// same holds for halftone: at 0 it costs a `mix` and nothing else.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Verbatim from `CI/Riso.ci.metal`. Copied rather than shared because Core Image kernels and
// SwiftUI stitchable shaders are separate compilation units.
static inline float hash2(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

// Standard 4×4 ordered (Bayer) matrix, normalised to 0…1 and returned for the cell at `p`.
//
// Unlike the hash this is a *function of position alone*, so it does not change frame to frame:
// the texture holds still and only shifts as the density field moves under it, which is the
// difference between DITHER's crosshatch shimmer and STATIC's boil.
static inline float bayer4x4(float2 p) {
    const float matrix[16] = {
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0
    };
    int x = int(fmod(abs(p.x), 4.0));
    int y = int(fmod(abs(p.y), 4.0));
    return (matrix[y * 4 + x] + 0.5) / 16.0;
}

// A halftone screen expressed as a threshold field: distance from the centre of a rotated cell.
//
// Reading it as a threshold rather than drawing a dot is what lets it blend with the other two.
// A fragment near the cell centre has a low threshold, so it takes the light pole at low density
// and the dot grows outward as density rises — the same relationship `Riso.ci.metal`'s
// `halftoneDot` builds, arrived at from the other side.
//
// The angle matters more than it looks: an unrotated screen aligns its dots with the pixel grid
// and reads as a plaid, which is why every print process screens on a slant.
static inline float halftoneThreshold(float2 position, float size, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    float2 rotated = float2(position.x * c - position.y * s, position.x * s + position.y * c);
    float2 local = fract(rotated / max(size, 1.0)) - 0.5;
    return clamp(length(local) * 2.0, 0.0, 1.0);
}

// Luminance of the layer at the centre of the cell containing `position`.
//
// Identical cell maths to `pixellate`, so the two effects land on the same lattice and a button
// does not appear to shift when the flag is toggled.
static inline float densityAt(SwiftUI::Layer layer, float2 position, float size, float2 bounds) {
    float2 cell = floor(position / size);
    float2 center = clamp(cell * size + size * 0.5, float2(0.0), bounds - 1.0);
    half4 sampled = layer.sample(center);
    return dot(float3(sampled.rgb), float3(0.299, 0.587, 0.114));
}

// Which pole a density lands on, dithered against `threshold`.
//
// The general N-level form of an ordered dither: scale the density across the levels, take the
// whole part, and let the threshold decide the fractional step. At `levels == 2` this reduces
// exactly to `density > threshold`, so adding the third colour cost the two-colour look nothing.
static inline int ditherLevel(float density, float threshold, float levels) {
    float v = clamp(density, 0.0, 1.0) * (levels - 1.0);
    float base = floor(v);
    float step = (v - base) > threshold ? 1.0 : 0.0;
    return int(clamp(base + step, 0.0, levels - 1.0));
}

static inline half4 poleForLevel(int level, float levels, half4 light, half4 mid, half4 dark) {
    if (levels < 2.5) {
        return level >= 1 ? light : dark;
    }
    if (level >= 2) { return light; }
    if (level == 1) { return mid; }
    return dark;
}

[[ stitchable ]] half4 staticDither(float2 position, SwiftUI::Layer layer,
                                    float size, float2 bounds,
                                    float time, float noiseAmount, float orderedAmount,
                                    float halftoneAmount, float halftoneAngle,
                                    float splitDistance, float splitAngle, float levels,
                                    float2 drift,
                                    half4 colorLight, half4 colorMid, half4 colorDark) {
    float2 cell = floor(position / size);

    // The threshold fields are read at a *drifting* position while the density field stays put,
    // so the grain marches across a stationary gradient rather than the whole image sliding.
    // Bayer takes the drift in whole cells, which keeps it on its own 4-cell lattice; halftone is
    // continuous and takes it in points.
    float2 driftedCell = cell + floor(drift / size);

    // Ordered contributes a *position*-dependent threshold and halftone a radial one; noise is a
    // *time*-dependent offset around whatever those two settle on.
    float threshold = mix(0.5, bayer4x4(driftedCell), orderedAmount);
    threshold = mix(threshold, halftoneThreshold(position + drift, size, halftoneAngle), halftoneAmount);
    threshold = clamp(threshold + (hash2(driftedCell + time) - 0.5) * noiseAmount, 0.0, 1.0);

    // Chromatic split: quantize three *displaced* copies of the density field and keep one channel
    // from each. At distance 0 the three agree and the result is exactly the flat two-colour
    // output, so this costs nothing when it is off — and as it opens up, the poles fringe apart
    // at every edge in the noise rather than the whole button merely blurring.
    float2 offset = float2(cos(splitAngle), sin(splitAngle)) * splitDistance;

    half4 r = poleForLevel(ditherLevel(densityAt(layer, position + offset, size, bounds), threshold, levels),
                           levels, colorLight, colorMid, colorDark);
    half4 g = poleForLevel(ditherLevel(densityAt(layer, position, size, bounds), threshold, levels),
                           levels, colorLight, colorMid, colorDark);
    half4 b = poleForLevel(ditherLevel(densityAt(layer, position - offset, size, bounds), threshold, levels),
                           levels, colorLight, colorMid, colorDark);

    // The layer's own alpha still governs the silhouette, so a shape clipped or masked outside the
    // effect keeps its edge instead of being filled out to the bounding box.
    float2 center = clamp(cell * size + size * 0.5, float2(0.0), bounds - 1.0);
    half alpha = layer.sample(center).a;

    return half4(half3(r.r, g.g, b.b) * alpha, alpha);
}
