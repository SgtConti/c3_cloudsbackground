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
uniform float uScale;
uniform float uSpeedX;
uniform float uSpeedY;
uniform float uDrift;
uniform float uBob;
uniform float uContrast;
uniform float uSoftness;
uniform float uSkyTint;
uniform vec3 uSkyTop;
uniform vec3 uSkyBottom;
uniform float uMask;
uniform float uMaskInv;
uniform float uMaskinv;
uniform float uSeed;

mat2 m = mat2(1.6, 1.2, -1.2, 1.6);

vec2 hash2(vec2 p) {
    p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
    return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float noise(vec2 p) {
    const float K1 = 0.366025404;
    const float K2 = 0.211324865;
    vec2 i = floor(p + (p.x+p.y)*K1);
    vec2 a = p - i + (i.x+i.y)*K2;
    vec2 o = (a.x>a.y) ? vec2(1.0,0.0) : vec2(0.0,1.0);
    vec2 b = a - o + K2;
    vec2 c = a - 1.0 + 2.0*K2;
    vec3 h = max(0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
    vec3 n = h*h*h*h*vec3( dot(a,hash2(i+0.0)), dot(b,hash2(i+o)), dot(c,hash2(i+1.0)));
    return dot(n, vec3(70.0));
}

float fbm(vec2 n) {
    float total = 0.0;
    float amplitude = 0.1;
    for (int i = 0; i < 6; i++) {
        total += noise(n) * amplitude;
        n = m * n;
        amplitude *= 0.45;
    }
    return total;
}

float ridged(vec2 uv, float t) {
    float r = 0.0;
    float w = 0.8;
    for (int i=0; i<7; i++){
        r += abs(w * noise(uv));
        uv = m * uv + vec2(t, 0.0);
        w *= 0.72;
    }
    return r;
}

float smooth01(float x, float k){
    float a = mix(0.35, 0.15, k);
    float b = mix(0.85, 0.60, k);
    return smoothstep(a, b, x);
}

void main(void)
{
    vec2 nrm = (vTex - srcOriginStart) / (srcOriginEnd - srcOriginStart);
    vec2 layoutPos = mix(layoutStart, layoutEnd, nrm);
    vec2 p = nrm;
    vec2 wind = vec2(uSpeedX, uSpeedY) * seconds;
    float bob = sin(seconds * 0.35 + uSeed * 3.1) * (0.0025 * clamp(uBob, 0.0, 1.0));
    vec2 basePos = layoutPos + wind;
    const float PERIOD = 4096.0;
    basePos = basePos - floor(basePos / PERIOD) * PERIOD;
    vec2 uv = (basePos * 0.0016) * (uScale * 1.1) + vec2(uSeed, uSeed);
    uv.y += bob;
    float drift = mix(0.002, 0.02, clamp(uDrift, 0.0, 1.0));
    float time = seconds * drift;
    vec2 timeVec = vec2(time, 0.0);
    float q = fbm(uv * 0.5 - timeVec);
    vec2 sh = uv - vec2(q, q) + timeVec;
    float r = ridged(sh, time);
    float f = fbm(sh) * 0.9;
    f *= (r + f);
    float c = fbm(uv * 2.0 - timeVec*2.0);
    float c1 = ridged(uv * 3.0 - timeVec*3.0, time*0.7);
    c = c + 0.6 * c1;
    float density = clamp(uDensity, 0.0, 1.0);
    float contrast = mix(0.8, 2.2, clamp(uContrast, 0.0, 1.0));
    float softness = clamp(uSoftness, 0.0, 1.0);
    float cover = mix(0.08, 0.45, density);
    float alphaGain = mix(3.0, 10.0, density);
    float cloud = cover + alphaGain * f * r;
    cloud = smooth01(cloud * contrast + c * 0.35, softness);
    vec3 sky = mix(uSkyTop, uSkyBottom, p.y);
    vec3 cloudCol = vec3(1.1, 1.1, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    vec3 result = mix(sky, clamp(uSkyTint * sky + cloudCol, 0.0, 1.0), cloud);
    vec4 front = texture2D(samplerFront, vTex);
    vec4 back  = texture2D(samplerBack, vTex);
    vec4 base  = front + back * (1.0 - front.a);
    float mask = mix(1.0, 1.0 - front.a, clamp(uMask, 0.0, 1.0));
    float outA = cloud * clamp(uOpacity, 0.0, 1.0) * mask;
    vec3 outRgb = mix(base.rgb, result, outA);
    gl_FragColor = vec4(outRgb, max(base.a, outA));
}
