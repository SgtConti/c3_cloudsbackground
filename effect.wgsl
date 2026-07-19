// Clouds Background (WebGPU WGSL)
%%FRAGMENTINPUT_STRUCT%%
%%FRAGMENTOUTPUT_STRUCT%%
%%C3PARAMS_STRUCT%%
%%C3_UTILITY_FUNCTIONS%%

struct ShaderParams {
    opacity: f32,
    density: f32,
    cloudScale: f32,
    speedX: f32,
    speedY: f32,
    drift: f32,
    bob: f32,
    contrast: f32,
    softness: f32,
    skyTint: f32,
    mask: f32,
    seed: f32,
    skyTop: vec3<f32>,
    _pad0: f32,
    skyBottom: vec3<f32>
};

%%SAMPLERFRONT_BINDING%% var samplerFront: sampler;
%%TEXTUREFRONT_BINDING%% var textureFront: texture_2d<f32>;
%%SAMPLERBACK_BINDING%% var samplerBack: sampler;
%%TEXTUREBACK_BINDING%% var textureBack: texture_2d<f32>;
%%SHADERPARAMS_BINDING%% var<uniform> shaderParams: ShaderParams;

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let K1 = 0.366025404;
    let K2 = 0.211324865;
    let i = floor(p + (p.x + p.y) * K1);
    let a = p - i + (i.x + i.y) * K2;
    let o = select(vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), a.x > a.y);
    let b = a - o + K2;
    let c = a - 1.0 + 2.0 * K2;
    let h = max(vec3<f32>(0.5) - vec3<f32>(dot(a, a), dot(b, b), dot(c, c)), vec3<f32>(0.0));
    let h4 = h * h * h * h;
    let n = h4 * vec3<f32>(dot(a, hash2(i)), dot(b, hash2(i + o)), dot(c, hash2(i + vec2<f32>(1.0))));
    return dot(n, vec3<f32>(70.0));
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var total = 0.0;
    var amp = 0.1;
    for (var i: i32 = 0; i < 6; i = i + 1) {
        total = total + noise(p) * amp;
        p = vec2<f32>(1.6 * p.x + 1.2 * p.y, -1.2 * p.x + 1.6 * p.y);
        amp = amp * 0.45;
    }
    return total;
}

fn ridged(uv0: vec2<f32>, t: f32) -> f32 {
    var uv = uv0;
    var r = 0.0;
    var w = 0.8;
    for (var i: i32 = 0; i < 7; i = i + 1) {
        r = r + abs(w * noise(uv));
        uv = vec2<f32>(1.6 * uv.x + 1.2 * uv.y, -1.2 * uv.x + 1.6 * uv.y) + vec2<f32>(t, 0.0);
        w = w * 0.72;
    }
    return r;
}

fn smooth01(x: f32, k: f32) -> f32 {
    let a = mix(0.35, 0.15, k);
    let b = mix(0.85, 0.60, k);
    return smoothstep(a, b, x);
}

@fragment
fn main(input: FragmentInput) -> FragmentOutput {
    let front = textureSample(textureFront, samplerFront, input.fragUV);
    let back = textureSample(textureBack, samplerBack, input.fragUV);
    let base = front + back * (1.0 - front.a);
    let nrm = c3_srcOriginToNorm(input.fragUV);
    let layoutPos = c3_getLayoutPos(input.fragUV);
    let wind = vec2<f32>(shaderParams.speedX, shaderParams.speedY) * c3Params.seconds;
    let bob = sin(c3Params.seconds * 0.35 + shaderParams.seed * 3.1) * (0.0025 * clamp(shaderParams.bob, 0.0, 1.0));
    let basePos = layoutPos + wind;
    let cloudScale = max(shaderParams.cloudScale, 0.01);
    var uv = (basePos * 0.0016) * (cloudScale * 1.1) + vec2<f32>(shaderParams.seed, shaderParams.seed);
    uv = uv + vec2<f32>(0.0, bob);

    let drift = mix(0.002, 0.02, clamp(shaderParams.drift, 0.0, 1.0));
    let time = c3Params.seconds * drift;
    let timeVec = vec2<f32>(time, 0.0);
    let q = fbm(uv * 0.5 - timeVec);
    let sh = uv - vec2<f32>(q, q) + timeVec;
    let r = ridged(sh, time);
    var f = fbm(sh) * 0.9;
    f = f * (r + f);
    let c0 = fbm(uv * 2.0 - timeVec * 2.0);
    let c1 = ridged(uv * 3.0 - timeVec * 3.0, time * 0.7);
    let c = c0 + 0.6 * c1;

    let density = clamp(shaderParams.density, 0.0, 1.0);
    let contrast = mix(0.8, 2.2, clamp(shaderParams.contrast, 0.0, 1.0));
    let softness = clamp(shaderParams.softness, 0.0, 1.0);
    let cover = mix(-0.05, 0.28, density);
    let alphaGain = mix(1.8, 6.2, density);
    var cloud = cover + alphaGain * f * r;
    cloud = smooth01(cloud * contrast + c * 0.22, softness);

    let sky = mix(shaderParams.skyTop, shaderParams.skyBottom, clamp(nrm.y, 0.0, 1.0));
    let cloudCol = vec3<f32>(1.1, 1.1, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    let result = mix(sky, clamp(shaderParams.skyTint * sky + cloudCol, vec3<f32>(0.0), vec3<f32>(1.0)), cloud);
    let mask = mix(1.0, 1.0 - front.a, clamp(shaderParams.mask, 0.0, 1.0));
    let outA = cloud * clamp(shaderParams.opacity, 0.0, 1.0) * mask;
    var output: FragmentOutput;
    output.color = vec4<f32>(mix(base.rgb, result, outA), max(base.a, outA));
    return output;
}
