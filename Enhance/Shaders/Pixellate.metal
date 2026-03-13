#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 pixellate(float2 position, SwiftUI::Layer layer, float size, float2 bounds) {
    float2 pixelCenter = floor(position / size) * size + size * 0.5;
    pixelCenter = clamp(pixelCenter, float2(0.0), bounds - 1.0);
    return layer.sample(pixelCenter);
}
