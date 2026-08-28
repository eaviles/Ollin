// The sky behind the world: hashed points on two lattices, so the field has a
// few bright stars over many faint ones rather than one even sprinkle.
//
// A user shader returns sRGB, so these are tones picked by eye.

// One lattice of stars. Each cell holds at most one, placed by a hash so the
// grid never shows, and `keep` decides how many cells hold anything at all.
static float star_layer(float2 uv, float cells, float keep, float size) {
    float2 g = uv * cells;
    float2 cell = floor(g);
    float h = hash12(cell + 3.7);
    if (h < keep) { return 0.0; }
    float2 at = hash22(cell + 11.1);
    float d = length(fract(g) - at);
    float falloff = max(0.0, 1.0 - d / size);
    return pow(falloff, 7.0) * (h - keep) / max(1.0 - keep, 1e-4);
}

float4 shade(float2 uv, ShaderInfo info) {
    float faint = star_layer(uv, 190.0, 0.955, 0.55);
    float bright = star_layer(uv, 54.0, 0.972, 0.90);

    // A cold cast on the small ones, a warmer one on the few large ones.
    float3 col = float3(0.72, 0.80, 1.00) * faint * 0.55
               + float3(1.00, 0.94, 0.86) * bright * 1.15;

    // The faintest wash of a galactic band, so the field is not perfectly even.
    float band = exp(-pow((uv.y - 0.34 - 0.12 * uv.x) / 0.20, 2.0));
    col += float3(0.10, 0.11, 0.16) * band * 0.25;

    return float4(col, 1.0);
}
