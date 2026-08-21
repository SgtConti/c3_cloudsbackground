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
    skyBottom: vec3<f32>,
    cloudType: f32
};

%%SAMPLERFRONT_BINDING%% var samplerFront: sampler;
%%TEXTUREFRONT_BINDING%% var textureFront: texture_2d<f32>;
%%SAMPLERBACK_BINDING%% var samplerBack: sampler;
%%TEXTUREBACK_BINDING%% var textureBack: texture_2d<f32>;
%%SHADERPARAMS_BINDING%% var<uniform> shaderParams: ShaderParams;

// Matches the GLSL `mat2 m = mat2(1.6, 1.2, -1.2, 1.6)` multiply. GLSL builds
// that matrix column by column, so writing the product out by hand here keeps
// the WebGPU cloud field identical to the WebGL one.
fn rot(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
}

// Lattice hash. The usual fract(sin(dot(p, k)) * 43758.5453) needs sin() to stay
// accurate for arguments in the millions - this field reaches 1e5 immediately and
// 1e7 after an hour of wind - and drivers range-reduce sin() very differently
// there. Some collapse it to a handful of values, which turns the cloud field
// into a static repeating pattern with no structure.
//
// This permutation hash uses only exact float arithmetic instead. Every
// intermediate stays under 2^24, the largest being (2*289*34 + 1) * 2*289 =
// 1.14e7, so it is bit-identical on every GPU and driver. cos/sin only ever see
// arguments in [0, 2pi). The cost is that the field repeats every 289 lattice
// cells - about 150,000 layout px at the default Scale, far past what is visible.
fn mod289f(x: f32) -> f32 { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289v(x: vec2<f32>) -> vec2<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: f32) -> f32 { return mod289f(((x * 34.0) + 1.0) * x); }

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let pi = mod289v(p);
    let h = permute(permute(pi.x) + pi.y);
    let a = h * (6.283185307179586 / 289.0);
    // 0.8165 is the RMS length of the old square-distributed gradient, so the
    // noise keeps the amplitude every cloud type is tuned against.
    return vec2<f32>(cos(a), sin(a)) * 0.8165;
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
        p = rot(p);
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
        uv = rot(uv) + vec2<f32>(t, 0.0);
        w = w * 0.72;
    }
    return r;
}

@fragment
fn main(input: FragmentInput) -> FragmentOutput {
    let front = textureSample(textureFront, samplerFront, input.fragUV);
    let back = textureSample(textureBack, samplerBack, input.fragUV);
    let base = front + back * (1.0 - front.a);
    var output: FragmentOutput;

    // Nothing the cloud field produces can survive this, so skip it entirely.
    // Matters most with "Only on transparent" turned up, where the covered part
    // of the screen would otherwise pay for a cloud it then throws away.
    let mask = mix(1.0, 1.0 - front.a, clamp(shaderParams.mask, 0.0, 1.0));
    let visible = clamp(shaderParams.opacity, 0.0, 1.0) * mask;
    if (visible < 0.002) {
        output.color = base;
        return output;
    }

    let nrm = c3_srcOriginToNorm(input.fragUV);
    let layoutPos = c3_getLayoutPos(input.fragUV);
    let wind = vec2<f32>(shaderParams.speedX, shaderParams.speedY) * c3Params.seconds;
    let bob = sin(c3Params.seconds * 0.35 + shaderParams.seed * 3.1) * (0.0025 * clamp(shaderParams.bob, 0.0, 1.0));
    let basePos = layoutPos + wind;
    let cloudScale = max(shaderParams.cloudScale, 0.01);
    var uv = (basePos * 0.0016) * (cloudScale * 1.1) + vec2<f32>(shaderParams.seed, shaderParams.seed);
    uv = uv + vec2<f32>(0.0, bob);

    let density = clamp(shaderParams.density, 0.0, 1.0);
    let softness = clamp(shaderParams.softness, 0.0, 1.0);
    let contrastN = clamp(shaderParams.contrast, 0.0, 1.0);
    let driftN = clamp(shaderParams.drift, 0.0, 1.0);
    let up = 1.0 - clamp(nrm.y, 0.0, 1.0);
    let ct = floor(clamp(shaderParams.cloudType, 0.0, 3.0) + 0.5);

    // All four cloud types run one shared noise pipeline and differ only in how
    // the domain is shaped and how the result is read. Keeping the expensive
    // part branch-free means no duplicated noise work, no extra register
    // pressure, and no dependence on the driver folding uniform branches.
    var stretch = vec2<f32>(1.0);       // domain anisotropy
    var warpVec = vec2<f32>(-1.0);      // how the warp field displaces the domain
    var ridgeScale = vec2<f32>(1.0);    // extra anisotropy for the turbulence term
    var qScale = 0.5;
    var driftLo = 0.002;
    var driftHi = 0.02;
    var needDetail = 1.0;               // the fine-detail pair is only used by 0 and 3

    if (ct > 0.5 && ct < 1.5) {
        stretch = vec2<f32>(0.55, 3.2);
        warpVec = vec2<f32>(-0.5);
        ridgeScale = vec2<f32>(1.6, 0.7);
        driftLo = 0.0012;
        driftHi = 0.012;
        needDetail = 0.0;
    } else if (ct > 1.5 && ct < 2.5) {
        stretch = vec2<f32>(0.62, 3.6);
        warpVec = vec2<f32>(2.4, -0.5);
        ridgeScale = vec2<f32>(2.2, 1.0);
        qScale = 0.6;
        driftLo = 0.0015;
        driftHi = 0.015;
        needDetail = 0.0;
    } else if (ct > 2.5) {
        stretch = vec2<f32>(0.80, 0.52);
        driftLo = 0.003;
        driftHi = 0.028;
    }

    let time = c3Params.seconds * mix(driftLo, driftHi, driftN);
    let timeVec = vec2<f32>(time, 0.0);
    let p = uv * stretch;
    let q = fbm(p * qScale - timeVec);
    let sh = p + warpVec * q + timeVec;
    let r = ridged(sh * ridgeScale, time);
    let f = fbm(sh);

    // Sheets and wisps have no billowing interior to describe, so they skip the
    // fine-detail pair and cost two of the five noise evaluations less.
    var c = 0.0;
    if (needDetail > 0.5) {
        c = fbm(p * 2.0 - timeVec * 2.0) + 0.6 * ridged(p * 3.0 - timeVec * 3.0, time * 0.7);
    }

    let sky = mix(shaderParams.skyTop, shaderParams.skyBottom, clamp(nrm.y, 0.0, 1.0));
    var tintAmt = clamp(shaderParams.skyTint, 0.0, 1.0);
    var cloud = 0.0;
    var cloudCol = vec3<f32>(1.0);

    if (ct < 0.5) {
        // --- 0: Cumulus -----------------------------------------------------
        // Broken puffs over open sky. Unchanged from the original effect.
        var ff = f * 0.9;
        ff = ff * (r + ff);
        let contrast = mix(0.8, 2.2, contrastN);
        let cover = mix(-0.05, 0.28, density);
        let alphaGain = mix(1.8, 6.2, density);
        cloud = smoothstep(mix(0.35, 0.15, softness), mix(0.85, 0.60, softness),
                           (cover + alphaGain * ff * r) * contrast + c * 0.22);
        cloudCol = vec3<f32>(1.1, 1.1, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    } else if (ct < 1.5) {
        // --- 1: Altostratus -------------------------------------------------
        // A closed grey sheet in wide flat layers with no defined cloud edges.
        // Density sets how much light gets through rather than how much of the
        // sky is covered, so the variation stays tonal instead of punching holes.
        let grain = r - 0.698;      // 0.698 is the median of ridged()
        let contrast = mix(0.5, 1.7, contrastN);
        let edge = mix(0.60, 0.24, softness);
        let thin = clamp((f * 5.0 + grain * 0.30) * contrast, -1.5, 1.5);
        let floorA = mix(0.32, 1.0, sqrt(density));
        cloud = clamp(floorA + (1.0 - floorA) * smoothstep(-edge, edge, thin), 0.0, 1.0);
        cloudCol = vec3<f32>(0.80, 0.81, 0.84) * clamp(0.72 + 1.5 * f + 0.16 * grain, 0.0, 1.0);
        tintAmt = tintAmt * 0.30;   // overcast reads grey, not sky-coloured
    } else if (ct < 2.5) {
        // --- 2: Cirrus ------------------------------------------------------
        // Sparse fibrous streaks high in the frame, drawn out along the wind.
        let cover = mix(-0.040, 0.050, density);
        var env = clamp((f - 0.016 + cover) * 22.0, 0.0, 1.0);
        // A power curve leaves the streak ends feathered instead of cut off.
        // Blending env^3 towards env gets the same falloff without a pow().
        env = mix(env * env * env, env, softness);
        let fibre = clamp((r - 0.52) * mix(0.9, 1.9, contrastN), 0.0, 1.0);
        let high = mix(0.72, 1.0, smoothstep(0.95, 0.15, nrm.y));
        cloud = env * mix(0.30, 1.0, fibre) * 0.85 * high;
        cloudCol = vec3<f32>(1.16, 1.16, 1.14) * clamp(0.80 + 6.0 * f + 0.15 * fibre, 0.0, 1.0);
    } else {
        // --- 3: Cumulonimbus ------------------------------------------------
        // A tall billowing mass: lit crown, anvil spreading across the top of
        // the frame, shadowed interior and a dark flat base.
        var ff = f * 0.95;
        ff = ff * (r + ff);
        let anvil = smoothstep(0.70, 1.0, up);
        let body = smoothstep(0.0, 0.34, up);
        let contrast = mix(1.1, 2.6, contrastN) * mix(1.0, 0.68, anvil);
        let cover = mix(-0.12, 0.32, density) + 0.18 * anvil - 0.22 * (1.0 - body);
        let alphaGain = mix(2.4, 5.4, density);
        let dens = cover + alphaGain * ff * r;
        cloud = smoothstep(mix(0.32, 0.14, softness), mix(0.78, 0.52, softness), dens * contrast + c * 0.18);
        cloud = cloud * mix(0.35, 1.0, body);

        // Volume shading for free: the warp field q is already low frequency, so
        // it doubles as a broad light/shadow mask, while dens darkens thick
        // interiors and the base.
        let thick = smoothstep(0.02, 0.55, dens);
        let shadow = smoothstep(-0.03, 0.055, q);
        let lit = clamp(0.38 + 0.30 * c - 0.60 * thick - 0.42 * shadow + 0.42 * up, 0.0, 1.0);
        cloudCol = mix(vec3<f32>(0.26, 0.29, 0.37), vec3<f32>(1.06, 1.05, 1.00), lit);
        tintAmt = tintAmt * mix(0.35, 1.0, lit);
    }

    let result = mix(sky, clamp(tintAmt * sky + cloudCol, vec3<f32>(0.0), vec3<f32>(1.0)), cloud);
    let outA = cloud * visible;
    output.color = vec4<f32>(mix(base.rgb, result, outA), max(base.a, outA));
    return output;
}
