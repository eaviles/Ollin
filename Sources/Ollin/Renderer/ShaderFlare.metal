// MARK: - Lens flare
//
// The camera's own contribution to the picture. A bright source does not only
// light the scene: some of it reflects off the lens's interfaces instead of
// passing through them, comes back down the barrel, and lands on the sensor
// somewhere it does not belong. That misplaced light is a ghost, and a row of
// ghosts along the line from the source through the middle of the frame is what
// a lens flare is.
//
// The optics are worked out on the CPU (see `LensFlare.swift`), which leaves the
// fragment with almost nothing to do. First-order optics is linear, so each
// ghost maps a point on the front opening to the sensor by one scale and one
// shift. The fragment runs that map *backwards*: from the pixel it is shading to
// the point on the opening whose light would have landed there. Then it asks two
// questions. Did that point start inside the front opening? Did it clear the
// iris? Light that answers yes to both is this ghost's contribution here.
//
// Coordinates are y-normalized: y runs -1…1 over the frame's height and x is
// scaled by the aspect, so a round lens stays round on a wide canvas.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"

// How far a pixel is from the edge of the iris opening, negative inside. A round
// iris is a circle; a bladed one is a regular polygon, which is what gives a
// stopped-down ghost its flat sides. The fold uses a floored modulo, since
// `fmod` truncates and would break the wedge for a negative angle.
static inline float ollin_flare_iris_distance(float2 p, float radius,
                                              float blades, float roll) {
    if (blades < 2.5) { return length(p) - radius; }
    float wedge = M_PI_F / blades;
    float a = atan2(p.y, p.x) - roll;
    float folded = a - 2.0 * wedge * floor((a + wedge) / (2.0 * wedge));
    return length(p) * cos(folded) - radius * cos(wedge);
}

// How much of each source the camera can actually see, one light per pixel of a
// tiny strip. A flare has to follow the *visible* area of its source: an
// occluder should fade it, not switch it off, so an edge sliding across the sun
// dims the whole flare smoothly. The taps ring the source over the disc it is
// treated as filling, and a tap that falls outside the frame counts as seeing
// it, because a source just off the edge is the classic flare and the depth
// buffer knows nothing about what is out there.
//
// params[0] = (tap radius in uv.y, aspect, light count, depth bias)
// params[1 + i] = (source uv.x, source uv.y, source depth, 1 if this light flares)
fragment float4 ollin_flare_visibility(PresentOut in [[stage_in]],
                                       depth2d<float> depthTex [[texture(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    constexpr sampler dsamp(filter::nearest, address::clamp_to_edge);
    uint index = uint(in.position.x);
    if (float(index) >= params[0].z) { return float4(0.0); }
    float4 light = params[1 + index];
    if (light.w < 0.5) { return float4(0.0); }

    float radius = params[0].x;
    float aspect = max(params[0].y, 1e-4);
    float bias = params[0].w;
    // A ring plus the center, at two radii: enough to read a partial cover
    // smoothly without the cost of a dense disc.
    const int kRing = 8;
    float seen = 0.0, total = 0.0;
    for (int step = 0; step < 3; step++) {
        float r = radius * (float(step) / 2.0);
        int count = step == 0 ? 1 : kRing;
        for (int k = 0; k < count; k++) {
            float phi = (2.0 * M_PI_F) * (float(k) + 0.5 * float(step)) / float(count);
            float2 uv = light.xy + float2(cos(phi) * r / aspect, sin(phi) * r);
            total += 1.0;
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { seen += 1.0; continue; }
            float scene = depthTex.sample(dsamp, uv);
            if (scene > light.z - bias) { seen += 1.0; }
        }
    }
    return float4(total > 0.0 ? seen / total : 0.0);
}

// Add the ghosts to the resolved frame, in linear light and before the tone map,
// because a flare is light arriving at the sensor rather than paint on the
// finished picture.
fragment float4 ollin_flare_composite(PresentOut in [[stage_in]],
                                      texture2d<float> frame [[texture(0)]],
                                      texture2d<float> visibility [[texture(1)]],
                                      texture2d<float> starPattern [[texture(2)]],
                                      sampler samp [[sampler(0)]],
                                      constant OllinLensFlareUniforms &flare [[buffer(0)]]) {
    float4 base = frame.sample(samp, in.uv);
    float pupil = flare.optics.x;
    float iris = flare.optics.y;
    float sensor = flare.optics.z;
    float aspect = flare.optics.w;
    // Where this pixel sits on the frame, and where that is on the sensor in
    // millimeters. The star is placed on the frame and the ghosts on the sensor,
    // which are the same line measured in two units.
    float2 screen = float2((in.uv.x * 2.0 - 1.0) * aspect, 1.0 - in.uv.y * 2.0);
    float2 here = screen * sensor;

    float3 sum = float3(0.0);
    for (int i = 0; i < flare.lightCount; i++) {
        float seen = visibility.read(uint2(uint(i), 0)).x;
        if (seen <= 0.0) { continue; }
        float2 angle = flare.lights[i].xy;
        for (int g = 0; g < flare.ghostCount; g++) {
            float4 ghost = flare.ghosts[g];
            // Backwards through this ghost: the point on the front opening whose
            // light lands here.
            float2 entry = (here - ghost.y * angle) / ghost.x;
            float reach = length(entry);
            if (reach > pupil) { continue; }
            // Forwards again to the iris, which is what shapes the ghost.
            float2 stop = ghost.z * entry + ghost.w * angle;
            float edge = ollin_flare_iris_distance(stop, iris, flare.iris.x, flare.iris.y);
            if (edge >= 0.0) { continue; }
            float shape = clamp(-edge / max(iris * flare.iris.z, 1e-5), 0.0, 1.0);
            float rim = clamp((pupil - reach) / max(pupil * flare.iris.w, 1e-5), 0.0, 1.0);
            sum += flare.tints[i * OLLIN_MAX_FLARE_GHOSTS + g].rgb * (shape * rim * seen);
        }
        // The star sits on the source itself, where the ghosts deliberately do
        // not. Its pattern is the opening's own power spectrum, baked once, so
        // the arms count the blades and their tips fan into color.
        float reachOut = flare.iris.y;
        if (reachOut > 0.0) {
            float2 offset = (screen - flare.lights[i].zw) / reachOut;
            if (abs(offset.x) < 1.0 && abs(offset.y) < 1.0) {
                // The frame measures y upward and the baked pattern downward, so
                // the read turns that axis over. Every regular opening's pattern
                // happens to be even about it, but the coordinate is still the
                // coordinate.
                float2 uv = float2(offset.x * 0.5 + 0.5, 0.5 - offset.y * 0.5);
                float3 pattern = starPattern.sample(samp, uv).rgb;
                sum += pattern * flare.starTints[i].rgb * seen;
            }
        }
    }
    return float4(base.rgb + sum, base.a);
}
