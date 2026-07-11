// Clouds Background (WGSL)
%%FRAGMENTINPUT_STRUCT%%
%%FRAGMENTOUTPUT_STRUCT%%
%%C3PARAMS_STRUCT%%
%%C3_UTILITY_FUNCTIONS%%

struct ShaderParams {
    opacity: f32,
    density: f32,
    scale: f32,
    speedX: f32,
    speedY: f32,
    drift: f32,
    bob: f32,
    contrast: f32,
    softness: f32,
    skyTint: f32,
    skyTop: vec3<f32>,
    _pad0: f32,
    skyBottom: vec3<f32>,
    mask: f32,
    seed: f32
};

%%SAMPLERFRONT_BINDING%% var samplerFront: sampler;
%%TEXTUREFRONT_BINDING%% var textureFront: texture_2d<f32>;
%%SAMPLERBACK_BINDING%% var samplerBack: sampler;
%%TEXTUREBACK_BINDING%% var textureBack: texture_2d<f32>;
%%SHADERPARAMS_BINDING%% var<uniform> shaderParams: ShaderParams;

fn hash12(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn warp(p: vec2<f32>) -> vec2<f32> { return vec2<f32>(1.6 * p.x + 1.2 * p.y, -1.2 * p.x + 1.6 * p.y); }
fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var v = 0.0;
    var a = 0.5;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        v = v + a * noise(p);
        p = warp(p) + vec2<f32>(11.7, 7.3);
        a = a * 0.5;
    }
    return v;
}
fn ridged(p0: vec2<f32>) -> f32 {
    var p = p0;
    var v = 0.0;
    var a = 0.55;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        v = v + a * (1.0 - abs(2.0 * noise(p) - 1.0));
        p = warp(p) + vec2<f32>(5.1, 3.9);
        a = a * 0.58;
    }
    return v;
}

@fragment
fn main(input: FragmentInput) -> FragmentOutput {
    let front = textureSample(textureFront, samplerFront, input.fragUV);
    let back = textureSample(textureBack, samplerBack, input.fragUV);
    let base = front + back * (1.0 - front.a);
    let n = c3_srcOriginToNorm(input.fragUV);
    let layoutPos = c3_getLayoutPos(input.fragUV);
    let wind = vec2<f32>(shaderParams.speedX, shaderParams.speedY) * c3Params.seconds;
    let bob = sin(c3Params.seconds * 0.35 + shaderParams.seed * 3.1) * (1.5 * clamp(shaderParams.bob, 0.0, 1.0));
    let featureScale = max(shaderParams.scale, 0.05);
    var uv = (layoutPos + wind + vec2<f32>(0.0, bob)) * (0.0016 / featureScale) + vec2<f32>(shaderParams.seed);
    let drift = mix(0.002, 0.02, clamp(shaderParams.drift, 0.0, 1.0));
    let t = vec2<f32>(c3Params.seconds * drift, 0.0);
    let q = fbm(uv * 0.5 - t);
    let sh = uv - vec2<f32>(q) + t;
    let r = ridged(sh);
    let f = fbm(sh) * 0.9;
    let c = fbm(uv * 2.0 - t * 2.0) + 0.5 * ridged(uv * 3.0 - t * 2.0);
    let density = clamp(shaderParams.density, 0.0, 1.0);
    let cover = mix(0.08, 0.45, density);
    let gain = mix(3.0, 9.0, density);
    let contrast = mix(0.8, 2.2, clamp(shaderParams.contrast, 0.0, 1.0));
    let low = mix(0.35, 0.15, clamp(shaderParams.softness, 0.0, 1.0));
    let high = mix(0.85, 0.60, clamp(shaderParams.softness, 0.0, 1.0));
    let cloud = smoothstep(low, high, (cover + gain * f * (r + f)) * contrast + c * 0.25);
    let sky = mix(shaderParams.skyTop, shaderParams.skyBottom, clamp(n.y, 0.0, 1.0));
    let cloudCol = vec3<f32>(1.05, 1.05, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    let result = mix(sky, clamp(shaderParams.skyTint * sky + cloudCol, vec3<f32>(0.0), vec3<f32>(1.0)), cloud);
    let mask = mix(1.0, 1.0 - front.a, clamp(shaderParams.mask, 0.0, 1.0));
    let outA = cloud * clamp(shaderParams.opacity, 0.0, 1.0) * mask;
    var output: FragmentOutput;
    output.color = vec4<f32>(mix(base.rgb, result, outA), max(base.a, outA));
    return output;
}
