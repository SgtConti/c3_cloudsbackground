// Clouds Background (WebGL)
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
uniform float uSeed;

float hash12(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p){
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++){
        v += a * noise(p);
        p = mat2(1.6, 1.2, -1.2, 1.6) * p + vec2(11.7, 7.3);
        a *= 0.5;
    }
    return v;
}
float ridged(vec2 p){
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 5; i++){
        v += a * (1.0 - abs(2.0 * noise(p) - 1.0));
        p = mat2(1.6, 1.2, -1.2, 1.6) * p + vec2(5.1, 3.9);
        a *= 0.58;
    }
    return v;
}

void main(void){
    vec4 front = texture2D(samplerFront, vTex);
    vec4 back = texture2D(samplerBack, vTex);
    vec4 base = front + back * (1.0 - front.a);
    vec2 n = (vTex - srcOriginStart) / max(srcOriginEnd - srcOriginStart, vec2(1e-6));
    vec2 layoutPos = mix(layoutStart, layoutEnd, n);
    vec2 wind = vec2(uSpeedX, uSpeedY) * seconds;
    float bob = sin(seconds * 0.35 + uSeed * 3.1) * (1.5 * clamp(uBob, 0.0, 1.0));
    float featureScale = max(uScale, 0.05);
    vec2 uv = (layoutPos + wind + vec2(0.0, bob)) * (0.0016 / featureScale) + vec2(uSeed);
    float drift = mix(0.002, 0.02, clamp(uDrift, 0.0, 1.0));
    vec2 t = vec2(seconds * drift, 0.0);
    float q = fbm(uv * 0.5 - t);
    vec2 sh = uv - vec2(q) + t;
    float r = ridged(sh);
    float f = fbm(sh) * 0.9;
    float c = fbm(uv * 2.0 - t * 2.0) + 0.5 * ridged(uv * 3.0 - t * 2.0);
    float cover = mix(0.08, 0.45, clamp(uDensity, 0.0, 1.0));
    float gain = mix(3.0, 9.0, clamp(uDensity, 0.0, 1.0));
    float cloud = cover + gain * f * (r + f);
    float contrast = mix(0.8, 2.2, clamp(uContrast, 0.0, 1.0));
    float low = mix(0.35, 0.15, clamp(uSoftness, 0.0, 1.0));
    float high = mix(0.85, 0.60, clamp(uSoftness, 0.0, 1.0));
    cloud = smoothstep(low, high, cloud * contrast + c * 0.25);
    vec3 sky = mix(uSkyTop, uSkyBottom, clamp(n.y, 0.0, 1.0));
    vec3 cloudCol = vec3(1.05, 1.05, 0.95) * clamp(0.55 + 0.45 * c, 0.0, 1.0);
    vec3 result = mix(sky, clamp(uSkyTint * sky + cloudCol, 0.0, 1.0), cloud);
    float mask = mix(1.0, 1.0 - front.a, clamp(uMask, 0.0, 1.0));
    float outA = cloud * clamp(uOpacity, 0.0, 1.0) * mask;
    gl_FragColor = vec4(mix(base.rgb, result, outA), max(base.a, outA));
}
