// The sky behind the world: hashed points on three lattices, so the field has a
// few bright stars over many faint ones rather than one even sprinkle.
//
// A user shader returns sRGB, so these are tones picked by eye. They are kept
// low: a camera set for a sunlit planet barely sees stars at all.

// One lattice of stars. Each cell holds at most one, placed by a hash so the
// grid never shows, and `keep` decides how many cells hold anything at all. A
// star is a point, so it is drawn about a pixel wide whatever the lattice, and
// what differs from one to the next is how bright it is. Most are faint: the
// brightness is a hash raised to a power, which is how the real sky is stocked.
static float3 star_layer(float2 uv, float2 resolution, float cells, float keep) {
    float2 g = uv * cells;
    float2 cell = floor(g);
    float h = hash12(cell + 3.7);
    if (h < keep) { return float3(0.0); }
    float2 at = 0.15 + 0.70 * hash22(cell + 11.1);
    float d = length(fract(g) - at) * resolution.y / cells;      // in pixels
    float bright = pow((h - keep) / max(1.0 - keep, 1e-4), 4.0);
    float core = exp(-d * d / (0.30 + 0.55 * bright));
    // Hot stars are blue-white and cool ones orange, with most in between.
    float heat = hash12(cell + 29.3);
    float3 tint = mix(float3(1.00, 0.80, 0.62), float3(0.72, 0.82, 1.00), heat);
    tint = mix(tint, float3(1.0), 0.45);
    return tint * core * (0.10 + 0.90 * bright);
}

float4 shade(float2 uv, ShaderInfo info) {
    float3 col = star_layer(uv, info.resolution, 150.0, 0.86) * 0.50
               + star_layer(uv + 0.37, info.resolution, 64.0, 0.90) * 0.75
               + star_layer(uv + 0.71, info.resolution, 21.0, 0.93) * 1.00;

    // The faintest wash of a galactic band, so the field is not perfectly even.
    float band = exp(-pow((uv.y - 0.34 - 0.12 * uv.x) / 0.20, 2.0));
    col += float3(0.10, 0.11, 0.16) * band * 0.14;

    return float4(col, 1.0);
}
