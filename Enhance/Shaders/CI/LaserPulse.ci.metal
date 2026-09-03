// LASER PULSE — energy shooting out of the eyes.
//
// Modulates a beam or flare layer with rings that expand from the pupil, so the light reads as
// pulses travelling *outward* rather than a steady glow. Rings rather than stripes so one kernel
// serves both looks: the aimed beam (one direction) and the classic edge-to-edge flare (both
// directions at once) both radiate from the same point, and a ring pattern is symmetric about it.
//
// Runs on the *layer*, not the photo: the layer is premultiplied and every channel is scaled by
// the same factor, so a trough dims the light and a crest keeps it, and the photo underneath is
// never touched. Core Image has no ring generator with a controllable phase, which is why this
// is a kernel and not a filter graph.

#include <CoreImage/CoreImage.h>
#include <metal_stdlib>

using namespace metal;

constant float kTau = 6.28318530718;

extern "C" float4 laserPulse(coreimage::sample_t layer,
                             float2 center,
                             float wavelength,
                             float phase,
                             float depth,
                             float sharpness,
                             coreimage::destination dest) {
    float d = distance(dest.coord(), center);
    // Crests move away from `center` as `phase` grows.
    float wave = 0.5 + 0.5 * cos(kTau * (d / max(wavelength, 1.0) - phase));
    // Sharpen the crests into pulses with dark gaps between them; 1.0 is a plain sine.
    wave = pow(wave, max(sharpness, 0.1));
    // Troughs dim by `depth`; crests *overshoot* by up to 60% at full depth, so a pulse is a
    // packet of extra light travelling down a dimmer beam rather than a beam with bites taken
    // out of it. The layer's alpha never exceeds ~0.85, so the overshoot stays in range for the
    // additive composite that follows.
    float factor = (1.0 - depth) + depth * wave * (1.0 + 0.6 * depth);
    return layer * factor;
}
