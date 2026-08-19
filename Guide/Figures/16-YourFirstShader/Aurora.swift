// figure: frame=200
//
// Guide payoff (Chapter 16): an aurora over a ridge, one shader, no assets.
// Curtains of light sway by warped noise, colored by a cosine palette, over
// hashed stars and a noise-drawn horizon.
import Ollin

final class Aurora: Sketch {
    @Param(0...0.4) var sway = 0.18
    @Param(0.5...2.5) var strength = 1.4

    // A computed property, so each frame's shader carries the knobs' current
    // values; the compiled pipeline is cached by source, so this is free.
    var sky: Shader {
        Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float t = info.time * 0.1;
        float sway = param(info, 0);
        float strength = param(info, 1);

        // The curtains: vertical bands whose x is bent by drifting noise, so
        // they ripple like fabric. y1 is height above the horizon.
        float y1 = 1.0 - uv.y;
        float bend = fbm(float2(uv.x * 2.4 + t, uv.y * 1.2 - t * 0.7)) - 0.5;
        float x = uv.x + bend * sway;
        float band = fbm(float2(x * 5.0, t * 1.6));
        band = smoothstep(0.45, 0.85, band) * strength;
        float height = smoothstep(0.1, 0.38, y1) * smoothstep(1.15, 0.4, y1);
        float glow = band * height;

        // Aurora colors from a cosine palette: green cores fading violet as
        // the curtain climbs.
        float3 aurora = palette(0.5 + glow * 0.22 - y1 * 0.3,
                                float3(0.16, 0.5, 0.38), float3(0.24, 0.5, 0.45),
                                float3(1.0, 0.7, 0.6), float3(0.35, 0.5, 0.75));

        // A cold night gradient, stars hashed per cell, brighter ones rarer.
        float3 col = mix(float3(0.01, 0.02, 0.05), float3(0.04, 0.07, 0.14), uv.y);
        float2 cell = floor(uv * info.resolution / 3.0);
        float star = step(0.997, hash12(cell)) * hash12(cell + 7.0);
        col += star * smoothstep(0.6, 0.1, glow);             // curtains outshine stars
        col += aurora * glow;

        // The ridge: a noise horizon, solid black below it.
        float ridge = 0.82 + (fbm(float2(uv.x * 3.0, 4.7)) - 0.5) * 0.12;
        float ground = smoothstep(ridge, ridge + 0.003, uv.y);
        col = mix(col, float3(0.005, 0.008, 0.012), ground);

        return float4(col, 1.0);
    }
    """, params: [Float(sway), Float(strength)])
    }

    override func draw() {
        drawImage(generate(sky).image, 0, 0)
    }
}
