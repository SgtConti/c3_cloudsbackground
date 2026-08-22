// Clouds Background (WebGL GLSL ES 1.0)
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 vTex;
uniform sampler2D samplerFront;
uniform sampler2D samplerBack;
uniform vec2 srcOriginStart;
uniform vec2 srcOriginEnd;
uniform vec2 layoutStart;
uniform vec2 layoutEnd;
uniform vec2 pixelSize;
uniform float seconds;
uniform float uOpacity;
uniform float uDensity;
uniform float uCloudScale;
uniform float uSpeedX;
uniform float uSpeedY;
uniform float uDrift;
uniform float uBob;
uniform float uContrast;
uniform float uSoftness;
uniform float uSkyTint;
uniform float uMask;
uniform float uSeed;
uniform vec3 uSkyTop;
uniform vec3 uSkyBottom;
uniform float uCloudType;

mat2 m = mat2(1.6, 1.2, -1.2, 1.6);

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
const float MODULUS = 289.0;

float mod289(float x){ return x - floor(x * (1.0 / MODULUS)) * MODULUS; }
vec2 mod289(vec2 x){ return x - floor(x * (1.0 / MODULUS)) * MODULUS; }
float permute(float x){ return mod289(((x * 34.0) + 1.0) * x); }

vec2 hash2(vec2 p){
    vec2 pi = mod289(p);
    float h = permute(permute(pi.x) + pi.y);
    float a = h * (6.283185307179586 / MODULUS);
    // 0.8165 is the RMS length of the old square-distributed gradient, so the
    // noise keeps the amplitude every cloud type is tuned against.
    return vec2(cos(a), sin(a)) * 0.8165;
}

float noise(vec2 p){
    const float K1 = 0.366025404;
    const float K2 = 0.211324865;
    vec2 i = floor(p + (p.x + p.y) * K1);
    vec2 a = p - i + (i.x + i.y) * K2;
    vec2 o = (a.x > a.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec2 b = a - o + K2;
    vec2 c = a - 1.0 + 2.0 * K2;
    vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
    vec3 n = h * h * h * h * vec3(dot(a, hash2(i)), dot(b, hash2(i + o)), dot(c, hash2(i + 1.0)));
    return dot(n, vec3(70.0));
}

float fbm(vec2 n){
    float total = 0.0;
    float amplitude = 0.1;
    for (int i = 0; i < 6; i++){
        total += noise(n) * amplitude;
        n = m * n;
        amplitude *= 0.45;
    }
    return total;
}

float ridged(vec2 uv, float t){
    float r = 0.0;
    float w = 0.8;
    for (int i = 0; i < 7; i++){
        r += abs(w * noise(uv));
        uv = m * uv + vec2(t, 0.0);
        w *= 0.72;
    }
    return r;
}

void main(void){
    vec4 front = texture2D(samplerFront, vTex);
    vec4 back = texture2D(samplerBack, vTex);
    vec4 base = front + back * (1.0 - front.a);

    // Nothing the cloud field produces can survive this, so skip it entirely.
    // Matters most with "Only on transparent" turned up, where the covered part
    // of the screen would otherwise pay for a cloud it then throws away.
    float mask = mix(1.0, 1.0 - front.a, clamp(uMask, 0.0, 1.0));
    float visible = clamp(uOpacity, 0.0, 1.0) * mask;
    if (visible < 0.002){
        gl_FragColor = base;
        return;
    }

    // Construct does not populate every one of these uniforms on every render
    // path, and a rectangle that arrives degenerate has to fall back rather than
    // divide by an epsilon. Dividing by 1e-6 does not guard anything: it scales
    // the field coordinate by a million, so consecutive pixels land thousands of
    // noise cells apart, every pixel hashes as its own cell, and the clouds
    // collapse into single-pixel static. The WebGPU path never hit this because
    // it uses Construct's own c3_getLayoutPos().
    vec2 srcSpan = srcOriginEnd - srcOriginStart;
    vec2 nrm = vTex;
    if (abs(srcSpan.x) > 1e-4 && abs(srcSpan.y) > 1e-4){
        nrm = (vTex - srcOriginStart) / srcSpan;
    }

    // Likewise for the layout rect. Losing it only costs scrolling with the
    // layout, which is a far better failure than not drawing clouds at all.
    vec2 layoutSpan = layoutEnd - layoutStart;
    vec2 layoutPos = nrm * 1000.0;
    if (abs(layoutSpan.x) > 1e-4 && abs(layoutSpan.y) > 1e-4){
        layoutPos = layoutStart + layoutSpan * nrm;
    }
    vec2 wind = vec2(uSpeedX, uSpeedY) * seconds;
    float bob = sin(seconds * 0.35 + uSeed * 3.1) * (0.0025 * clamp(uBob, 0.0, 1.0));
    vec2 basePos = layoutPos + wind;
    float cloudScale = max(uCloudScale, 0.01);
    vec2 uv = (basePos * 0.0016) * (cloudScale * 1.1) + vec2(uSeed, uSeed);
    uv.y += bob;

    float density = clamp(uDensity, 0.0, 1.0);
    float softness = clamp(uSoftness, 0.0, 1.0);
    float contrastN = clamp(uContrast, 0.0, 1.0);
    float driftN = clamp(uDrift, 0.0, 1.0);
    float up = 1.0 - clamp(nrm.y, 0.0, 1.0);
    float ct = floor(clamp(uCloudType, 0.0, 3.0) + 0.5);

    // All four cloud types run one shared noise pipeline and differ only in how
    // the domain is shaped and how the result is read. Keeping the expensive
    // part branch-free means no duplicated noise work, no extra register
    // pressure, and no dependence on the driver folding uniform branches.
    vec2 stretch = vec2(1.0);       // domain anisotropy
    vec2 warpVec = vec2(-1.0);      // how the warp field displaces the domain
    vec2 ridgeScale = vec2(1.0);    // extra anisotropy for the turbulence term
    float qScale = 0.5;
    float driftLo = 0.002;
    float driftHi = 0.02;
    float needDetail = 1.0;         // the fine-detail pair is only used by 0 and 3

    if (ct > 0.5 && ct < 1.5){
        stretch = vec2(0.55, 3.2);
        warpVec = vec2(-0.5);
        ridgeScale = vec2(1.6, 0.7);
        driftLo = 0.0012;
        driftHi = 0.012;
        needDetail = 0.0;
    } else if (ct > 1.5 && ct < 2.5){
        stretch = vec2(0.62, 3.6);
        warpVec = vec2(2.4, -0.5);
        ridgeScale = vec2(2.2, 1.0);
        qScale = 0.6;
        driftLo = 0.0015;
        driftHi = 0.015;
        needDetail = 0.0;
    } else if (ct > 2.5){
        stretch = vec2(0.80, 0.52);
        driftLo = 0.003;
        driftHi = 0.028;
    }

    float time = seconds * mix(driftLo, driftHi, driftN);
    vec2 timeVec = vec2(time, 0.0);
    vec2 p = uv * stretch;
    float q = fbm(p * qScale - timeVec);
    vec2 sh = p + warpVec * q + timeVec;
    float r = ridged(sh * ridgeScale, time);
    float f = fbm(sh);

    // Sheets and wisps have no billowing interior to describe, so they skip the
    // fine-detail pair and cost two of the five noise evaluations less.
    float c = 0.0;
    if (needDetail > 0.5){
        c = fbm(p * 2.0 - timeVec * 2.0) + 0.6 * ridged(p * 3.0 - timeVec * 3.0, time * 0.7);
    }

    vec3 sky = mix(uSkyTop, uSkyBottom, clamp(nrm.y, 0.0, 1.0));
    float tintAmt = clamp(uSkyTint, 0.0, 1.0);
    float cloud = 0.0;
    vec3 cloudCol = vec3(1.0);

    if (ct < 0.5){
        // --- 0: Cumulus -----------------------------------------------------
        // Broken puffs over open sky. Unchanged from the original effect.
        float ff = f * 0.9;
        ff *= (r + ff);
        float contrast = mix(0.8, 2.2, contrastN);
        float cover = mix(-0.05, 0.28, density);
        float alphaGain = mix(1.8, 6.2, density);
        cloud = smoothstep(mix(0.35, 0.15, softness), mix(0.85, 0.60, softness),
                           (cover + alphaGain * ff * r) * contrast + c * 0.22);
        cloudCol = vec3(1.1, 1.1, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    } else if (ct < 1.5){
        // --- 1: Altostratus -------------------------------------------------
        // A closed grey sheet in wide flat layers with no defined cloud edges.
        // Density sets how much light gets through rather than how much of the
        // sky is covered, so the variation stays tonal instead of punching holes.
        float grain = r - 0.698;    // 0.698 is the median of ridged()
        float contrast = mix(0.5, 1.7, contrastN);
        float edge = mix(0.60, 0.24, softness);
        float thin = clamp((f * 5.0 + grain * 0.30) * contrast, -1.5, 1.5);
        float floorA = mix(0.32, 1.0, sqrt(density));
        cloud = clamp(floorA + (1.0 - floorA) * smoothstep(-edge, edge, thin), 0.0, 1.0);
        cloudCol = vec3(0.80, 0.81, 0.84) * clamp(0.72 + 1.5 * f + 0.16 * grain, 0.0, 1.0);
        tintAmt *= 0.30;    // overcast reads grey, not sky-coloured
    } else if (ct < 2.5){
        // --- 2: Cirrus ------------------------------------------------------
        // Sparse fibrous streaks high in the frame, drawn out along the wind.
        float cover = mix(-0.040, 0.050, density);
        float env = clamp((f - 0.016 + cover) * 22.0, 0.0, 1.0);
        // A power curve leaves the streak ends feathered instead of cut off.
        // Blending env^3 towards env gets the same falloff without a pow().
        env = mix(env * env * env, env, softness);
        float fibre = clamp((r - 0.52) * mix(0.9, 1.9, contrastN), 0.0, 1.0);
        float high = mix(0.72, 1.0, smoothstep(0.95, 0.15, nrm.y));
        cloud = env * mix(0.30, 1.0, fibre) * 0.85 * high;
        cloudCol = vec3(1.16, 1.16, 1.14) * clamp(0.80 + 6.0 * f + 0.15 * fibre, 0.0, 1.0);
    } else {
        // --- 3: Cumulonimbus ------------------------------------------------
        // A tall billowing mass: lit crown, anvil spreading across the top of
        // the frame, shadowed interior and a dark flat base.
        float ff = f * 0.95;
        ff *= (r + ff);
        float anvil = smoothstep(0.70, 1.0, up);
        float body = smoothstep(0.0, 0.34, up);
        float contrast = mix(1.1, 2.6, contrastN) * mix(1.0, 0.68, anvil);
        float cover = mix(-0.12, 0.32, density) + 0.18 * anvil - 0.22 * (1.0 - body);
        float alphaGain = mix(2.4, 5.4, density);
        float dens = cover + alphaGain * ff * r;
        cloud = smoothstep(mix(0.32, 0.14, softness), mix(0.78, 0.52, softness), dens * contrast + c * 0.18);
        cloud *= mix(0.35, 1.0, body);

        // Volume shading for free: the warp field q is already low frequency, so
        // it doubles as a broad light/shadow mask, while dens darkens thick
        // interiors and the base.
        float thick = smoothstep(0.02, 0.55, dens);
        float shadow = smoothstep(-0.03, 0.055, q);
        float lit = clamp(0.38 + 0.30 * c - 0.60 * thick - 0.42 * shadow + 0.42 * up, 0.0, 1.0);
        cloudCol = mix(vec3(0.26, 0.29, 0.37), vec3(1.06, 1.05, 1.00), lit);
        tintAmt *= mix(0.35, 1.0, lit);
    }

    vec3 result = mix(sky, clamp(tintAmt * sky + cloudCol, 0.0, 1.0), cloud);
    float outA = cloud * visible;
    gl_FragColor = vec4(mix(base.rgb, result, outA), max(base.a, outA));
}
