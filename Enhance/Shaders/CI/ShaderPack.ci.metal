// SHADER PACK — the twelve SwiftUIShaders looks starred in SHADER LAB, ported to Core Image so
// they run in the same `CIImage` pipeline as every other IMAGE effect: the live preview, the
// card thumbnails and the GIF export all read one implementation.
//
// The bodies are the vendored `[[ stitchable ]]` functions from `Shaders/ShaderPack.metal`,
// copied verbatim (Kris Puckett, MIT — see THIRD_PARTY_NOTICES.md). Only the frame around each
// body changes, and that frame is `BCSLayer` below, which stands in for `SwiftUI::Layer`:
//
// - **Origin.** SwiftUI hands a shader top-left-origin points; Core Image's `dest.coord()` is
//   bottom-left. Every body that says "toward the top" or "gravity pulls down" (HEAT SHIMMER's
//   vertical bias, MELT's drip) would run upside down without the flip in `position()` and
//   `sample()`.
// - **Scale.** The pack's pixel constants (a 100px drip, a 16px datamosh block) were tuned on
//   the lab's preview. The kernel runs in a virtual frame `scale` times smaller than the image
//   (`PackShaderEffect` picks the scale so the frame's short side is 650 virtual px, the live
//   preview's size), so a look dialled in on the preview exports the same on a 3000px source.
// - **Colour space.** The context's working space is linear sRGB; the pack's palettes and
//   thresholds (THERMAL's ramp, SOLARIZE's threshold, NEON EDGE's HSB) are sRGB. `sample()`
//   converts in and `finish()` converts out — EFFECTS.md's first "hand-ported shader" rule.
//
// Each kernel takes the pack's own parameters in the pack's own order, after the frame
// arguments (`origin`, `size`, `scale`, `time`). Two colour-only looks (NEON EDGE, SOLARIZE)
// take an extra leading `blend`, since nothing in their bodies reads as an amount.

#include <CoreImage/CoreImage.h>
#include <metal_stdlib>

using namespace metal;

// MARK: - Frame

static inline float3 bcs_linearToSRGB(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
static inline float3 bcs_srgbToLinear(float3 c) { return pow(max(c, 0.0), 2.2); }

struct BCSLayer {
    coreimage::sampler src;
    float2 origin;   // the image extent's origin, working-space pixels
    float2 size;     // the virtual frame, top-left origin, in virtual pixels
    float scale;     // working pixels per virtual pixel

    // The pack's `position`: this destination pixel in the virtual, top-left-origin frame.
    float2 position(float2 coord) const {
        return float2((coord.x - origin.x) / scale, size.y - (coord.y - origin.y) / scale);
    }

    // `SwiftUI::Layer::sample`, minus the layer: clamp to the frame as the pack does, map back to
    // working space, and hand the body sRGB like the layer would have.
    half4 sample(float2 p) const {
        float2 q = clamp(p, float2(0.0), size);
        float2 w = float2(origin.x + q.x * scale, origin.y + (size.y - q.y) * scale);
        float4 c = src.sample(src.transform(w));
        return half4(half3(bcs_linearToSRGB(c.rgb)), half(c.a));
    }
};

static inline float4 bcs_finish(half4 c) {
    return float4(bcs_srgbToLinear(float3(c.rgb)), float(c.a));
}

#define BCS_FRAME(src, origin, size, scale, dest) \
    BCSLayer layer = { src, origin, size, scale }; \
    float2 position = layer.position(dest.coord());

// MARK: - Shared noise utilities (verbatim)

static float bcs_hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float bcs_valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = bcs_hash(i);
    float b = bcs_hash(i + float2(1.0, 0.0));
    float c = bcs_hash(i + float2(0.0, 1.0));
    float d = bcs_hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float bcs_fbm(float2 st, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * bcs_valueNoise(st * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

static half3 bcs_hsb2rgb(half3 c) {
    half3 rgb = clamp(
        abs(fmod(c.x * 6.0h + half3(0.0h, 4.0h, 2.0h), 6.0h) - 3.0h) - 1.0h,
        0.0h, 1.0h
    );
    rgb = rgb * rgb * (3.0h - 2.0h * rgb);
    return c.z * mix(half3(1.0h), rgb, c.y);
}

// MARK: - Heat Shimmer

extern "C" float4 bcs_ci_heatShimmer(coreimage::sampler src, float2 origin, float2 size, float scale,
                                     float time, float amplitude, float frequency, float speed,
                                     float vertical_bias, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;

    float bias = mix(1.0, 1.0 - uv.y, vertical_bias);

    float wave1 = sin(uv.y * frequency + time * speed) * amplitude * bias;
    float wave2 = sin(uv.y * frequency * 1.7 + time * speed * 0.8 + 2.0) * amplitude * 0.5 * bias;

    float waveY = cos(uv.x * frequency * 0.5 + time * speed * 1.2) * amplitude * 0.3 * bias;

    float2 displaced = position + float2(wave1 + wave2, waveY);
    displaced = clamp(displaced, float2(0.0), size);

    return bcs_finish(layer.sample(displaced));
}

// MARK: - Chromatic Split

extern "C" float4 bcs_ci_chromaticSplit(coreimage::sampler src, float2 origin, float2 size, float scale,
                                        float time, float spread, float angle, float edge_only,
                                        float animate, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;

    float2 center = float2(0.5, 0.5);
    float dist = distance(uv, center);
    float mask = mix(1.0, smoothstep(0.1, 0.5, dist), edge_only);

    float animatedSpread = spread;
    if (animate > 0.01) {
        animatedSpread += sin(time * 2.0) * spread * 0.3 * animate;
    }

    float effectiveSpread = animatedSpread * mask;

    float2 dir = float2(cos(angle), sin(angle)) * effectiveSpread;

    half4 r = layer.sample(position + dir);
    half4 g = layer.sample(position);
    half4 b = layer.sample(position - dir);

    return bcs_finish(half4(r.r, g.g, b.b, g.a));
}

// MARK: - Live Ripple

extern "C" float4 bcs_ci_liveRipple(coreimage::sampler src, float2 origin, float2 size, float scale,
                                    float time, float amplitude, float frequency, float speed,
                                    float damping, float ring_count, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float aspectRatio = size.x / size.y;

    float2 totalOffset = float2(0.0);

    for (int i = 0; i < int(ring_count); i++) {
        float phase = float(i) * 1.256;
        float2 ringCenter = center + float2(
            sin(time * 0.3 + phase) * 0.05,
            cos(time * 0.4 + phase) * 0.05
        );

        float2 delta = uv - ringCenter;
        delta.x *= aspectRatio;
        float dist = length(delta);

        float wave = sin(dist * frequency - time * speed + phase);

        float envelope = exp(-dist * damping);

        float2 dir = dist > 0.001 ? normalize(delta) : float2(0.0);
        dir.x /= aspectRatio;

        totalOffset += dir * wave * envelope * amplitude / ring_count;
    }

    float2 displaced = clamp(position + totalOffset, float2(0.0), size);
    return bcs_finish(layer.sample(displaced));
}

// MARK: - Pulse / Heartbeat (the ZOOM tab's HEART BEAT)

extern "C" float4 bcs_ci_pulse(coreimage::sampler src, float2 origin, float2 size, float scale,
                               float time, float amplitude, float bpm, float sharpness,
                               float glow_intensity, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;
    float dist = length(delta);

    float beatFreq = bpm / 60.0;
    float beat = sin(time * beatFreq * 3.14159 * 2.0);
    beat = pow(abs(beat), 1.0 / sharpness) * sign(beat);
    beat = beat * 0.5 + 0.5;

    float2 dir = dist > 0.001 ? normalize(delta) : float2(0.0);
    float displacement = beat * amplitude * smoothstep(0.0, 0.3, dist);

    float2 displaced = position + dir * displacement;
    displaced = clamp(displaced, float2(0.0), size);

    half4 color = layer.sample(displaced);

    float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float edgeGlow = (1.0 - smoothstep(0.0, 0.15, edgeDist)) * beat * glow_intensity;
    color.rgb += half3(edgeGlow * 0.5, edgeGlow * 0.3, edgeGlow * 0.6);

    return bcs_finish(color);
}

// MARK: - Wave Pool

extern "C" float4 bcs_ci_wavePool(coreimage::sampler src, float2 origin, float2 size, float scale,
                                  float time, float amplitude, float wavelength, float speed,
                                  float complexity, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    float2 totalOffset = float2(0.0);

    int waves = int(complexity);

    for (int i = 0; i < waves; i++) {
        float angle = float(i) * 3.14159 / float(waves);
        float2 dir = float2(cos(angle), sin(angle));

        float phase = dot(uv, dir) * wavelength + time * speed + float(i) * 1.5;
        float wave = sin(phase);

        float2 perpDir = float2(-dir.y, dir.x);
        totalOffset += perpDir * wave * amplitude / float(waves);
    }

    float2 displaced = clamp(position + totalOffset, float2(0.0), size);
    return bcs_finish(layer.sample(displaced));
}

// MARK: - Melt

extern "C" float4 bcs_ci_melt(coreimage::sampler src, float2 origin, float2 size, float scale,
                              float time, float melt_amount, float drip_scale, float speed,
                              float heat, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;

    float column = uv.x * drip_scale;
    float dripNoise = bcs_fbm(float2(column, time * speed * 0.3), 4);
    float dripNoise2 = bcs_fbm(float2(column * 1.7 + 3.0, time * speed * 0.25), 3);

    float gravity = uv.y * uv.y;
    float drip = (dripNoise * 0.7 + dripNoise2 * 0.3) * melt_amount * gravity;

    float wobble = sin(uv.y * 10.0 + time * speed * 2.0 + dripNoise * 5.0) * melt_amount * 0.05 * gravity;

    float2 displaced = position + float2(wobble, -drip);
    displaced = clamp(displaced, float2(0.0), size);

    half4 color = layer.sample(displaced);

    float meltFactor = drip / max(melt_amount, 1.0);
    color.r += half(meltFactor * heat * 0.3);
    color.g -= half(meltFactor * heat * 0.1);
    color.b -= half(meltFactor * heat * 0.2);

    float dripEdge = abs(bcs_fbm(float2(column + 0.01, time * speed * 0.3), 4) - dripNoise);
    float specular = pow(dripEdge * 5.0, 3.0) * gravity * 0.4;
    color.rgb += half3(specular);

    return bcs_finish(color);
}

// MARK: - Neon Edge

extern "C" float4 bcs_ci_neonEdge(coreimage::sampler src, float2 origin, float2 size, float scale,
                                  float time, float blend, float edge_strength, float glow_amount,
                                  float color_cycle, float mix_original, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    half4 original = layer.sample(position);

    float step_x = 1.0;
    float step_y = 1.0;

    half4 tl = layer.sample(position + float2(-step_x, -step_y));
    half4 tc = layer.sample(position + float2(0, -step_y));
    half4 tr = layer.sample(position + float2(step_x, -step_y));
    half4 ml = layer.sample(position + float2(-step_x, 0));
    half4 mr = layer.sample(position + float2(step_x, 0));
    half4 bl = layer.sample(position + float2(-step_x, step_y));
    half4 bc = layer.sample(position + float2(0, step_y));
    half4 br = layer.sample(position + float2(step_x, step_y));

    float ltl = dot(float3(tl.rgb), float3(0.299, 0.587, 0.114));
    float ltc = dot(float3(tc.rgb), float3(0.299, 0.587, 0.114));
    float ltr = dot(float3(tr.rgb), float3(0.299, 0.587, 0.114));
    float lml = dot(float3(ml.rgb), float3(0.299, 0.587, 0.114));
    float lmr = dot(float3(mr.rgb), float3(0.299, 0.587, 0.114));
    float lbl = dot(float3(bl.rgb), float3(0.299, 0.587, 0.114));
    float lbc = dot(float3(bc.rgb), float3(0.299, 0.587, 0.114));
    float lbr = dot(float3(br.rgb), float3(0.299, 0.587, 0.114));

    float gx = -ltl - 2.0*lml - lbl + ltr + 2.0*lmr + lbr;
    float gy = -ltl - 2.0*ltc - ltr + lbl + 2.0*lbc + lbr;
    float edgeMag = sqrt(gx*gx + gy*gy) * edge_strength;
    edgeMag = clamp(edgeMag, 0.0, 1.0);

    float edgeAngle = atan2(gy, gx);
    float hue = fract(edgeAngle / 6.2832 + time * color_cycle * 0.3 + uv.y * 0.5);
    half3 neonColor = bcs_hsb2rgb(half3(half(hue), 1.0h, 1.0h));

    float bloom = pow(edgeMag, 0.7) * glow_amount;

    half3 darkBG = original.rgb * half(mix_original * 0.5);
    half3 neon = neonColor * half(edgeMag + bloom);

    half4 result = half4(darkBG + neon, original.a);
    return bcs_finish(mix(original, result, half(blend)));
}

// MARK: - Pixelate Storm

extern "C" float4 bcs_ci_pixelateStorm(coreimage::sampler src, float2 origin, float2 size, float scale,
                                       float time, float pixel_size, float storm_amount, float swirl,
                                       float pulse, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);

    float pxSize = pixel_size * (1.0 + sin(time * pulse) * 0.3 * storm_amount);

    float2 delta = uv - center;
    float dist = length(delta);
    float angle = atan2(delta.y, delta.x);
    float swirlAngle = swirl * (1.0 - dist) * sin(time * 0.5);
    float2 swirledUV = center + dist * float2(cos(angle + swirlAngle), sin(angle + swirlAngle));

    float2 pixelUV = floor(swirledUV * size / pxSize) * pxSize / size;

    float blockRand = bcs_hash(floor(swirledUV * size / pxSize));
    float stormActive = step(1.0 - storm_amount * 0.8, blockRand);
    float2 stormOffset = float2(
        sin(time * 3.0 + blockRand * 20.0) * storm_amount * pxSize * 0.5,
        cos(time * 2.5 + blockRand * 15.0) * storm_amount * pxSize * 0.5
    ) * stormActive;

    float2 samplePos = pixelUV * size + stormOffset;
    samplePos = clamp(samplePos, float2(0.0), size);
    half4 color = layer.sample(samplePos);

    float scanline = sin(position.y * 3.14159 / 2.0) * 0.5 + 0.5;
    color.rgb *= half(0.92 + scanline * 0.08);

    return bcs_finish(color);
}

// MARK: - Shockwave

extern "C" float4 bcs_ci_shockwave(coreimage::sampler src, float2 origin, float2 size, float scale,
                                   float time, float wave_speed, float ring_width, float strength,
                                   float repeat_rate, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float aspectRatio = size.x / size.y;

    float2 delta = uv - center;
    delta.x *= aspectRatio;
    float dist = length(delta) * size.y;

    float cycleTime = fmod(time, repeat_rate);
    float waveFront = cycleTime * wave_speed;

    float ringDist = abs(dist - waveFront);
    float ringMask = 1.0 - smoothstep(0.0, ring_width, ringDist);
    ringMask *= ringMask;

    float fadeWithDist = exp(-waveFront * 0.003);
    ringMask *= fadeWithDist;

    float2 dir = dist > 0.001 ? normalize(delta) : float2(0.0);
    float2 disp = dir * ringMask * strength;

    float waveFront2 = max(cycleTime - 0.15, 0.0) * wave_speed * 0.9;
    float ringDist2 = abs(dist - waveFront2);
    float ringMask2 = 1.0 - smoothstep(0.0, ring_width * 0.7, ringDist2);
    ringMask2 *= ringMask2 * fadeWithDist * 0.5;
    disp += dir * ringMask2 * strength * 0.4;

    float2 samplePos = clamp(position + disp, float2(0.0), size);
    half4 color = layer.sample(samplePos);

    float chromaAmt = ringMask * strength * 0.15;
    float2 chromaDir = float2(dir.x * chromaAmt, dir.y * chromaAmt);
    half4 rSamp = layer.sample(clamp(samplePos + chromaDir, float2(0.0), size));
    half4 bSamp = layer.sample(clamp(samplePos - chromaDir, float2(0.0), size));
    color.r = mix(color.r, rSamp.r, half(ringMask * 0.6));
    color.b = mix(color.b, bSamp.b, half(ringMask * 0.6));

    color.rgb += half3(ringMask * 0.15h);

    return bcs_finish(color);
}

// MARK: - Thermal

extern "C" float4 bcs_ci_thermal(coreimage::sampler src, float2 origin, float2 size, float scale,
                                 float time, float intensity, float shimmer, float noise_speed,
                                 float palette_shift, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;

    float2 st = uv * 8.0;
    float n1 = bcs_valueNoise(st + float2(0.0, time * noise_speed * 2.0));
    float n2 = bcs_valueNoise(st * 1.3 + float2(time * noise_speed * 1.5, 0.0));
    float2 heatDisp = float2(
        (n1 - 0.5) * shimmer,
        (n2 - 0.5) * shimmer * 0.6 - shimmer * 0.3
    );

    float2 samplePos = clamp(position + heatDisp, float2(0.0), size);
    half4 original = layer.sample(samplePos);

    float heat = dot(float3(original.rgb), float3(0.299, 0.587, 0.114));

    heat += (bcs_valueNoise(uv * 20.0 + time * 0.5) - 0.5) * 0.05;
    heat = clamp(heat + palette_shift * 0.3, 0.0, 1.0);

    half3 thermal;
    if (heat < 0.15) {
        thermal = mix(half3(0.0h), half3(0.0h, 0.0h, 0.3h), half(heat / 0.15));
    } else if (heat < 0.35) {
        thermal = mix(half3(0.0h, 0.0h, 0.3h), half3(0.5h, 0.0h, 0.5h), half((heat - 0.15) / 0.2));
    } else if (heat < 0.55) {
        thermal = mix(half3(0.5h, 0.0h, 0.5h), half3(1.0h, 0.0h, 0.0h), half((heat - 0.35) / 0.2));
    } else if (heat < 0.75) {
        thermal = mix(half3(1.0h, 0.0h, 0.0h), half3(1.0h, 0.6h, 0.0h), half((heat - 0.55) / 0.2));
    } else if (heat < 0.9) {
        thermal = mix(half3(1.0h, 0.6h, 0.0h), half3(1.0h, 1.0h, 0.0h), half((heat - 0.75) / 0.15));
    } else {
        thermal = mix(half3(1.0h, 1.0h, 0.0h), half3(1.0h, 1.0h, 1.0h), half((heat - 0.9) / 0.1));
    }

    half3 result = mix(original.rgb, thermal, half(intensity));
    return bcs_finish(half4(result, original.a));
}

// MARK: - Solarize

extern "C" float4 bcs_ci_solarize(coreimage::sampler src, float2 origin, float2 size, float scale,
                                  float time, float blend, float threshold, float curveIntensity,
                                  float colorSeparation, float animate, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    half4 original = layer.sample(position);
    float2 uv = position / size;

    float animOffset = sin(time * 1.5 + uv.x * 3.0) * animate * 0.15;
    float t = threshold + animOffset;

    half3 result;
    for (int ch = 0; ch < 3; ch++) {
        float channelOffset = float(ch) * colorSeparation * 0.08;
        float channelThreshold = t + channelOffset;
        float val = float(original.rgb[ch]);
        float dist = abs(val - channelThreshold);
        float curve = 1.0 - pow(dist * curveIntensity, 2.0);
        curve = clamp(curve, 0.0, 1.0);
        float inverted = 1.0 - val;
        float solarized = mix(val, inverted, curve);
        result[ch] = half(solarized);
    }

    float grain = (bcs_hash(uv * 500.0 + fract(time * 0.1)) - 0.5) * 0.04;
    result += half3(grain);

    return bcs_finish(mix(original, half4(result, original.a), half(blend)));
}

// MARK: - Datamosh

extern "C" float4 bcs_ci_datamosh(coreimage::sampler src, float2 origin, float2 size, float scale,
                                  float time, float blockCorruption, float smearAmount, float colorBleed,
                                  float glitchRate, coreimage::destination dest) {
    BCS_FRAME(src, origin, size, scale, dest)
    float2 uv = position / size;
    half4 original = layer.sample(position);

    float blockSize = 16.0;
    float2 blockUV = floor(uv * size / blockSize) / (size / blockSize);
    float blockHash = bcs_hash(blockUV * 73.0 + floor(time * glitchRate) * 0.1);

    float isCorrupted = step(1.0 - blockCorruption, blockHash);

    if (isCorrupted < 0.5) {
        return bcs_finish(original);
    }

    float smearAngle = bcs_hash(blockUV * 137.0 + floor(time * glitchRate * 0.5) * 0.3) * 6.28;
    float2 smearDir = float2(cos(smearAngle), sin(smearAngle));
    float blockSmear = smearAmount * (0.5 + blockHash * 0.5);
    float2 smearOffset = smearDir * blockSmear;

    float2 smearPos = clamp(position + smearOffset, float2(0.0), size);
    half4 smeared = layer.sample(smearPos);

    float2 rOffset = smearOffset * (1.0 + colorBleed * 0.3);
    float2 bOffset = smearOffset * (1.0 - colorBleed * 0.2);
    half4 rSamp = layer.sample(clamp(position + rOffset, float2(0.0), size));
    half4 bSamp = layer.sample(clamp(position + bOffset, float2(0.0), size));

    half4 result = smeared;
    result.r = mix(smeared.r, rSamp.r, half(colorBleed));
    result.b = mix(smeared.b, bSamp.b, half(colorBleed));

    float quantize = 16.0;
    result.rgb = floor(result.rgb * half(quantize)) / half(quantize);

    float2 blockCell = fract(uv * size / blockSize);
    float blockEdge = 1.0 - step(0.03, min(blockCell.x, blockCell.y));
    result.rgb += half3(blockEdge * 0.1);

    return bcs_finish(result);
}
