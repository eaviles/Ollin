// The plume's density, one thread per sample of the grid: noise over the box's
// width and depth that repeats over its height, read scrolled up by `rise`
// (0 to 1, one grid height a lap), kept where it rises above a floor that
// climbs away from the column's axis, so the smoke frays at its edge instead
// of ending on the box's faces.
//
// The shared shader library is spliced in ahead of this file (`hash13` comes
// from it), so it writes no includes. The grid is a `ComputeTexture3D`; the
// sketch dispatches this kernel over it every frame with `compute(_:writing:)`
// and draws it with `drawVolume`.

// Value noise whose lattice wraps every `period` cells along y, so a read
// scrolled past the top comes back in at the bottom without a seam.
static float plume_noise(float3 p, float period) {
    float3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float corner[8];
    for (int k = 0; k < 8; k++) {
        float3 c = i + float3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
        c.y -= period * floor(c.y / period);
        corner[k] = hash13(c);
    }
    float x00 = mix(corner[0], corner[1], f.x), x10 = mix(corner[2], corner[3], f.x);
    float x01 = mix(corner[4], corner[5], f.x), x11 = mix(corner[6], corner[7], f.x);
    return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Four octaves of it, each wrapping on twice the period of the last, in 0 to 1.
static float plume_fbm(float3 p, float period) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * plume_noise(p, period);
        p *= 2.0;
        period *= 2.0;
        amp *= 0.5;
    }
    return v / 0.9375;
}

kernel void plume(texture3d<float, access::write> out [[texture(0)]],
                  constant float4 &params [[buffer(11)]],
                  uint3 gid [[thread_position_in_grid]]) {
    uint3 n = uint3(out.get_width(), out.get_height(), out.get_depth());
    if (any(gid >= n)) return;
    float3 uvw = float3(gid) / float3(n - 1);
    float u = uvw.x, v = uvw.y, w = uvw.z;
    float rise = params.x;
    float scrolled = fract(v - rise + 1.0);
    // Four cells of noise over the width and depth, four over one lap of the
    // height, the lap the scroll comes home on.
    float noise = plume_fbm(float3(u * 3.4, scrolled * 4.0, w * 3.4), 4.0);
    float spread = 0.16 + 0.24 * v;
    float2 fromAxis2 = float2(u - 0.5, w - 0.5) / spread;
    float fromAxis = length(fromAxis2);
    float floorLevel = 0.36 + 0.35 * fromAxis * fromAxis + 0.15 * v;
    float ends = min(1.0, v * 10.0) * min(1.0, (1.0 - v) * 2.5);
    out.write(float4(max(0.0, noise - floorLevel) * 5.0 * ends), gid);
}
