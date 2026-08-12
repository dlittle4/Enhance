// CAUSTIC — the rippling light network you get on the floor of a swimming pool.
//
// This is the effect ROADMAP §2c calls "the one that most needs the kernel", and the reason is
// LEARNINGS 2026-08-10: **discrete structure cannot be built from smeared noise.** A blur averages
// neighbours into a continuous wash, and no later operation can recover which contribution came
// from where — so caustic ridges built from blurred noise read as mush no matter how they are
// tuned. Core Image has no caustic and no Worley/Voronoi generator, and `CICrystallize` exposes
// neither seed nor phase, so it cannot flow between frames.
//
// So the ridges are analytic: a Worley (cellular) field, with the bright network sitting exactly
// on the *cell walls* — the locus where the two nearest feature points are equidistant.

#include <CoreImage/CoreImage.h>
#include <metal_stdlib>

using namespace metal;

constant float kTau = 6.28318530718;

static inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract(float2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}

/// Distances to the nearest and second-nearest feature points, in cell units.
///
/// Each cell's point **orbits a circle with a period of exactly 1 in `phase`**, at a per-cell
/// starting angle. That is what makes the effect loop: advance `phase` by a whole number over the
/// GIF and the last frame is the first frame, with no cross-fade and no visible seam. A drifting
/// or noise-driven animation could not do this.
static inline void worley(float2 uv, float phase, thread float &f1, thread float &f2) {
    float2 cell = floor(uv);
    float2 local = fract(uv);

    f1 = 1e9;
    f2 = 1e9;

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 offset = float2(x, y);
            float2 h = hash22(cell + offset);
            // 0.4 keeps the orbit inside its cell, so the 3x3 neighbourhood is always enough to
            // find the true two nearest points. Widening it would let a point from two cells away
            // become nearest, and the network would tear.
            float2 point = offset + 0.5 + 0.4 * float2(cos(kTau * (phase + h.x)),
                                                       sin(kTau * (phase + h.y)));
            float d = length(point - local);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
}

/// The caustic network at one scale. `f2 - f1` is zero exactly on a cell wall and grows away from
/// it, so inverting a smoothstep of it draws a thin bright curve along every wall.
static inline float causticLayer(float2 uv, float phase, float width) {
    float f1, f2;
    worley(uv, phase, f1, f2);
    return 1.0 - smoothstep(0.0, width, f2 - f1);
}

extern "C" float4 caustic(coreimage::sampler src,
                          float4 tint,
                          float cellSize,
                          float phase,
                          float width,
                          float brightness,
                          float2 origin,
                          coreimage::destination dest) {
    float2 coord = dest.coord();
    float4 base = src.sample(src.transform(coord));

    // Anchored to image content rather than to the frame: `origin` carries the pan so the light
    // stays over the same part of the subject, and `cellSize` already has the zoom folded in.
    float2 uv = (coord - origin) / max(cellSize, 1.0);

    // Two octaves. The second is finer, faster and weaker — real caustics have a coarse network
    // with finer filigree inside it, and a single octave reads as a bare Voronoi diagram.
    //
    // The second octave's time multiplier **must be a whole number**. `phase` completes an
    // integer number of orbits over the GIF, and an integer multiple of an integer is still one;
    // an irrational-looking 1.37 leaves this layer mid-orbit at the wrap and the loop visibly
    // jumps. The spatial offsets can be any value — only time has to divide the loop.
    float ridge = causticLayer(uv, phase, width);
    ridge += 0.5 * causticLayer(uv * 2.03 + 17.0, phase * 2.0, width);
    ridge = clamp(ridge, 0.0, 1.0);

    // Sharpen: caustics are thin and bright rather than broad and soft.
    ridge = pow(ridge, 2.0);

    // Pools of brighter and dimmer network, on a much larger scale than the cells.
    //
    // Without this the web is uniformly lit everywhere and reads as cracked glass rather than as
    // light on water — an even, fully-connected lattice is the giveaway. Real caustics gather
    // into bright patches and fade between them. Loop-safe: the sines are periodic in `phase`
    // with period 1, so they land back where they started at the wrap.
    float swellA = sin(uv.x * 0.7 + kTau * phase) * cos(uv.y * 0.6 - kTau * phase);
    float swellB = sin((uv.x + uv.y) * 0.4 - kTau * phase);
    ridge *= 0.35 + 0.65 * clamp(0.5 + 0.35 * swellA + 0.25 * swellB, 0.0, 1.0);

    // Mostly white, tinted at the fringes. Light is white before it is coloured, so weighting
    // this toward white is what keeps a red swatch reading as *light through water* rather than
    // as fire. The tint arrives as sRGB and this arithmetic is additive light, so it converts to
    // linear first: adding in the wrong space would blow the highlights out and skew the hue.
    float3 tintLinear = pow(max(tint.rgb, 0.0), 2.2);
    float3 light = mix(tintLinear, float3(1.0), pow(ridge, 0.6));

    // Additive, not source-over. Caustics are light landing on the subject, so they add to it and
    // clip at white — a blend would darken the photo wherever the network is dim.
    float alpha = base.a;
    float3 result = base.rgb + light * ridge * brightness * alpha;

    return float4(min(result, alpha), alpha);
}
