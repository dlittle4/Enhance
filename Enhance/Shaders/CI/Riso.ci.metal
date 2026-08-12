// RISO — risograph emulation. A port of `Docs/reference/riso-print.wgsl`, kept verbatim in the
// repo so this can be checked against the source rather than against prose. See EFFECTS.md →
// "Riso Print" for the pipeline and for the two things the old prose summary got wrong.
//
// The look is **tonal-band separation**, not CMYK: luminance is split into shadow / midtone /
// highlight bands, each band gets one user-chosen spot colour, each is screened at its own
// halftone angle, and the three ink layers are multiplied onto warm paper.

#include <CoreImage/CoreImage.h>
#include <metal_stdlib>

using namespace metal;

// The kernel runs in the context's *linear* sRGB working space, but every constant below —
// the paper colour, the band edges, the 0.5 midpoint — was tuned in sRGB, and the spot colours
// arrive as sRGB components. Converting here rather than changing `workingColorSpace` keeps the
// change local; touching the context would silently alter every other effect in the app.
// EFFECTS.md documents this as one of the two things that make a hand-ported shader look wrong.
static inline float3 linearToSRGB(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
static inline float3 srgbToLinear(float3 c) { return pow(max(c, 0.0), 2.2); }

// Verbatim from the source. A hash rather than a texture read, so grain costs no bandwidth.
static inline float hash2(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

// One halftone screen. `lum` is *ink density* here, not brightness — the call sites pass
// `1 - mask`, so a strong band yields a large dot.
//
// The `sqrt` is what makes dot **area** track density rather than radius, which is why the
// midtones read as continuous rather than blowing out. The source also computed a `cell`
// value it never used; dropped.
static inline float halftoneDot(float2 pixel, float lum, float scale, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    float2 rotated = float2(pixel.x * c - pixel.y * s, pixel.x * s + pixel.y * c);
    float2 local = fract(rotated / scale) - 0.5;
    float radius = sqrt(1.0 - clamp(lum, 0.0, 1.0)) * 0.5;
    return smoothstep(radius + 0.02, radius - 0.02, length(local));
}

extern "C" float4 riso(coreimage::sampler src,
                       float4 colourShadow,
                       float4 colourMid,
                       float4 colourHighlight,
                       float halftoneScale,
                       float misregistration,
                       float grain,
                       float contrast,
                       float2 phase,
                       float mix_,
                       coreimage::destination dest) {
    float2 coord = dest.coord();

    // Plate misalignment: three samples at slightly different positions. The offsets are the
    // source's fixed fractions. Plate C never moves — it is the reference plate, and its alpha
    // is the one that passes through.
    float2 offsetA = float2(misregistration * 0.7, misregistration * 0.3);
    float2 offsetB = float2(-misregistration * 0.5, misregistration * 0.6);

    float4 sampleA = src.sample(src.transform(coord + offsetA));
    float4 sampleB = src.sample(src.transform(coord + offsetB));
    float4 sampleC = src.sample(src.transform(coord));

    float3 rgbA = linearToSRGB(sampleA.rgb);
    float3 rgbB = linearToSRGB(sampleB.rgb);
    float3 rgbC = linearToSRGB(sampleC.rgb);

    // Rec.601 weights, deliberately. EFFECTS.md standardises new effects on Rec.709, but this
    // is a port of a specific look and the band edges below were tuned against 601. Rec.709
    // weights green about 22% higher, which pushes green-heavy regions out of the midtone band
    // into the highlight band — a different picture, not a corrected one.
    const float3 rec601 = float3(0.299, 0.587, 0.114);
    float lumA = dot(rgbA, rec601);
    float lumB = dot(rgbB, rec601);
    float lumC = dot(rgbC, rec601);

    lumA = clamp((lumA - 0.5) * contrast + 0.5, 0.0, 1.0);
    lumB = clamp((lumB - 0.5) * contrast + 0.5, 0.0, 1.0);
    lumC = clamp((lumC - 0.5) * contrast + 0.5, 0.0, 1.0);

    // Tonal separation. The midtone mask is a triangular peak at 0.5 rather than a smoothstep,
    // so it falls off toward both ends and the three bands overlap into each other.
    float shadowMask    = smoothstep(0.5, 0.0, lumA);
    float midMask       = 1.0 - abs(lumB - 0.5) * 2.0;
    float highlightMask = smoothstep(0.5, 1.0, lumC);

    // The screens are anchored to image content, not to the frame: `phase` carries the
    // frame's content origin so the dots stay over the same features while the animation pans,
    // and `halftoneScale` already has the zoom folded in. Without both, the screen crawls
    // across the subject exactly as DITHER's did.
    float2 pixel = coord - phase;

    // The classic moiré-avoiding angle set: 15°, 75°, 45° in radians.
    float dotShadow    = halftoneDot(pixel, 1.0 - shadowMask,    halftoneScale, 0.2618);
    float dotMid       = halftoneDot(pixel, 1.0 - midMask,       halftoneScale, 1.309);
    float dotHighlight = halftoneDot(pixel, 1.0 - highlightMask, halftoneScale, 0.7854);

    // Subtractive: start at paper and multiply each ink layer, so overlapping inks darken the
    // way real ink does. Warm off-white rather than pure white — it is most of why the result
    // reads as printed paper.
    const float3 paper = float3(0.96, 0.94, 0.92);
    float3 inkShadow    = mix(float3(1.0), colourShadow.rgb,    dotShadow);
    float3 inkMid       = mix(float3(1.0), colourMid.rgb,       dotMid);
    float3 inkHighlight = mix(float3(1.0), colourHighlight.rgb, dotHighlight);

    float3 result = paper * inkShadow * inkMid * inkHighlight;

    // Grain is additive and applied after compositing — it sits on the paper, not in the ink.
    float noise = hash2(pixel * 1.7 + float2(42.0, 17.0));
    result += (noise - 0.5) * grain * 0.3;
    result = clamp(result, 0.0, 1.0);

    // INTENSITY blends back toward the untouched frame, matching GRADIENT's `strength`, so the
    // slider dials the effect in rather than switching it on.
    result = mix(rgbC, result, clamp(mix_, 0.0, 1.0));

    // Core Image expects premultiplied alpha. Photos here are opaque, so this is belt and
    // braces rather than load-bearing — but returning straight alpha would show up as a halo
    // the moment this composes with anything that is not.
    float alpha = sampleC.a;
    return float4(srgbToLinear(result) * alpha, alpha);
}
