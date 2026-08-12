// STRETCH — pixels smeared along a line, the "pixel sorting" / melted-scanline look.
//
// The mechanism from EFFECTS.md → "Pixel stretch": project each pixel onto a line and sample from
// the projection instead of from itself. Every pixel in a perpendicular column then reads the
// *same* source point, which is what draws the streak — the smear is a consequence of collapsing
// one coordinate, not of any blurring.
//
// Built as a kernel rather than as a `CIDisplacementDistortion` field. The displacement route is
// real — this is a per-pixel UV remap, which is exactly what that filter expresses — but it needs
// the offset field built as an image at 8 bits per channel, and long smears then band. The kernel
// gate (ROADMAP §1c) is done, so the exact version is now the cheaper one to write and to read.

#include <CoreImage/CoreImage.h>
#include <metal_stdlib>

using namespace metal;

extern "C" float4 stretch(coreimage::sampler src,
                          float2 centre,
                          float angle,
                          float position,
                          float reach,
                          float strength,
                          coreimage::destination dest) {
    float2 coord = dest.coord();

    // Normal to the smear line. The line runs along (cos, sin); pixels are pulled *across* it.
    float2 normalDir = float2(-sin(angle), cos(angle));

    // How far this pixel sits from the line, signed. `position` slides the line across the frame
    // without rotating it, so ANGLE and POSITION stay independent controls.
    float signedDistance = dot(coord - centre, normalDir) - position;

    // Falloff is on |distance|, so the smear is symmetric either side of the line.
    //
    // Note the inner edge is at 0.6 * reach, not 0. That plateau is the difference between a
    // stretch and a smudge: with the ramp starting at the line itself, only pixels exactly *on*
    // it snapped fully and everything else was partially displaced, which reads as a lens
    // distortion. The plateau gives a solid band that genuinely collapses, and the outer ramp
    // stops it ending on a hard edge — a hard edge reads as a rectangle pasted on the photo.
    float falloff = smoothstep(reach, reach * 0.6, abs(signedDistance));
    float amount = clamp(falloff * strength, 0.0, 1.0);

    // Projection of this pixel onto the line. At amount = 1 the pixel samples exactly there, so a
    // whole perpendicular column collapses onto one source point.
    float2 projected = coord - normalDir * signedDistance;
    float2 source = mix(coord, projected, amount);

    return src.sample(src.transform(source));
}
