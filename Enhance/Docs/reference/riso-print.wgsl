diagnostic(off,derivative_uniformity);

struct Uniforms {
  colorA: vec4f,
  colorB: vec4f,
  colorC: vec4f,
  params: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var inputTex: texture_2d<f32>;

struct VsIn {
  @location(0) pos: vec2f,
  @location(1) uv: vec2f,
};
struct VsOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex fn vs_main(in: VsIn) -> VsOut {
  var out: VsOut;
  out.position = vec4f(in.pos, 0.0, 1.0);
  out.uv = in.uv;
  return out;
}

fn hash2(p: vec2f) -> f32 {
  var p3 = fract(vec3f(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3f(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn halftone(uv: vec2f, lum: f32, scale: f32, angle: f32) -> f32 {
  let s = sin(angle);
  let c = cos(angle);
  let rotUv = vec2f(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
  let grid = rotUv / scale;
  let cell = floor(grid);
  let local = fract(grid) - vec2f(0.5);
  let dist = length(local);
  let radius = sqrt(1.0 - clamp(lum, 0.0, 1.0)) * 0.5;
  return smoothstep(radius + 0.02, radius - 0.02, dist);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let dims = vec2f(textureDimensions(inputTex, 0));
  let halftoneScale = u.params.x;
  let misreg = u.params.y / dims.x;
  let grain = u.params.z;
  let contrast = u.params.w;

  let colA = u.colorA.rgb;
  let colB = u.colorB.rgb;
  let colC = u.colorC.rgb;

  // Sample with misregistration offsets per channel
  let uvA = uv + vec2f(misreg * 0.7, misreg * 0.3);
  let uvB = uv + vec2f(-misreg * 0.5, misreg * 0.6);
  let uvC = uv;

  let sampleA = textureSample(inputTex, samp, uvA);
  let sampleB = textureSample(inputTex, samp, uvB);
  let sampleC = textureSample(inputTex, samp, uvC);

  // Convert each sample to luminance and apply contrast
  let lumA = dot(sampleA.rgb, vec3f(0.299, 0.587, 0.114));
  let lumB = dot(sampleB.rgb, vec3f(0.299, 0.587, 0.114));
  let lumC = dot(sampleC.rgb, vec3f(0.299, 0.587, 0.114));

  let cLumA = clamp((lumA - 0.5) * contrast + 0.5, 0.0, 1.0);
  let cLumB = clamp((lumB - 0.5) * contrast + 0.5, 0.0, 1.0);
  let cLumC = clamp((lumC - 0.5) * contrast + 0.5, 0.0, 1.0);

  // Tonal separation: shadows -> colorA, midtones -> colorB, highlights -> colorC
  let shadowA = smoothstep(0.5, 0.0, cLumA);
  let midB = 1.0 - abs(cLumB - 0.5) * 2.0;
  let highlightC = smoothstep(0.5, 1.0, cLumC);

  // Pixel coordinates for halftone
  let pixCoord = uv * dims;

  // Halftone each channel at different angles
  let dotA = halftone(pixCoord, 1.0 - shadowA, halftoneScale, 0.2618);
  let dotB = halftone(pixCoord, 1.0 - midB, halftoneScale, 1.309);
  let dotC = halftone(pixCoord, 1.0 - highlightC, halftoneScale, 0.7854);

  // Composite: start with white paper, multiply each ink layer
  var paper = vec3f(0.96, 0.94, 0.92);
  let inkA = mix(vec3f(1.0), colA, dotA);
  let inkB = mix(vec3f(1.0), colB, dotB);
  let inkC = mix(vec3f(1.0), colC, dotC);

  var result = paper * inkA * inkB * inkC;

  // Add grain
  let noise = hash2(pixCoord * 1.7 + vec2f(42.0, 17.0));
  result = result + (noise - 0.5) * grain * 0.3;
  result = clamp(result, vec3f(0.0), vec3f(1.0));

  return vec4f(result, sampleC.a);
}
