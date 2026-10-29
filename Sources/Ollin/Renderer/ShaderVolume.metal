#include "Shader3D.metal"

// MARK: - Volumes (`drawVolume`)
//
// A density grid drawn as a participating medium: emission and absorption with
// single scattering of the scene's lights, Max's optical model (1995; the
// sources are credited in ATTRIBUTION.md). Along a view ray the radiance that
// reaches the eye is
//
//     L = integral of T(t) * S(t) dt  +  T(end) * (what is behind),
//     T(t) = exp(-integral of sigma(s) ds over [start, t]),
//
// where sigma is the medium's extinction (`density` times the grid's value) and
// S is the light the medium adds per unit length: its own glow, plus the light
// it scatters toward the eye (`color` times sigma times the light arriving).
// The composite runs after the frame's geometry pass, reading that pass's
// resolved depth, so the march ends at the first solid along the ray and a
// solid inside the volume is veiled by what lies in front of it only. It
// outputs (L, 1 - T(end)), premultiplied, and blends source-over onto the
// frame, which is the second term.
//
// The march takes equal steps, each sample read at a jittered point inside its
// step, and integrates each step exactly under the sample's values: across a
// step of length dt with extinction sigma and source S held constant,
//
//     added = T * S * (1 - exp(-sigma * dt)) / sigma,   T *= exp(-sigma * dt),
//
// the per-step form of Hillaire's energy-conserving integration (2015). A
// uniform medium is therefore exact at any step count, and a thick one
// never adds more than its source over its own extinction.
//
// The light arriving at a point is the scene's lights through the medium's own
// shadow, and with a bounce (`glow.w`, the contribution factor b) the light
// the medium passes on to itself, in the production approximation of
// Wrenninge, Kulla, and Lundqvist (2013): the light is added over N octaves,
// the k-th through a shadow thinned to a^k of the optical depth (light reaches
// deeper), at b^k of the share (less of it), and with the phase's eccentricity
// at c^k of g (spread wider), a = c = 1/2 and b at most 0.43: under the
// thinning, as Hillaire's energy rule (2016) asks (an octave whose share
// outran its thinning would scatter more light than it stops), and set so a
// thick white, even slab lit and seen along its normal reads what the exact
// solution for such a half-space gives, 1.06 of a white matte surface under
// the same light (the thick limit only: the single scattering under it keeps
// the fog's convention, about four times nature's). The shadow grid therefore
// holds optical depth rather than transmittance, so a deep octave still finds
// light where exp(-tau) is below a half float. Every lit step works its light
// out in full: lighting every other step and holding or interpolating it
// between saved nothing measurable on the M2 (the march's cost is in its
// steps and their reads, not in the light; the numbers are in
// DESIGN-NOTES.md). After the march the whole result is veiled by the frame's
// fog as a solid at the medium's mean depth would be.

// `ollin_volume_box` and `ollin_volume_uvw` (the box crossing and the lattice
// coordinate) live in Shader3D.metal beside the solids' read of a cloud's shadow.
static inline float ollin_volume_density(texture3d<float> grid, float3 p, float3 n) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    return max(grid.sample(s, ollin_volume_uvw(p, n)).r, 0.0);
}

// The light-transmittance grid: from each of its lattice points, how much of a
// light survives the volume's own medium on the way there (Behrens and
// Ratering's light attenuation volume, 1998), stored as the optical depth
// along that ray (the transmittance is exp of its negative), so the bounce's
// thinned octaves and a thick medium's deep interior keep their precision.
// Worked out once per light, and again only when the volume, its placement,
// or the light changes, so a view sample reads its self-shadow with one
// trilinear tap instead of marching toward every light.
// `lightRay` is the direction to the light (w = 0) or its position (w = 1), in
// world space; the march walks the world ray, so its steps are world distances.
kernel void ollin_volume_light_kernel(texture3d<float, access::write> out [[texture(0)]],
                                      texture3d<float> grid [[texture(1)]],
                                      constant OllinVolumeDraw &vol [[buffer(0)]],
                                      constant float4 &lightRay [[buffer(1)]],
                                      uint3 gid [[thread_position_in_grid]]) {
    uint3 size = uint3(out.get_width(), out.get_height(), out.get_depth());
    if (any(gid >= size)) return;
    float3 n = float3(grid.get_width(), grid.get_height(), grid.get_depth());
    float3 p = float3(gid) / float3(size - 1) - 0.5;
    float3 world = (vol.model * float4(p, 1.0)).xyz;
    float3 toLight;
    float reach = INFINITY;
    if (lightRay.w == 0.0) {
        toLight = normalize(lightRay.xyz);
    } else {
        float3 v = lightRay.xyz - world;
        reach = length(v);
        toLight = v / max(reach, 1e-6);
    }
    float3 d = (vol.inverseModel * float4(toLight, 0.0)).xyz;
    float tEnd = min(ollin_volume_box(p, d).y, reach);
    float tau = 0.0;
    if (tEnd > 0.0) {
        // A step of one sample spacing: the grid holds nothing finer. Its own
        // spacing, not the view march's step, which follows the quality tier.
        float finest = 1.0 / (max(max(n.x, n.y), n.z) - 1.0);
        float stepLength = finest / max(length(d), 1e-6);
        int steps = clamp(int(ceil(tEnd / stepLength)), 1, 1024);
        float dt = tEnd / float(steps);
        for (int i = 0; i < steps; i++) {
            tau += ollin_volume_density(grid, p + d * ((float(i) + 0.5) * dt), n) * dt;
        }
    }
    out.write(float4(vol.medium.x * tau), gid);
}

// Which blocks of a grid hold any medium, for the march to stride through the
// ones that hold none. One thread a block of OLLIN_VOLUME_BLOCK lattice cells a
// side, writing 1 when any sample a trilinear read inside the block can reach
// is above zero: the block's own samples and one more on every side, so a read
// a rounding step past a face, or one the filter takes from the neighboring
// texel, is still covered. A block of 0 therefore reads exactly zero anywhere
// in it, and a march that skips it adds nothing it would have added.
//
// A held block also widens the grid's tight box, the span of fine blocks that
// hold anything (`bounds`: the lowest block per axis, then the highest one's
// complement, all folded with atomic minimums from the 0xFFFFFFFF that
// `ollin_volume_bounds_reset_kernel` leaves): every point outside it lies in an
// empty block, so a ray reads nothing before it enters that box or after it
// leaves.
kernel void ollin_volume_bounds_reset_kernel(device atomic_uint *bounds [[buffer(0)]],
                                             uint gid [[thread_position_in_grid]]) {
    if (gid < 6) atomic_store_explicit(&bounds[gid], 0xFFFFFFFFu, memory_order_relaxed);
}

kernel void ollin_volume_occupancy_kernel(texture3d<uint, access::write> out [[texture(0)]],
                                          texture3d<float> grid [[texture(1)]],
                                          device atomic_uint *bounds [[buffer(0)]],
                                          uint3 gid [[thread_position_in_grid]]) {
    if (any(gid >= uint3(out.get_width(), out.get_height(), out.get_depth()))) return;
    int3 last = int3(grid.get_width(), grid.get_height(), grid.get_depth()) - 1;
    int3 lo = max(int3(gid) * OLLIN_VOLUME_BLOCK - 1, 0);
    int3 hi = min(int3(gid + 1) * OLLIN_VOLUME_BLOCK + 1, last);
    uint held = 0;
    for (int z = lo.z; z <= hi.z && held == 0; z++) {
        for (int y = lo.y; y <= hi.y && held == 0; y++) {
            for (int x = lo.x; x <= hi.x; x++) {
                if (grid.read(uint3(x, y, z)).r > 0.0) { held = 1; break; }
            }
        }
    }
    out.write(uint4(held), gid);
    if (held != 0) {
        for (int axis = 0; axis < 3; axis++) {
            atomic_fetch_min_explicit(&bounds[axis], gid[axis], memory_order_relaxed);
            atomic_fetch_min_explicit(&bounds[3 + axis], ~gid[axis], memory_order_relaxed);
        }
    }
}

// The tight box `bounds` describes, in the unit box: the fine blocks from the
// lowest held one to the highest, corner to corner. Empty (lo above hi) when
// no block holds anything.
static inline void ollin_volume_tight_box(device const uint *bounds, float3 n,
                                          thread float3 &lo, thread float3 &hi) {
    float3 first = float3(bounds[0], bounds[1], bounds[2]);
    float3 last = float3(~bounds[3], ~bounds[4], ~bounds[5]);
    if (bounds[0] == 0xFFFFFFFFu) { lo = float3(1.0); hi = float3(-1.0); return; }
    lo = first * float(OLLIN_VOLUME_BLOCK) / (n - 1.0) - 0.5;
    hi = min((last + 1.0) * float(OLLIN_VOLUME_BLOCK), n - 1.0) / (n - 1.0) - 0.5;
}

// The coarse occupancy: a block of OLLIN_VOLUME_BLOCK fine blocks a side holds
// medium when any of them does. The fine blocks' margins cover the coarse
// block's, so the same exactness carries up.
kernel void ollin_volume_coarse_occupancy_kernel(texture3d<uint, access::write> out [[texture(0)]],
                                                 texture3d<uint> fine [[texture(1)]],
                                                 uint3 gid [[thread_position_in_grid]]) {
    if (any(gid >= uint3(out.get_width(), out.get_height(), out.get_depth()))) return;
    uint3 last = uint3(fine.get_width(), fine.get_height(), fine.get_depth()) - 1;
    uint3 lo = gid * OLLIN_VOLUME_BLOCK;
    uint3 hi = min(lo + (OLLIN_VOLUME_BLOCK - 1), last);
    uint held = 0;
    for (uint z = lo.z; z <= hi.z && held == 0; z++) {
        for (uint y = lo.y; y <= hi.y && held == 0; y++) {
            for (uint x = lo.x; x <= hi.x; x++) {
                if (fine.read(uint3(x, y, z)).r != 0) { held = 1; break; }
            }
        }
    }
    out.write(uint4(held), gid);
}

// Where a ray leaves the empty block around the unit-box point `p`, at the
// coarse size when that block is empty and the fine size when only that one
// is, or -1 when the fine block holds medium. The ray is `o + t * d` in the
// unit box, `n` the grid's samples per axis.
static inline float ollin_volume_empty_exit(texture3d<uint> fine, texture3d<uint> coarse,
                                            float3 p, float3 o, float3 d, float3 n) {
    float3 lattice = (clamp(p, -0.5, 0.5) + 0.5) * (n - 1.0);
    float3 lo;
    float side;
    uint3 coarseLast = uint3(coarse.get_width(), coarse.get_height(), coarse.get_depth()) - 1;
    uint3 coarseBlock = min(uint3(lattice / float(OLLIN_VOLUME_BLOCK * OLLIN_VOLUME_BLOCK)), coarseLast);
    if (coarse.read(coarseBlock).r == 0) {
        side = float(OLLIN_VOLUME_BLOCK * OLLIN_VOLUME_BLOCK);
        lo = float3(coarseBlock) * side;
    } else {
        uint3 fineLast = uint3(fine.get_width(), fine.get_height(), fine.get_depth()) - 1;
        uint3 fineBlock = min(uint3(lattice / float(OLLIN_VOLUME_BLOCK)), fineLast);
        if (fine.read(fineBlock).r != 0) return -1.0;
        side = float(OLLIN_VOLUME_BLOCK);
        lo = float3(fineBlock) * side;
    }
    float3 hi = min(lo + side, n - 1.0);
    float3 safe = select(d, copysign(float3(1e-12), d), fabs(d) < 1e-12);
    float3 far = select(lo, hi, safe > 0.0) / (n - 1.0) - 0.5;
    float3 t = (far - o) / safe;
    return min(min(t.x, t.y), t.z);
}

struct OllinVolumeOut {
    float4 position [[position]];
    float2 clipXY;
};

// One oversized triangle over the whole target; the scissor bounds it to the
// box's footprint on screen.
vertex OllinVolumeOut ollin_volume_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    OllinVolumeOut out;
    out.clipXY = p * 2.0 - 1.0;
    out.position = float4(out.clipXY, 0.0, 1.0);
    return out;
}

// The octaves the bounce adds over the first (Wrenninge's N); with b = 0 the
// loop ends after one, which is single scattering.
#define OLLIN_VOLUME_OCTAVES 8

// The light the scene's lights deliver to the unit-box point `p` (the world
// point `world`) toward the eye along `rd`: each lit light's reach, cone, and
// shaping, the solids' shadow through its 2D map, the medium's own shadow
// through its optical-depth grid (the first four lit lights have one), and
// the phase, summed over the bounce's octaves. Without the ambient, which the
// caller adds once.
static float3 ollin_volume_arriving(float3 p, float3 world, float3 rd,
                                    constant OllinVolumeDraw &vol,
                                    constant OllinLighting &light,
                                    int lightCount, thread const int *casterOf,
                                    depth2d_array<float> shadowMap, sampler shadowSamp,
                                    texture3d<float> lit0, texture3d<float> lit1,
                                    texture3d<float> lit2, texture3d<float> lit3,
                                    texture2d_array<float> iesProfiles,
                                    texture2d_array<float> cookies) {
    float g = vol.medium.y;
    float b = vol.glow.w;
    float3 arriving = float3(0.0);
    for (int li = 0; li < lightCount; li++) {
        // Read in place: a copy of the light per step is a large record moved
        // for the two fields shaping may tint.
        constant OllinLight &L = light.lights[li];
        float3 color = L.color.rgb;
        float3 toLight;
        float atten = 1.0;
        if (L.kind == 0) {
            toLight = normalize(L.direction.xyz);
        } else if (L.kind == 1 || L.kind == 2) {
            float3 v = L.position.xyz - world;
            float distance = length(v);
            toLight = v / max(distance, 1e-5);
            atten = ollin_light_reach(distance, L.position.w);
            if (L.kind == 2) {
                atten *= smoothstep(L.cosOuter, L.cosInner,
                                    dot(normalize(L.direction.xyz), -toLight));
            }
            if (atten <= 0.0) continue;
            color *= ollin_light_shaping_tint(L, light, toLight, world, iesProfiles, cookies);
        } else {
            continue;   // the area kinds have no single direction to scatter from
        }
        // The solids' shadow, through the light's 2D map when it has one: a
        // solid blocks every octave, since the bounce thins only the medium.
        int cs = casterOf[li];
        if (cs >= 0) {
            float tap = ollin_fog_shadow_tap(world, light.shadowCasters[cs].lightViewProjection,
                                             (uint)cs, shadowMap, shadowSamp);
            atten *= 1.0 - light.shadowCasters[cs].strength * (1.0 - tap);
            if (atten <= 0.0) continue;
        }
        // The medium's own shadow, as the optical depth toward the light from
        // its grid. A light past the four grids scatters unshadowed, and takes
        // one octave: the bounce stands in for what the shadow took away.
        float tau = 0.0;
        bool shadowed = true;
        if (vol.litLights.x == float(li))      tau = ollin_volume_grid_read(lit0, p);
        else if (vol.litLights.y == float(li)) tau = ollin_volume_grid_read(lit1, p);
        else if (vol.litLights.z == float(li)) tau = ollin_volume_grid_read(lit2, p);
        else if (vol.litLights.w == float(li)) tau = ollin_volume_grid_read(lit3, p);
        else shadowed = false;
        float cosine = dot(toLight, rd);
        float sum = 0.0;
        float share = 1.0, thinning = 1.0, spread = g;
        for (int k = 0; k < OLLIN_VOLUME_OCTAVES; k++) {
            sum += share * exp(-thinning * tau) * ollin_hg_phase(cosine, spread);
            if (!shadowed) break;
            share *= b;
            thinning *= 0.5;
            spread *= 0.5;
            if (share < 1e-4) break;
        }
        arriving += color * (atten * sum);
    }
    return arriving;
}

fragment float4 ollin_volume_fragment(OllinVolumeOut in [[stage_in]],
                                      constant OllinVolumeDraw &vol [[buffer(0)]],
                                      constant OllinLighting &light [[buffer(1)]],
                                      constant Uniforms3D &u [[buffer(2)]],
                                      texture3d<float> grid [[texture(0)]],
                                      depth2d<float> sceneDepth [[texture(1)]],
                                      depth2d_array<float> shadowMap [[texture(2)]],
                                      sampler shadowSamp [[sampler(0)]],
                                      texture3d<float> lit0 [[texture(4)]],
                                      texture3d<float> lit1 [[texture(5)]],
                                      texture3d<float> lit2 [[texture(6)]],
                                      texture3d<float> lit3 [[texture(7)]],
                                      texturecube<float> iblIrradiance [[texture(8)]],
                                      texture2d_array<float> iesProfiles [[texture(10)]],
                                      texture2d_array<float> cookies [[texture(11)]],
                                      texture3d<uint> fineOccupancy [[texture(12)]],
                                      texture3d<uint> coarseOccupancy [[texture(13)]],
                                      device const uint *tightBounds [[buffer(3)]]) {
    // The world ray through this pixel, rebuilt the way the raymarched fields
    // rebuild theirs (the frame's own, jittered view-projection), so the march
    // lines up with the depth it reads.
    float4 nearH = u.inverseViewProjection * float4(in.clipXY, 0.0, 1.0);
    float4 farH  = u.inverseViewProjection * float4(in.clipXY, 1.0, 1.0);
    float3 ro = nearH.xyz / nearH.w;
    float3 rd = normalize(farH.xyz / farH.w - ro);

    // The same ray in the unit box: a linear map, so t stays a world distance.
    float3 o = (vol.inverseModel * float4(ro, 1.0)).xyz;
    float3 d = (vol.inverseModel * float4(rd, 0.0)).xyz;
    float2 span = ollin_volume_box(o, d);
    float t0 = max(span.x, 0.0);
    float t1 = span.y;
    // The first solid along the ray ends the march.
    float z = sceneDepth.read(uint2(in.position.xy));
    if (z < 1.0) {
        float4 hitH = u.inverseViewProjection * float4(in.clipXY, z, 1.0);
        t1 = min(t1, dot(hitH.xyz / hitH.w - ro, rd));
    }
    if (t1 <= t0) discard_fragment();

    float3 n = float3(vol.grid.xyz);
    float span1 = t1 - t0;
    float stepLength = vol.grid.w / max(length(d), 1e-6);
    int steps = clamp(int(ceil(span1 / stepLength)), 1, int(vol.medium.w));
    float dt = span1 / float(steps);
    // The steps that can read anything: those whose samples may fall inside
    // the grid's tight box. The steps keep the places and offsets the whole
    // box gives them, so the ones taken add exactly what a march through
    // every step adds; a ray that misses the tight box adds nothing, which
    // is a discard.
    float3 tightLo, tightHi;
    ollin_volume_tight_box(tightBounds, n, tightLo, tightHi);
    float3 safe = select(d, copysign(float3(1e-12), d), fabs(d) < 1e-12);
    float3 enter3 = (select(tightHi, tightLo, safe > 0.0) - o) / safe;
    float3 leave3 = (select(tightLo, tightHi, safe > 0.0) - o) / safe;
    float enter = max(max(enter3.x, enter3.y), enter3.z);
    float leave = min(min(leave3.x, leave3.y), leave3.z);
    if (any(tightLo > tightHi) || leave <= enter || leave <= t0 || enter >= t1) discard_fragment();
    int firstStep = int(max(floor((enter - t0) / dt), 0.0));
    int endStep = min(int(min(floor((leave - t0) / dt), float(steps))) + 1, steps);
    // Each step reads its sample at its own offset inside the step, a pure
    // function of the pixel and the step (and of the temporal sample, when the
    // frame takes several), so banding becomes fine grain the present dither
    // and the temporal resolve absorb. One offset shared by every step would
    // move them together, and a sharp edge inside the medium (a solid's
    // shadow) would print that shared pattern as streaks along itself.

    float sigmaScale = vol.medium.x;
    bool scatters = vol.scatter.w > 0.0;

    // The light arriving from everywhere at once: the flat ambient, plus the
    // environment's irradiance averaged over the six axes (the isotropic part
    // of what a cloud sees). Unshadowed, read once per pixel.
    float3 ambient = light.ambient.rgb;
    if (scatters && light.iblEnabled != 0) {
        float3 sum = float3(0.0);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3( 1, 0, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(-1, 0, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0,  1, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, -1, 0), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, 0,  1), light, iblIrradiance);
        sum += ollin_ibl_flat_ambient(float3(1.0), float3(0, 0, -1), light, iblIrradiance);
        ambient += sum / 6.0;
    }

    // Each lit light's 2D shadow caster, found once per pixel.
    int lightCount = light.enabled != 0 ? min(light.lightCount, OLLIN_MAX_LIGHTS) : 0;
    int casterOf[OLLIN_MAX_LIGHTS];
    for (int li = 0; li < OLLIN_MAX_LIGHTS; li++) casterOf[li] = -1;
    for (int c = 0; c < light.shadowCasterCount; c++) {
        int li = light.shadowCasters[c].lightIndex;
        if (li >= 0 && li < OLLIN_MAX_LIGHTS && light.shadowCasters[c].kind == 0) casterOf[li] = c;
    }

    float3 radiance = float3(0.0);
    float T = 1.0;
    // Where along the ray the result sits, for the fog's veil: the depth of
    // each step weighted by what it covers of the pixel (which sums to the
    // alpha), and by the light it adds (for a glow that covers nothing).
    float coverDepth = 0.0, lightDepth = 0.0, lightWeight = 0.0;
    for (int i = firstStep; i < endStep; i++) {
        float jitter = fract(ollin_ign(in.position.xy + float(i) * 5.588238) + vol.medium.z);
        float t = t0 + (float(i) + jitter) * dt;
        float3 p = o + d * t;
        float rho = ollin_volume_density(grid, p, n);
        if (rho <= 0.0) {
            // An empty block around this sample: every step whose sample falls
            // before the ray leaves it reads zero too, so the march goes on from
            // the first step that may sample past it, at the place and with the
            // offset it would have reached step by step.
            float leaves = ollin_volume_empty_exit(fineOccupancy, coarseOccupancy, p, o, d, n);
            if (leaves > t) {
                int next = int(min(floor((leaves - t0) / dt), float(steps)));
                i = max(i, next - 1);
            }
            continue;
        }
        float sigma = sigmaScale * rho;
        float3 source = vol.glow.rgb * rho;
        if (scatters && sigma > 0.0) {
            float3 arriving = ambient;
            arriving += ollin_volume_arriving(p, ro + rd * t, rd, vol, light, lightCount, casterOf,
                                              shadowMap, shadowSamp, lit0, lit1, lit2, lit3,
                                              iesProfiles, cookies);
            source += vol.scatter.rgb * sigma * arriving;
        }
        float opticalDepth = sigma * dt;
        float stepT = exp(-opticalDepth);
        // The step's exact integral of T * S under a constant sigma and S; its
        // limit S * dt where the medium blocks nothing (a pure glow).
        float3 added = opticalDepth > 1e-4 ? source * ((1.0 - stepT) / sigma)
                                           : source * dt * (1.0 - 0.5 * opticalDepth);
        float3 stepRadiance = T * added;
        radiance += stepRadiance;
        coverDepth += T * (1.0 - stepT) * t;
        float stepLight = dot(stepRadiance, float3(0.2126, 0.7152, 0.0722));
        lightDepth += stepLight * t;
        lightWeight += stepLight;
        T *= stepT;
        if (T < 1e-4) { T = 0.0; break; }
    }
    float alpha = 1.0 - T;
    // The frame's fog veils the result as it veils a solid standing at the
    // medium's mean depth: the medium's light dimmed by the air in front of it
    // and the air's own light added over the share of the pixel it covers. A
    // glow with no thickness covers nothing, and is only dimmed.
    if (light.fogColor.w > 0.0 && (alpha > 1e-4 || lightWeight > 0.0)) {
        float2 pixel = in.position.xy;
        if (alpha > 1e-4) {
            float3 world = ro + rd * (coverDepth / alpha);
            float3 unveiled = radiance / alpha;
            float3 veiled = (light.fogColor.w > 1.5)
                ? ollin_apply_aerial(unveiled, world, pixel, light, shadowMap, shadowSamp, iesProfiles, cookies)
                : ollin_apply_fog(unveiled, world, pixel, light, shadowMap, shadowSamp, iesProfiles, cookies);
            radiance = veiled * alpha;
        } else {
            float tMean = lightDepth / lightWeight;
            float3 origin = light.cameraPosition.xyz;
            float3 world = ro + rd * tMean;
            float3 v = world - origin;
            float reach = length(v);
            float tau = ollin_fog_optical_depth(origin, v / max(reach, 1e-5), reach,
                                                light.fogParams.x, light.fogParams.y);
            if (light.fogColor.w > 1.5) {
                float3 T3, Lin;
                ollin_aerial_split(tau, rd, light, T3, Lin);
                radiance *= T3;
            } else {
                radiance *= exp(-tau);
            }
        }
    }
    return float4(radiance, alpha);
}
