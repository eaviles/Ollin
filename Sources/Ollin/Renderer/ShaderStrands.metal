// Strand fields (`drawStrands`): grass-like blades generated entirely on the
// GPU by a mesh pipeline. No vertex, index, or instance buffer exists: the
// object stage culls per tile against the camera and picks a per-tile segment
// count by distance, and the mesh stage synthesizes each blade's ribbon from
// hashes of its index, emitting the solid mesh path's own MeshOut so the
// blades shade through `ollin_mesh_fragment` (lights, shadows received, IBL,
// GI, fog) exactly like any solid mesh. Must follow Shader3D (MeshOut) in the
// segment order; <metal_mesh> is included by ShaderCore.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "Shader3D.metal"

// One object threadgroup per tile: thread 0 tests the tile's AABB against the
// frustum and launches the tile's blade bundles (zero threadgroups = culled).
// The payload hands the mesh stage its tile coordinates and segment count.
struct OllinStrandPayload {
    uint tileX;
    uint tileZ;
    uint segments;     // 1 ... OLLIN_STRAND_MAX_SEGMENTS, from camera distance
};

[[object]] void ollin_strand_object(object_data OllinStrandPayload& payload [[payload]],
                                    metal::mesh_grid_properties grid,
                                    constant OllinStrandParams& p [[buffer(4)]],
                                    uint2 tile [[threadgroup_position_in_grid]],
                                    uint tid [[thread_index_in_threadgroup]]) {
    if (tid != 0) { return; }
    // The tile's world-space AABB: its patch-local box through the field matrix,
    // conservatively bounded by a sphere (the matrix may rotate it).
    float tileEdge = p.patch.z;
    float2 originXZ = float2(-p.patch.x + float(tile.x) * tileEdge,
                             -p.patch.y + float(tile.y) * tileEdge);
    float maxH = p.blade.x * (1.0 + p.blade.y) + p.sway.x;
    float3 localCenter = float3(originXZ.x + tileEdge * 0.5, maxH * 0.5,
                                originXZ.y + tileEdge * 0.5);
    float4 wc = p.fieldModel * float4(localCenter, 1.0);
    float sx = length(p.fieldModel[0].xyz), sy = length(p.fieldModel[1].xyz),
          sz = length(p.fieldModel[2].xyz);
    float radius = 0.5 * length(float3(tileEdge, maxH, tileEdge)) * max(sx, max(sy, sz));
    if (p.cullEnabled != 0) {
        for (uint i = 0; i < 6; i += 1) {
            if (dot(p.planes[i].xyz, wc.xyz) + p.planes[i].w < -radius) {
                grid.set_threadgroups_per_grid(uint3(0, 0, 0));
                return;
            }
        }
    }
    // Segment count from the tile's distance to the eye: full detail inside
    // lod.x, the minimum past lod.y. With LOD off, every tile is full detail.
    uint segments = OLLIN_STRAND_MAX_SEGMENTS;
    if (p.eye.w != 0.0) {
        float d = length(wc.xyz - p.eye.xyz);
        float t = saturate((d - p.lod.x) / max(p.lod.y - p.lod.x, 0.001));
        segments = max(1u, uint(round(mix(float(OLLIN_STRAND_MAX_SEGMENTS), 1.0, t))));
    }
    payload.tileX = tile.x;
    payload.tileZ = tile.y;
    payload.segments = segments;
    uint bundles = (p.bladesPerTile + OLLIN_STRAND_BUNDLE - 1) / OLLIN_STRAND_BUNDLE;
    grid.set_threadgroups_per_grid(uint3(bundles, 1, 1));
}

// The mesh stage: one threadgroup per blade bundle, one thread per blade. Each
// thread synthesizes its blade (position, height, lean, sway, tint, all from
// hashes of the blade's global index) and writes its ribbon into the shared
// mesh at blade-local offsets. Capacity sized in OllinShaderTypes.h: bundle 24
// x (4+1)*2 verts = 240 <= 256, 24 x 4*2 prims = 192 <= 512.
using OllinStrandMesh = metal::mesh<MeshOut, void,
                                    OLLIN_STRAND_BUNDLE * (OLLIN_STRAND_MAX_SEGMENTS + 1) * 2,
                                    OLLIN_STRAND_BUNDLE * OLLIN_STRAND_MAX_SEGMENTS * 2,
                                    metal::topology::triangle>;

[[mesh]] void ollin_strand_mesh(OllinStrandMesh m,
                                const object_data OllinStrandPayload& payload [[payload]],
                                constant OllinStrandParams& p [[buffer(4)]],
                                constant Uniforms3D& u [[buffer(2)]],
                                uint bundle [[threadgroup_position_in_grid]],
                                uint tid [[thread_index_in_threadgroup]]) {
    uint segments = payload.segments;
    uint bladeInTile = bundle * OLLIN_STRAND_BUNDLE + tid;
    bool alive = tid < OLLIN_STRAND_BUNDLE && bladeInTile < p.bladesPerTile;

    // Every thread writes its slots (a dead thread writes degenerate zeros so
    // the mesh's fixed layout stays fully initialized); thread 0 sets the count.
    uint vertsPerBlade = (segments + 1) * 2;
    uint primsPerBlade = segments * 2;
    uint vBase = tid * vertsPerBlade;
    uint iBase = tid * primsPerBlade * 3;

    float tileEdge = p.patch.z;
    uint tileIndex = payload.tileZ * p.tilesX + payload.tileX;
    float seedBase = float(tileIndex) * 131.7 + float(bladeInTile) * 7.13 + p.sway.w;

    MeshOut v;
    v.position = float4(0.0);
    v.worldPos = float3(0.0);
    v.normal = float3(0, 1, 0);
    v.color = float4(0.0);

    if (alive) {
        // The blade's ground point, jittered across the tile.
        float2 cell = hash22(float2(seedBase, seedBase * 1.618));
        float2 originXZ = float2(-p.patch.x + float(payload.tileX) * tileEdge,
                                 -p.patch.y + float(payload.tileZ) * tileEdge);
        float2 rootXZ = originXZ + cell * tileEdge;
        // Per-blade character.
        float3 h3 = hash33(float3(seedBase * 0.731, seedBase * 2.117, seedBase * 0.293));
        float height = p.blade.x * (1.0 + p.blade.y * (h3.x * 2.0 - 1.0));
        float leanAngle = h3.y * 6.28318530718;
        float2 leanDir = float2(cos(leanAngle), sin(leanAngle));
        float lean = p.blade.w * (0.4 + 0.6 * h3.z);
        float phase = h3.y * 6.28318530718;
        float swayNow = sin(p.sway.z * p.sway.y + phase) * p.sway.x;
        float width = p.blade.z;
        float tint = h3.x;

        // The ribbon faces across its own lean, tilted toward up for soft
        // shading (a blade is thin; a hard side normal reads like a wall).
        float3 across = normalize(float3(-leanDir.y, 0.0, leanDir.x));
        float3 bladeNormal = normalize(float3(leanDir.x, 1.6, leanDir.y));

        for (uint s = 0; s <= segments; s += 1) {
            float t = float(s) / float(segments);
            float bendT = t * t;
            float3 local = float3(rootXZ.x + (lean + swayNow) * bendT * leanDir.x,
                                  height * t,
                                  rootXZ.y + (lean + swayNow) * bendT * leanDir.y);
            float halfWidth = width * 0.5 * (1.0 - t * 0.85);
            float3 a = local - across * halfWidth;
            float3 b = local + across * halfWidth;
            float4 wa = p.fieldModel * float4(a, 1.0);
            float4 wb = p.fieldModel * float4(b, 1.0);
            float3 lin0 = p.fieldModel[0].xyz, lin1 = p.fieldModel[1].xyz,
                   lin2 = p.fieldModel[2].xyz;
            float3 n = normalize(cross(lin1, lin2) * bladeNormal.x
                               + cross(lin2, lin0) * bladeNormal.y
                               + cross(lin0, lin1) * bladeNormal.z);
            float4 color = mix(p.lowColor, p.tipColor, t);
            color.rgb *= 0.82 + 0.18 * tint;

            MeshOut va;
            va.worldPos = wa.xyz;
            va.position = u.projection * (u.view * float4(wa.xyz, 1.0));
            va.normal = n;
            va.color = color;
            m.set_vertex(vBase + s * 2, va);
            va.worldPos = wb.xyz;
            va.position = u.projection * (u.view * float4(wb.xyz, 1.0));
            m.set_vertex(vBase + s * 2 + 1, va);
        }
        for (uint s = 0; s < segments; s += 1) {
            uint o = vBase + s * 2;
            uint ii = iBase + s * 6;
            m.set_index(ii + 0, o + 0); m.set_index(ii + 1, o + 2); m.set_index(ii + 2, o + 1);
            m.set_index(ii + 3, o + 1); m.set_index(ii + 4, o + 2); m.set_index(ii + 5, o + 3);
        }
    } else {
        for (uint s = 0; s <= segments; s += 1) {
            m.set_vertex(vBase + s * 2, v);
            m.set_vertex(vBase + s * 2 + 1, v);
        }
        for (uint s = 0; s < segments; s += 1) {
            uint ii = iBase + s * 6;
            for (uint k = 0; k < 6; k += 1) { m.set_index(ii + k, vBase); }
        }
    }
    if (tid == 0) {
        uint blades = min(uint(OLLIN_STRAND_BUNDLE),
                          p.bladesPerTile - bundle * OLLIN_STRAND_BUNDLE);
        m.set_primitive_count(blades * primsPerBlade);
    }
}
