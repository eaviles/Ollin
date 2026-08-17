#ifndef OLLIN_SHADER_TYPES_H
#define OLLIN_SHADER_TYPES_H

// Single source of truth for the structs shared between Swift (CPU) and the
// Metal shaders (GPU). Each layout is defined once, here, so a field can never
// drift between the two sides and silently corrupt memory.
//
// It's consumed three ways:
//   - Swift imports it through the `COllinShaders` C module (whose bridge
//     header re-includes this file), so `OllinVertex`, `Uniforms`, and
//     `SDFInstance` are ordinary Swift structs.
//   - `ShaderCore.metal` (the first shader segment) `#include`s it for the
//     GPU-side definitions.
//   - At runtime the shader source is compiled with `makeLibrary(source:)`,
//     which has no include search path, so `MetalRenderer` splices this file's
//     text in place of the `#include` directive. That's why the header ships
//     beside the shader segments as a resource. A precompiled metallib, by
//     contrast, resolves the include at build time and never goes through that.
//
// Vector and matrix fields use the `simd_*` spellings: on the CPU side those
// come from <simd/simd.h> and the Swift importer maps them to
// SIMD2<Float> / SIMD4<Float> / simd_float3x3; on the GPU side they're aliased
// onto Metal's own vector types below.

#ifdef __METAL_VERSION__
// Metal: the vector and matrix types come from <metal_stdlib>, already included
// (with `using namespace metal;`) ahead of this header. Alias the `simd_*`
// names the structs use onto them. Aliasing to the identical type is legal even
// if those names were already visible, so this stays conflict-free.
typedef float2   simd_float2;
typedef float4   simd_float4;
typedef float3x3 simd_float3x3;
typedef float4x4 simd_float4x4;
#else
#include <simd/simd.h>
#endif

// A half-precision float4 shared across the boundary: Metal reads it as a
// native half4; the CPU side stores the four Float16 bit patterns in a
// simd_ushort4 (same 8-byte size and alignment), packed with
// `Float16.bitPattern`. Used where 8 bytes must carry a direction + sign
// (a mesh vertex's tangent) without widening the stride.
#ifdef __METAL_VERSION__
typedef half4 OllinHalf4;
#else
typedef simd_ushort4 OllinHalf4;
#endif

// One vertex of tessellated (triangle-path) geometry: float2 @0, float2 @8,
// float4 @16, for a stride of 32 — `aa` lives in what was the float2→float4
// alignment padding, so the stride (and the triangle buffer/ring) is unchanged.
// The triangle pipeline ignores `aa`; the fringe pipeline (`ollin_fringe_vertex`)
// reads `aa.x` as the AA coverage interpolant, with the stroke's own paint alpha
// in `color.a` — so a fringe vertex carries rgb + paint-alpha + coverage as three
// independent channels (the fragment applies perceptualCoverage to coverage only).
typedef struct {
    simd_float2 position;   // sketch-space, points, top-left origin, y-down
    simd_float2 aa;         // fringe pipeline: x = AA coverage 0…1 (y reserved); ignored elsewhere
    simd_float4 color;      // straight (non-premultiplied) RGBA, 0...1 (fringe: a = paint alpha)
} OllinVertex;

// Per-frame constants, shared by both pipelines.
typedef struct {
    simd_float2 viewport;   // logical canvas size in points (width, height)
    float clipDepth;        // clip-space z (Metal NDC, [0,1]) the 2D vertex shaders
                            // emit, so 2D draws can occlude/be occluded by 3D
                            // geometry in a depth pass (see depth(at:)). 0 in a
                            // 2D-only frame, so those frames are byte-identical.
    float batchTransformed; // 1 while a retained `Batch` replays under a draw-time
                            // CTM: the 2D vertex shaders then left-apply
                            // `batchTransform` to their canvas-space output. 0
                            // everywhere else, so the transform branch is untaken
                            // and the ordinary paths' position math is untouched
                            // (byte-identical, the flag-gate rule).
    simd_float3x3 batchTransform;  // canvas space -> canvas space (the CTM at
                                   // drawBatch time); identity when unused
} Uniforms;

// Per-frame constants for the 3D pipelines (an active `Camera3D`). Bound at
// vertex buffer index 2 — distinct from the 2D `Uniforms` at index 1, so a 3D
// batch and the 2D batches around it (HUD/captions) each read their own without
// rebinding. World space is right-handed, y-up; `view` takes a world point into
// camera space (camera down −z) and `projection` into Metal clip space (z ∈ [0,1]).
typedef struct {
    simd_float4x4 view;        // world -> camera space
    simd_float4x4 projection;  // camera -> clip space (Metal z in [0,1])
    simd_float4x4 inverseViewProjection;  // clip -> world; the raymarch pass rebuilds a
                               // world ray from each pixel's NDC through this. The
                               // mesh/point/wireframe pipelines never read it, so it's
                               // free for them (the field is just set each frame).
    simd_float2 viewport;      // drawable size in points (for any screen-space math)
    simd_float2 raymarchSteps; // the RenderQuality raymarch dial, read only by the raymarch
                               // fragment: .x = camera-march step budget, .y = self-shadow
                               // march budget. Default (128, 48) reproduces the pre-dial
                               // constants exactly, so default-quality snapshots are unchanged.
    simd_float2 raymarchScale; // .x = the raymarch pass's internal render scale (1 = full
                               // resolution): the reduced-res pre-pass traces at
                               // `viewport * scale`, and its pixel-cone AA must match the
                               // texel it actually shades, not the full-res pixel (a cone
                               // sized to the full-res pixel under-blurs the low-res image
                               // and the upsample magnifies the aliasing into a staircase).
                               // Always 1 for the full-res inline march (byte-identical:
                               // `viewport.y * 1` is exact). .y unused.
} Uniforms3D;

// The mover-velocity pass (temporal AA): per-draw constants bound at vertex
// buffer index 3, beside the frame's `Uniforms3D` at 2. `previousViewProjection`
// is last frame's unjittered view·projection (the temporal history's own
// reprojection matrix, so the two never disagree); `previousOfCurrent` takes a
// mover's baked *current* world-space vertex back to where last frame's model
// matrix put it (prevModel · inverse(curModel)), the identity for a mover that
// held still, so a stationary mover writes exactly the camera's own motion.
typedef struct {
    simd_float4x4 previousViewProjection;
    simd_float4x4 previousOfCurrent;
} OllinVelocityUniforms;

// The velocity texture's "nothing written here" sentinel (its clear color's red
// channel). Real velocities are screen-pixel deltas, orders of magnitude
// smaller; the resolve treats any red above half this as a written texel, so a
// NaN (a degenerate mover transform) also reads as unwritten and falls back.
#define OLLIN_VELOCITY_NONE -16384.0f

// One vertex of a textured quad (the image pipeline). Position is already in
// sketch space (the CTM is applied on the CPU, like OllinVertex), `uv` samples
// the image (0,0 top-left … 1,1 bottom-right), and `tint` multiplies the
// sampled color. Stride 32: float2 @0, float2 @8, float4 @16.
typedef struct {
    simd_float2 position;   // sketch-space, points, top-left origin, y-down
    simd_float2 uv;         // texture coordinates, 0...1
    simd_float4 tint;       // straight RGBA multiplier (white = unchanged)
} OllinImageVertex;

// One analytic shape for the instanced-SDF pipeline, drawn as a single quad
// whose fragment computes fill + stroke + anti-aliasing from a signed-distance
// field (no CPU tessellation). A tagged union: `shape` (see `SDFShape` in
// Drawer.swift) picks the SDF and decides how the generic slots
// (size/param0/param1/extra) are read.
//
// float3x3 is 48 bytes (three 16-byte columns); the rest follows simd alignment.
// The three `param*` slots plus `size`/`extra` give shapes their geometry; a
// shape parameterized by three free points (a general triangle's corners, a
// quadratic Bézier's control points) fills `param0`/`param1`/`param2` — `size`
// is reserved as the covering quad's AABB half-extent and can't double as a
// point. Adding `param2` took the stride to 144 (still 16-aligned); the two
// gradient row fields then filled the 8 bytes of tail padding that left, so the
// stride is still 144 with no spare bytes.
//
// Gradient paints ride the existing slots rather than widening the struct: when
// a paint-kind field in `shape` (bits 10-11 for fill, 12-13 for stroke; 0 solid,
// 1 linear, 2 radial, 3 along-path) is non-zero, the matching color slot is
// reinterpreted as gradient *geometry* relative to `center` — linear packs
// (start.xy, end.xy), radial packs (center.xy, radius, unused) — and
// `fillGradient`/`strokeGradient` carry the paint's row in the gradient strip
// texture the ramp was baked into (see BakedGradient).
typedef struct {
    simd_float3x3 transform;   // local sketch space -> sketch space (the CTM)
    simd_float2 center;        // shape center, local sketch space
    simd_float2 size;          // generic half-extent (see SDFShape)
    simd_float4 fillColor;     // straight RGBA; alpha 0 means no fill — or fill-gradient geometry
    simd_float4 strokeColor;   // straight RGBA; alpha 0 means no stroke — or stroke-gradient geometry
    simd_float2 param0;        // shape-specific
    simd_float2 param1;        // shape-specific
    simd_float2 param2;        // shape-specific
    float strokeWidth;         // points; 0 means no stroke
    float extra;               // shape-specific scalar
    float bandWidth;           // hollow-band width (points); 0 means solid fill
    unsigned int shape;        // SDFShape.rawValue + alignment/paint-kind bits (32-bit)
    float fillGradient;        // gradient-strip row index for a gradient fill
    float strokeGradient;      // gradient-strip row index for a gradient stroke
} SDFInstance;

// One instruction of the SDF-combinator "VM" (see ShaderCombinator.metal). A
// composed field (the `SDF` value type) flattens to a flat array of these that the
// fragment interprets with two small fixed-depth stacks — a *value* stack of
// (distance, color) for the combine/modify ops and a *point* stack for the
// transform/domain scopes. Unlike `SDFInstance` (one shape per quad), many nodes
// evaluate at the *same* point and combine, which is why they ride their own buffer.
//
// `kind` is the instruction class; `sel` its sub-selector; the rest are read per
// kind (most fields unused outside EVAL). Leaves carry NO transform — all
// positioning (the shape's own anchor, the user's .at/.rotated/.scaled, and the
// domain ops) is XFORM nodes, so method-chain order is preserved exactly:
//   kind 0 EVAL   leaf: sel = SDFShape tag; evaluate that region SDF
//                 (ollin_sdf_distance) at the current point, push (distance, color).
//                 geo0 = (size.xy, param0.xy), geo1 = (param1.xy, param2.xy),
//                 extra = shape `extra`, color = the leaf's straight RGBA.
//   kind 1 OP     binary combine, pop 2 / push 1: sel = 0 union, 1 smoothUnion,
//                 2 subtract, 3 smoothSubtract, 4 intersect, 5 smoothIntersect,
//                 6 morph. k = smoothing radius (distance units) / morph amount.
//                 The smooth ops lerp color by the smin blend factor.
//   kind 2 MOD    unary value op, pop 1 / push 1: sel = 0 round, 1 onion. k =
//                 radius / thickness.
//   kind 3 XFORM  push the current point, then transform it for the enclosing scope
//                 (a complete child subtree evaluates to one value-stack entry):
//                 sel = 0 translate (geo0.xy), 1 rotate (geo0.xy = cos, sin),
//                 2 scale (k = factor s, applied as p /= s), 3 mirror (geo0 =
//                 (mirrorX flag, mirrorY flag, offX, offY)), 4 repeat (geo0.xy =
//                 spacing, geo1.xy = per-side limit, extra >= 0.5 = limited else
//                 infinite). Translate/rotate/mirror/repeat are rigid (distance
//                 unchanged); scale multiplies the child distance back at RESTORE_P.
//   kind 4 RESTORE_P  pop the point (leave the scope); k = the distance scale to
//                 multiply the child result by (s for a scale scope, else 1).
// Stride 64 (four 16-byte rows), sized to the EVAL case; other kinds use a subset.
typedef struct {
    unsigned int kind;     // 0 EVAL, 1 OP, 2 MOD, 3 XFORM, 4 RESTORE_P
    unsigned int sel;      // shape tag / op kind / mod kind / xform kind
    float k;               // OP smin k or morph; MOD radius/thickness; XFORM scale s; RESTORE_P distance scale
    float extra;           // EVAL shape `extra`; XFORM repeat limited flag
    simd_float4 color;     // EVAL leaf straight RGBA
    simd_float4 geo0;      // EVAL (size.xy, param0.xy); XFORM params
    simd_float4 geo1;      // EVAL (param1.xy, param2.xy); XFORM params
} SDFNode;

// One composed SDF field for the combinator pipeline, drawn as a single covering
// quad (like `SDFInstance`) whose fragment runs the VM over `nodeCount` `SDFNode`s
// starting at `nodeStart` in the shared node buffer. With a solid `fill` the color
// comes from the nodes (each leaf carries its own, baked from the current `fill` at
// flatten time); with a gradient `fill` the whole merged region is painted by
// `fillGradient*` instead (the leaf colors bypassed, like the 3D field — but in
// field/canvas space here, sampled at the field point, not a screen projection). The
// merged-outline *stroke* takes the same treatment (solid `strokeColor`, or a gradient
// whose geometry rides the `strokeColor` slot when `strokeGradientKind != 0`, exactly
// as `SDFInstance` reinterprets its color slots). Stride 128 (16-aligned).
typedef struct {
    simd_float3x3 transform; // local sketch space -> sketch space (the CTM)
    simd_float2 center;      // group center, local sketch space
    simd_float2 size;        // conservative covering-quad half-extent (whole-tree AABB)
    simd_float4 strokeColor; // solid stroke straight RGBA (a=0 none) — or, when
                             // strokeGradientKind != 0, the stroke gradient's geometry
                             // (field coords): linear (start.xy, end.xy), radial (center.xy, radius, _)
    float strokeWidth;       // points; 0 means no stroke
    float bandWidth;         // hollow-band width (points); 0 = solid (reserved)
    unsigned int nodeStart;  // first SDFNode for this group (absolute index)
    unsigned int nodeCount;  // number of nodes
    // Gradient paint (linear/radial; along-path has no single path on a merged field). The
    // fill has no solid slot to reuse (its color is the nodes'), so its geometry is explicit;
    // the stroke reuses `strokeColor`. Sampled at the field point from the baked gradient strip.
    simd_float4 fillGradientGeo; // fill gradient geometry (field coords), read when fillGradientKind != 0
    float fillGradientKind;      // 0 solid (the leaves' own colors), 1 linear, 2 radial
    float fillGradientRow;       // gradient-strip row index for the fill ramp (when kind != 0)
    float strokeGradientKind;    // 0 solid, 1 linear, 2 radial
    float strokeGradientRow;     // gradient-strip row index for the stroke ramp (when kind != 0)
} SDFGroupInstance;

// One instruction of the *3D* SDF-combinator VM (see ShaderRaymarch.metal) — the
// raymarched sibling of `SDFNode`. A composed 3D field (the `SDF3D` value type)
// flattens to a flat array of these that the raymarch fragment walks at each march
// step, with a *value* stack of (distance, color) for the combine/modify ops and a
// *point* stack (float3 this time) for the transform scopes. Same instruction
// classes as the 2D `SDFNode`; leaves evaluate 3D distance functions:
//   kind 0 EVAL   leaf: sel = SDF3DShape tag; evaluate that 3D SDF at the current
//                 point, push (distance, color). geo0 packs the shape params — sphere
//                 radius in .x; box half-extents in .xyz; torus (major, tube) in .xy;
//                 capsule (radius, half-height) in .xy — and color is the leaf's RGBA.
//   kind 1 OP     binary combine, pop 2 / push 1: sel = 0 union, 1 smoothUnion, 2
//                 subtract, 3 smoothSubtract, 4 intersect, 5 smoothIntersect, 6 morph
//                 (the 2D ops exactly). k = smoothing radius / morph amount; the
//                 smooth ops lerp color by the smin blend factor.
//   kind 2 MOD    unary value op, pop 1 / push 1: sel = 0 round, 1 onion. k = amount.
//   kind 3 XFORM  push the current point, transform it for the enclosing scope: sel =
//                 0 translate (geo0.xyz), 1 rotate (geo0.xyz = unit axis, geo1.x =
//                 angle), 2 scale (k = factor s, p /= s). Translate/rotate are rigid;
//                 scale multiplies the child distance back at RESTORE_P.
//   kind 4 RESTORE_P  pop the point; k = the distance scale (s for a scale scope, else 1).
// Stride 64 (four 16-byte rows), matching `SDFNode`.
typedef struct {
    unsigned int kind;     // 0 EVAL, 1 OP, 2 MOD, 3 XFORM, 4 RESTORE_P
    unsigned int sel;      // shape tag / op kind / mod kind / xform kind
    float k;               // OP smin k or morph; MOD radius/thickness; XFORM scale s; RESTORE_P distance scale
    float extra;           // reserved (spare per-kind scalar)
    simd_float4 color;     // EVAL leaf straight RGBA
    simd_float4 geo0;      // EVAL shape params; XFORM vector param (translate xyz / rotate axis xyz)
    simd_float4 geo1;      // EVAL extra params; XFORM scalar param (rotate angle in .x)
} SDFNode3D;

// One composed 3D SDF field for the raymarch pipeline (see ShaderRaymarch.metal),
// drawn as a fullscreen triangle whose fragment sphere-traces the field's `SDFNode3D`
// program. The march runs in WORLD space, so the surface normal (a 4-tap gradient)
// and the written depth are world-space directly — no normal matrix. Each step maps
// the world sample point into the field's local frame by `inverseModel`, evaluates
// the node VM there, and multiplies the local distance by `modelScale` to get the
// world step. `boundsMin`/`boundsMax` are the field's world-space AABB; a pixel whose
// ray misses that box bails in O(1), so the fullscreen pass is cheap where the field
// isn't. With a solid `fill`, the color comes from the nodes (each leaf carries its own,
// baked at flatten time); with a gradient `fill`, the whole merged surface is painted by
// `fillGradient*` instead, sampled by each hit's projected screen position. Stride 144.
typedef struct {
    simd_float4x4 inverseModel; // world -> field-local space (the inverse 3D model matrix)
    simd_float4 boundsMin;      // field world-space AABB min (xyz; w unused)
    simd_float4 boundsMax;      // field world-space AABB max (xyz; w unused)
    simd_float4 fillGradientGeo;// screen-space gradient geometry in canvas points (read when
                                // fillGradientKind != 0): linear (start.xy, end.xy), radial
                                // (center.xy, radius, _). The gradient paints the whole merged
                                // surface by each hit's projected screen position
    float modelScale;           // uniform scale of the model matrix (local distance -> world distance)
    unsigned int nodeStart;     // first SDFNode3D for this field (absolute index)
    unsigned int nodeCount;     // number of nodes
    float unbounded;            // 1 if the field has no finite AABB (contains a plane): the march
                                // ignores boundsMin/Max and runs to the camera's far plane instead
    float fillGradientKind;     // 0 solid (the leaves' own colors), 1 linear, 2 radial (screen-space)
    float fillGradientRow;      // gradient-strip row index for the ramp (when kind != 0)
    float _pad0;                // pads the stride to 144 (16-aligned)
    float _pad1;
} SDF3DGroupInstance;

// The light-space matrices for rendering a raymarched 3D field into the directional/spot 2D
// shadow map (`ollin_raymarch_shadow_fragment`): the field is sphere-traced from the light's
// point of view, and the hit's depth is written through `lightViewProjection`, so meshes
// sampling the map receive the field's cast shadow exactly as they do another mesh's.
typedef struct {
    simd_float4x4 lightViewProjection;         // world -> light clip (writes the hit's depth)
    simd_float4x4 inverseLightViewProjection;  // light clip -> world (rebuilds the march ray)
    float raymarchSteps;                       // the field's camera-march budget (the
                                               // RenderQuality dial; default 128 unchanged)
} OllinRaymarchShadowUniforms;

// One particle for the GPU compute path: a persistent buffer of these is updated
// by a compute kernel each frame (positions never round-trip through the CPU) and
// drawn by the instanced particle render path (`ollin_particle_vertex`). The
// built-in renderer reads `position`/`color`/`size`; `velocity`/`life`/`seedA`/
// `seedB` are free per-particle state a sim kernel uses (velocity for motion, life
// for fade/respawn, the two seeds for per-particle randomness). Stride 48 (three
// 16-byte rows): float2 @0, float2 @8, float4 @16, then four floats @32…44.
typedef struct {
    simd_float2 position;   // sketch-space, points, top-left origin, y-down
    simd_float2 velocity;   // points/sec — sim state; the built-in render ignores it
    simd_float4 color;      // straight (non-premultiplied) RGBA, 0…1
    float size;             // on-screen diameter, points
    float life;             // 0…1 lifetime — sim state; the built-in render ignores it
    float seedA;            // free per-particle scratch (e.g. a respawn seed)
    float seedB;            // free per-particle scratch — pads the stride to 48
} OllinParticle;

// One point of a 3D point cloud, drawn by the instanced point pipeline
// (`ollin_point_vertex`) as a camera-facing disc billboard sized in world units
// (perspective shrinks distant points). Positions are world space (right-handed,
// y-up) and reach the screen through `Camera3D`, not the 2D canvas mapping.
// `position.w` is unused (a float4 keeps the layout unambiguous across CPU/GPU).
// Stride 48 (three 16-byte rows): float4 @0, float4 @16, float @32, then pad.
typedef struct {
    simd_float4 position;   // world-space xyz (w unused)
    simd_float4 color;      // straight (non-premultiplied) RGBA, 0…1
    float size;             // splat diameter in world units
    float _pad0;            // pads the stride to 48 (free for a future normal)
    float _pad1;
    float _pad2;
} OllinPoint;

// One vertex of a solid 3D mesh (the triangle-mesh pipeline, `ollin_mesh_vertex`),
// drawn through `Camera3D` with depth testing. A primitive (box/sphere/…) is a unit
// `Mesh` placed by the model matrix; like the point cloud, the model matrix bakes
// into `position` on the CPU and the model's normal matrix into `normal`, so the
// vertex shader only applies the camera (view + projection) — positions and normals
// are already world space (right-handed, y-up). `color` is the surface (diffuse)
// color baked from the current `fill` (rgb) with `color.a` the opacity. With no
// lights set the fragment draws the surface flat in that color (the unlit look);
// with lights it shades `color` per the material model. The spare `w` slots carry
// per-vertex material data for the ray-traced reflection hit shade: `normal.w` is
// the metalness and `position.w` the roughness of a physically-based mesh (a
// wireframe reuses `position.w` for its line width instead); the lit vertex
// shaders read only `position.xyz`/`normal.xyz`, so the slots are inert for the
// primary render.
// `uv` carries texture coordinates (0,0 … 1,1) for the textured-mesh pipeline; the
// solid `ollin_mesh_vertex`/`_fragment` read only position/normal/color, so an
// untextured mesh leaves `uv` zero and is unaffected by it. The *material finish*
// (specular, iridescence, rim, subsurface, …) does not ride the vertex (it's constant
// across a mesh, so it's bound per batch as an `OllinMaterial` uniform, below); the `w`
// slots exist for the *per-hit* lookups a per-batch uniform can't serve (a reflection
// ray lands on someone else's batch). Triangle indices are expanded into a flat
// list on the CPU (no index buffer), matching the 2D triangle path. Stride 64 (four
// 16-byte rows): float4 @0, float4 @16, float4 @32, float2 @48, half4 @56; the
// tangent lives in what was the tail padding, so the stride is unchanged.
// `tangent` carries the world-space tangent basis for normal mapping as four
// Float16s: xyz = the surface's +u direction (model's linear part baked in,
// normalized), w = the bitangent handedness (±1, glTF's convention:
// bitangent = w · cross(normal, tangent)). Only the normal-mapped textured
// pipeline reads it; every other mesh leaves it zero and is unaffected.
typedef struct {
    simd_float4 position;   // world-space xyz (model matrix baked in); w = wireframe line width (unused when lit)
    simd_float4 normal;     // world-space normal (normal matrix baked in); w unused
    simd_float4 color;      // straight RGBA diffuse; rgb = surface color, a = opacity
    simd_float2 uv;         // texture coordinates, 0…1 (textured-mesh pipeline; 0 when untextured)
    OllinHalf4 tangent;     // packed world tangent xyz + handedness w (normal-mapped pipeline only)
} OllinMeshVertex;

// One instance of an instanced mesh draw (`drawMesh(_:instances:)`): the base
// mesh's local-space vertices ride their own buffer once per call, and each
// instance carries its own local -> world model matrix, applied per vertex on
// the GPU (`ollin_mesh_instanced_vertex`), so a thousand copies cost one
// vertex expansion plus a thousand of these, not a thousand CPU re-bakes.
// `color` multiplies the batch's baked surface color (white = unchanged).
// There is deliberately no normal matrix: the shader derives the normal
// transform from the model's linear part (the adjugate-transpose, exact under
// non-uniform scale), so a compute kernel writing instances fills only these
// two fields. Stride 80 (five 16-byte rows).
typedef struct {
    simd_float4x4 model;   // local -> world (the instance's own placement)
    simd_float4 color;     // straight RGBA multiplier on the surface color
} OllinMeshInstance;

// One entry of a `MeshField` (one distinct mesh and its run of copies), read by
// the field's GPU cull + encode kernels and by the CPU build. The field's base
// vertices concatenate into one buffer; `vertexStart`/`vertexCount` are this
// entry's run. Its copies are `copyStart ..< copyStart + copyCount` in the
// field's `OllinMeshInstance` buffer, and its visible copies compact into
// `compactOffset ..<` in the compacted-index buffer (capacity = copyCount, so
// entries never collide). `center`/`radius` are the mesh's LOCAL bounding
// sphere; the cull kernel transforms them per copy. Stride 48.
typedef struct {
    simd_float4 center;      // local bounding-sphere center (xyz; w unused)
    unsigned int vertexStart;
    unsigned int vertexCount;
    unsigned int copyStart;
    unsigned int copyCount;
    unsigned int compactOffset;
    float radius;            // local bounding-sphere radius
    float _fe0;              // pads the stride to 48 (16-aligned)
    float _fe1;
} OllinFieldEntry;

// Per-frame parameters for a `MeshField`'s GPU cull + encode kernels: the view
// frustum as six inward-facing planes (Gribb-Hartmann rows of the unjittered
// view-projection, normalized), the field's draw-time model matrix (the 3D CTM
// at drawMeshField, composed onto every copy), and the two dispatch widths.
typedef struct {
    simd_float4 planes[6];     // inward world-space frustum planes (xyz = n, w = d)
    simd_float4x4 fieldModel;  // field local -> world (identity when untransformed)
    unsigned int copyCount;    // total copies (the cull dispatch width)
    unsigned int entryCount;   // entries (the encode dispatch width)
    unsigned int cullEnabled;  // 0 = every copy passes (the A/B and export path)
    unsigned int _fc0;
} OllinFieldCullParams;

// Parameters for a `StrandField` (`drawStrands`): a patch of grass-like blades
// generated ENTIRELY on the GPU by a mesh pipeline. No vertex or instance
// buffer exists anywhere: every blade's position, height, lean, sway phase, and
// tint derive from its index through the shader library's hashes, the object
// stage frustum-culls per tile and picks a per-tile segment count by camera
// distance, and the mesh stage emits the ribbons in-draw. One struct feeds the
// object stage, the mesh stage, and the CPU-side tile math.
typedef struct {
    simd_float4 planes[6];     // inward world-space frustum planes (camera)
    simd_float4x4 fieldModel;  // patch local -> world (the draw-time 3D CTM)
    simd_float4 lowColor;      // straight sRGB base color at the blade root
    simd_float4 tipColor;      // straight sRGB color at the tip
    simd_float4 patch;         // x, y = patch half-extents in X/Z; z = tile edge; w unused
    simd_float4 blade;         // x = height, y = height variance 0..1, z = width, w = lean amount
    simd_float4 sway;          // x = sway amplitude, y = frequency, z = the sketch clock, w = seed
    simd_float4 lod;           // x = camera-space near distance (full detail), y = far
                               // (least), z = eye x, w = eye z (the distance read)
    simd_float4 eye;           // xyz = world eye (unused slots reserved); w = lodEnabled
    unsigned int tilesX;       // tiles across the patch
    unsigned int tilesZ;
    unsigned int bladesPerTile;
    unsigned int cullEnabled;  // 0 = every tile passes (the A/B switch)
} OllinStrandParams;

// Blade-bundle sizing shared by the CPU dispatch and the mesh stage: each mesh
// threadgroup emits up to OLLIN_STRAND_BUNDLE blades, one thread per blade, at
// up to OLLIN_STRAND_MAX_SEGMENTS segments each. The metal::mesh capacity is
// sized from these (verts = bundle * (maxSegments + 1) * 2 <= 256, primitives
// = bundle * maxSegments * 2 <= 512), so changing either means re-checking
// both caps.
#define OLLIN_STRAND_BUNDLE 24
#define OLLIN_STRAND_MAX_SEGMENTS 4

// The surface *finish* of a 3D mesh: how it responds to light, separate from the surface
// color (which is the baked vertex color = the current `fill`). A material is constant
// across a mesh, so it's bound per mesh batch as a fragment uniform rather than baked into
// every vertex. It composes a base **shading model** (0 standard Lambert, 1 toon/cel,
// 2 Gooch warm–cool, 3 physically-based metallic-roughness) with layered **finishes**
// evaluated in the shared `meshLitColor` tail — Blinn-Phong specular, a Fresnel **rim**
// glow, fake **subsurface** scattering, and a Fresnel-driven **iridescent** sheen. Each
// finish is inert at its zero value, so the default material (specular 0, shininess 32,
// everything else 0, shading model 0) shades byte-identically to the plain Lambert path.
// Shading model 3 swaps the diffuse+Blinn-Phong term for a Cook-Torrance microfacet BRDF
// driven by `metallic`/`roughness` (the surface color stays the baked vertex color =
// `fill`); the other models ignore those two fields, so they're unchanged.
// The transmission tail (`transmission`/`ior`/`thickness`/`attenuation`) turns a
// physically-based dielectric into glass: the transmitted lobe replaces the diffuse one,
// refracting the environment (or the traced scene under ray-traced reflections). Inert at
// transmission 0 and inactive without an environment, so every existing frame is unchanged.
// Two layered physically-based lobes ride the same model: `clearcoat` adds a thin polished
// lacquer layer (a second specular lobe at its own roughness, the base attenuated by what
// the coat reflects), and `sheenColor` a soft fabric rim (retroreflective fuzz at grazing
// angles, the base scaled down by the sheen's directional albedo). Both inert at zero.
// Colors are linear (sRGB→linear CPU-side).
typedef struct {
    simd_float4 rimColor;         // rgb linear rim color; a = rim strength (0 = no rim)
    simd_float4 subsurfaceColor;  // rgb linear subsurface tint; a = subsurface strength (0 = none)
    simd_float4 goochWarm;        // rgb linear Gooch warm tone (lit side); a unused
    simd_float4 goochCool;        // rgb linear Gooch cool tone (shadow side); a unused
    simd_float4 sparkleColor;     // rgb linear flake tint; a = sparkle strength (0 = none)
    float specular;               // Blinn-Phong specular strength (0 = matte)
    float shininess;              // Blinn-Phong shininess exponent (>= 1)
    float iridescence;            // iridescent sheen strength (0 = none)
    float iridescenceScale;       // iridescence band count, head-on -> grazing
    float rimPower;               // Fresnel exponent for the rim falloff
    float toonBands;              // number of cel bands (toon shading)
    int   shadingModel;           // 0 standard (Lambert), 1 toon (cel), 2 Gooch (warm-cool), 3 physically-based
    float metallic;               // PBR (shading model 3): 0 dielectric … 1 metal; ignored otherwise
    float roughness;              // PBR (shading model 3): 0 mirror-smooth … 1 fully rough; ignored otherwise
    float sparkleSize;            // flake cell size, relative to the scene framing (1 = fine glitter)
    float sparkleSharpness;       // flake flash exponent (higher = rarer, harder flashes)
    float clearcoat;              // PBR: clear-coat layer intensity (0 = no coat); the coat's own
                                  // specular lobe adds on top and the base dims by what it reflects
    simd_float4 attenuation;      // Beer-Lambert medium: rgb = linear attenuation color (what white
                                  // light becomes after `w` of travel); w = attenuation distance in
                                  // world units (0 = no attenuation). Volumetric only (thickness > 0).
    float transmission;           // PBR: fraction of light transmitted through the surface (0 = opaque)
    float ior;                    // PBR: index of refraction (>= 1; 1.5 = common glass)
    float thickness;              // PBR transmission: 0 = thin-walled; > 0 = solid, world units
    float f0;                     // PBR: normal-incidence Fresnel reflectance, packed CPU-side from
                                  // `ior` (exactly 0.04 at the default 1.5, keeping old frames bit-equal)
    float iridescenceFlow;        // soap-film mode: strength of the drifting film-thickness swirl the
                                  // iridescent sheen reads (0 = the plain view-angle rim sheen)
    float iridescencePhase;       // the film swirl's animation clock, sketch-driven (no hidden time,
                                  // so exports reproduce); only read when iridescenceFlow > 0
    float iridescenceFlowSize;    // the swirl's feature size, relative to the scene framing (the
                                  // sparkle sizing rule): 1 = default, smaller = finer marbling
    float clearcoatRoughness;     // PBR: the coat layer's own perceptual roughness (0 = polished)
    simd_float4 sheenColor;       // PBR sheen: rgb = linear sheen tint premultiplied by strength
                                  // (0,0,0 = no sheen); w = the sheen lobe's perceptual roughness
    simd_float4 scatter;          // real subsurface scattering (the screen-space diffusion blur):
                                  // rgb = per-channel falloff ratios (raw, not linearized; they
                                  // stretch the diffusion profile per channel, red widest for skin);
                                  // w = the scattering radius in world units (0 = off). Read by the
                                  // scatter-mask pass, the CPU kernel build, and the lit fragments'
                                  // transmittance branch (gated on `scatterStrength > 0`, so every
                                  // non-scattering shading path is untouched).
    float scatterStrength;        // 0…1 fraction of the surface's light the blur diffuses, and the
                                  // scale on the transmittance term (0 = both off)
    float normalScale;            // normal-map strength: 0 = no map bound (the gate; every other
                                  // mesh keeps this zero, so unmapped frames are untouched),
                                  // > 0 scales the sampled tangent-space x/y before renormalizing
                                  // (glTF's normalTexture.scale). Set per batch from the mesh's
                                  // `MeshMaterial.normalScale` when its normal map draws, not from
                                  // the drawing-state `material(_:)` finish.
    // The surface-map gates below follow `normalScale`'s pattern: per-mesh state set
    // only when the surface-mapped pipeline draws a mesh whose maps verified, zero on
    // every other batch, doubling as the encode-side and shader-side gates.
    float mrGate;                 // 1 = a metallic-roughness map is bound (glTF packing:
                                  // roughness g, metallic b); the sampled channels multiply
                                  // `metallic`/`roughness` above, which then carry the composed
                                  // factors (drawing-state finish × the mesh material's own)
    float occlusionStrength;      // > 0 = an occlusion map is bound (its r channel); the sample
                                  // dims the *indirect* terms only (ambient/IBL/GI) as
                                  // 1 + strength·(ao − 1), the glTF convention. 0 = no map.
    simd_float4 emissive;         // rgb = linear emissive factor (the surface adds this much
                                  // light of its own; 0,0,0 = none, the gate for the constant
                                  // term); w = 1 when an emissive map is bound (sampled sRGB,
                                  // multiplied by the factor), 0 = factor alone
    float parallax;               // > 0 = a height map is bound (its r channel, sampled as data):
                                  // the relief depth the fragment's parallax march carves below
                                  // the surface, as a fraction of the uv tile
                                  // (`MeshMaterial.heightScale`). 0 = no map (the gate; every
                                  // other mesh keeps this zero, so unmapped frames are untouched).
    float triplanar;              // > 0 = the base texture (and normal map, if bound) project
                                  // along the three world axes, blended by the surface normal,
                                  // for meshes with no uvs at all. The value is tiles per world
                                  // unit (1 / `MeshMaterial.triplanarScale`). 0 = uv mapping
                                  // (the gate; every other mesh keeps this zero, so uv-mapped
                                  // frames are untouched).
    float detailScale;            // > 0 = detail maps bound (the gate for the pair): the tile
                                  // count of the detail uv relative to the base uv
                                  // (`MeshMaterial.detailScale`); the detail maps repeat that
                                  // many times across one base tile. 0 = no detail (every other
                                  // mesh keeps this zero, so detail-less frames are untouched).
    float detailStrength;         // how strongly the detail pair applies: scales the color map's
                                  // push away from its 128-gray neutral and the detail normal's
                                  // tangent-plane tilt. Packed only while detailScale > 0.
    simd_float4 detailGates;      // x = 1 when a detail color map is bound (texture 22, sampled
                                  // as data: 128-gray neutral, the sample × 2 multiplies the
                                  // base color); y = 1 when a detail normal map is bound
                                  // (texture 23, data; reoriented onto the base normal);
                                  // z, w pad the row.
} OllinMaterial;

// A projected decal (see `Sketch.decal(_:at:...)`): a picture stamped onto whatever
// 3D surfaces sit inside its oriented box, composited over the surface's base color
// before lighting, so the shading treats it as paint on the surface (it takes the
// surface's own finish). The frame's decals ride one small uniform (`OllinDecals`,
// fragment buffer 2 on the surface-mapped mesh pipeline) beside a shared
// `texture2d_array` (texture 24), the light-cookie arrangement. The rows carry the
// world→box transform: p = (dot(row0, w1), dot(row1, w1), dot(row2, w1)) with
// w1 = (worldPos, 1) lands inside the box when every |component| <= 0.5; +y in box
// space reads as the image's top (the cookie orientation rule).
typedef struct {
    simd_float4 row0;        // world→decal-box rows (the box's inverse frame over its size)
    simd_float4 row1;
    simd_float4 row2;
    simd_float4 axis;        // xyz = the projection direction (unit, world space), for the
                             // facing fade: surfaces turned past ~edge-on to the projection
                             // fade the decal out instead of smearing it. w unused.
    simd_float4 params;      // x = layer in the decal texture array; w = opacity 0…1;
                             // y, z unused
} OllinDecal;

#define OLLIN_MAX_DECALS 8

// The frame's decal list, packed CPU-side each frame (`Drawer.placedDecals` order,
// which is call order: a later decal composites over an earlier one). `count == 0`
// is the gate: the fragment's decal loop is skipped entirely and the texture slot
// holds a stand-in, so a frame that places no decal renders byte-identically.
typedef struct {
    int count;
    int _decPad0;
    int _decPad1;
    int _decPad2;
    OllinDecal decals[OLLIN_MAX_DECALS];
} OllinDecals;

// Parameters for the live ground-grid overlay (`ollin_grid_fragment`): a shader-drawn
// reference floor at y=0, host chrome shown in the live preview only, never in an
// export. The grid is computed per pixel from the plane's interpolated world XZ via
// screen-space derivatives (an anti-aliased "pristine grid"), so lines hold a constant
// ~`lineWidthPixels` screen width at any distance or grazing angle and blend to a flat
// tone before they would Moiré. The X (z=0) and Z (x=0) world axes take their own
// colors. Everything fades out radially between `fadeStart` and `fadeEnd` (world
// distance from the camera) so the finite plane reads as infinite. Colors are straight
// sRGB (the fragment linearizes them); each color's `a` is its own opacity (the grid
// line's `a` the master grid opacity). Bound once per grid batch as a fragment uniform.
typedef struct {
    simd_float4 cameraPos;   // world-space camera eye (xyz; w unused), for the distance fade
    simd_float4 lineColor;   // minor (fine) grid line color: sRGB rgb + a = opacity
    simd_float4 majorColor;  // major (every 10th) grid line color: sRGB rgb + a = opacity
    simd_float4 xAxisColor;  // X-axis (z=0) line color: sRGB rgb + a = opacity
    simd_float4 zAxisColor;  // Z-axis (x=0) line color: sRGB rgb + a = opacity
    float cellSize;          // the finest division reference (base cell), world units; the shader
                             // picks the on-screen level of detail from this via a smooth log blend
    float lineWidthPixels;   // grid + axis line width, in screen pixels
    float fadeStart;         // world distance from the camera where the fade begins
    float fadeEnd;           // world distance where the grid has fully faded out
} OllinGridParams;

// Lighting for the 3D mesh model (the Blinn-Phong material on `ollin_mesh_fragment`).
// Per-frame state, like the camera: the sketch sets lights each `draw()` (see
// `Sketch.directionalLight`/`pointLight`/`spotLight`/`ambientLight`), and the renderer
// packs them into one `OllinLighting` bound to the mesh fragment. With `enabled == 0`
// (no lights and no ambient set) the fragment keeps the byte-identical normal-as-color
// path, so a 3D frame that sets no light renders exactly as before.

#define OLLIN_MAX_LIGHTS 8

// One light. `kind`: 0 directional (parallel rays), 1 point (omni from a position),
// 2 spot (point gated by a cone), 3 rect / 4 disk / 5 tube (area lights, shaded with
// Linearly Transformed Cosines through the fitted LUTs at fragment textures 8/9).
// Colors are linear (sRGB→linear on the CPU) and premultiplied by intensity. The
// punctual kinds (0-2) have no distance attenuation; the area kinds fall off
// physically (the shape's solid angle shrinks with distance), with `color` as the
// emitting surface's radiance, so a bigger panel casts more light.
typedef struct {
    simd_float4 color;       // rgb = linear *diffuse* color × intensity; a unused
    simd_float4 position;    // point/spot: world-space position; rect/disk/tube: the shape's center; w unused
    simd_float4 direction;   // directional: unit direction *to* the light; spot: unit cone axis (light's
                             // travel direction); rect/disk: the panel's unit normal (the way it faces);
                             // tube: unused. w: rect/disk two-sided flag (1 = emits both faces, 0 = front only)
    int   kind;              // 0 directional, 1 point, 2 spot, 3 rect, 4 disk, 5 tube
    float cosInner;          // spot: cosine of the inner half-angle (full brightness within)
    float cosOuter;          // spot: cosine of the outer half-angle (zero beyond); inner→outer is the soft penumbra
    float softness;          // diffuse wrap, 0…1: softens the terminator (0 = hard Lambert, byte-identical to
                             // before). Punctual kinds only; an area kind's softness is its real extent.
    simd_float4 specular;    // rgb = linear *specular* color × intensity (defaults to `color`, so a single-color light is unchanged); a unused
    simd_float4 axisA;       // rect/disk: unit tangent (the width axis), w = half-width (disk: radius);
                             // tube: the unit axis, w = the half-length. Unused for kinds 0-2.
    simd_float4 axisB;       // rect/disk: unit bitangent (the height axis), w = half-height (disk: radius);
                             // tube: xyz unused, w = the tube radius. Unused for kinds 0-2.
    simd_float4 shaping;     // light shaping (point/spot): x = IES profile layer in the array at
                             // fragment texture 10 (-1 = none), y = cookie layer in the array at
                             // fragment texture 11 (-1 = none, spot only), z = roll about the beam
                             // axis in radians (spins profile azimuth + cookie together), w unused.
                             // The point kind's fixture axis rides `direction` (unused before).
} OllinLight;

// Shadow mapping (opt-in, `castShadows()`): one light casts. The caster's
// contribution is dimmed where a depth pass from its point of view found an occluder
// nearer than the receiver. `shadowLight` is the index of that light in `lights` (or
// -1 when shadows are off, so the mesh fragment is byte-identical to the unshadowed
// path); `shadowStrength` scales the darkening (1 = full). `shadowKind` selects how
// the caster's depth is stored and sampled: 0 = a single **2D** map (a directional
// light's orthographic box or a spot light's perspective frustum, both via
// `lightViewProjection` into the caster's clip space, sampled with the comparison
// `depth2d`), 1 = an omnidirectional **cube** map (a point light). The cube stores, per
// direction, the nearest occluder's **linear distance to the light** normalized by the
// far plane (not a projected depth), so the receiver simply measures its own distance
// and shadows where it exceeds the sampled one. `shadowTexelWorld` is the world-space
// size of one shadow-map texel (the bias / PCF-spread unit, used by both kinds);
// `shadowDepthA` carries the cube's far plane (to denormalize the sampled distance), with
// the light position from `lights[shadowLight].position`. A ray-tracing device instead
// uses `shadowKind` 2 for a point caster: the renderer traces a visibility ray against a
// per-frame acceleration structure (no cube, no depth compare: exact, no acne/peter-pan),
// and `shadowDepthB` carries the area-light radius that softens it (`shadowTexelWorld`
// reused as the self-hit normal-offset). A rect/disk **area** caster rides the same two
// paths by the panel's real extent: kind 0 renders a spot-style map from the panel's
// center whose PCSS penumbra radius is sized from that extent, and a ray-tracing device
// flips it to kind 2, tracing visibility to the panel's actual surface (`shadowDepthB`
// then carries the softness scale on the extent, not a radius). `shadowDepthB` is 0 /
// unused for the remaining kinds.
// One camera-anchored global-illumination probe cascade (the vast-scene ladder;
// the scene-fitted volume rides `OllinLighting`'s own gi fields as cascade 0).
// Spacing is isotropic per cascade (each cascade doubles the finer one's), and the
// counts/phase pair carries the infinite-scrolling wrap: a probe at grid coordinate
// g stores into physical tile ((g + phase) mod counts) inside the cascade's own
// 512-probe atlas slot, so a camera move re-labels only the scrolled-in planes.
#define OLLIN_GI_MAX_CAMERA_CASCADES 3
typedef struct {
    simd_float4 originBias;    // xyz = the window's world-space corner (first probe's grid
                               // anchor); w = the cascade's self-shadow bias magnitude
                               // (0.75 · spacing · 0.3, the volume rule at this spacing).
    simd_float4 spacingBase;   // x = the isotropic probe spacing; y = the cascade's first
                               // probe index in the stacked atlases ((c + 1) · 512); z = the
                               // Chebyshev moment cap (1.5 · spacing, the cage rule); w unused.
    simd_float4 countsPhase;   // xyz = probes per axis (2…8, as floats); w = the scroll phase
                               // packed as phase.x + 32·(phase.y + 32·phase.z) (each 0…31).
} OllinGICascade;

typedef struct {
    simd_float4 ambient;          // rgb linear ambient (lights every surface flatly); a unused
    simd_float4 cameraPosition;   // world-space eye xyz (for the specular view direction); w unused
    OllinLight lights[OLLIN_MAX_LIGHTS];
    int lightCount;               // number of valid entries in `lights`
    int enabled;                  // 1 = lit shading (any light or ambient set); 0 = normal-as-color (unchanged)
    int shadowLight;              // index of the shadow-casting light in `lights`, or -1 (no shadows)
    float shadowStrength;         // 0…1 darkening applied to the caster where occluded
    simd_float4x4 lightViewProjection;  // world -> shadow-caster clip space (2D kind)
    float shadowTexelWorld;       // world-space size of one shadow-map texel (bias / PCF-spread unit)
    int   shadowKind;             // 0 = 2D map (directional/spot/area), 1 = cube map (point),
                                  // 2 = ray-traced (point or area; the caster entry's kind splits them)
    float shadowDepthA;           // cube kind: the far plane; 2D kind: the PCSS penumbra radius
                                  // in texels (0 = the hard legacy 3x3 path; an area caster sizes
                                  // it from the panel's extent); ray-traced: unused
    float shadowDepthB;           // ray-traced kind: a point caster's area radius (softness) or an
                                  // area caster's softness scale on the sampled panel; 2D kind:
                                  // the perspective projection's [2][2] term to linearize a spot
                                  // or area map's depth for the penumbra ratio (0 = an ortho/
                                  // directional map, the sentinel for plain separation); cube: unused
    int   shadowSamples;          // ray-traced kind: rays per pixel; 2D kind: the PCSS tap budget
                                  // (split blocker search / PCF); cube kind: unused (default 0)
    int   fieldCasterCount;       // number of raymarched SDF fields casting onto meshes under a
                                  // point/ray-traced caster (the lit mesh fragments march them
                                  // toward the light; 0 = none, the byte-identical mesh path). A
                                  // directional/spot caster instead has the field render into the
                                  // 2D map, so this stays 0 for shadowKind 0.
    int   fieldShadowMode;        // how a lit mesh resolves that point/RT field cast: 0 = march the
                                  // field inline per pixel (full-res / export / the byte-identical
                                  // path); 1 = sample the precomputed half-res field-shadow texture
                                  // by screen position (the live preview, the RenderQuality dial).
    float fieldShadowScale;       // the half-res resolution fraction (e.g. 0.5) when fieldShadowMode
                                  // == 1: the fragment's screen uv is (position.xy · scale) / the
                                  // half-res texture size, so it's free of any points-vs-pixels
                                  // (Retina) drawable mismatch (the texture covers the screen).
    int   iblEnabled;             // 1 = an image-based-lighting environment is bound (the
                                  // physically-based ambient samples the irradiance/prefilter/BRDF
                                  // textures); 0 = none, the flat-ambient path, byte-identical.
    float iblIntensity;           // brightness multiplier on the IBL ambient term
    float iblMaxMip;              // top mip index of the prefiltered specular cube (roughness 1)
    float iblRotation;            // environment Y rotation (radians), applied to the sample dirs
    int   rtReflections;          // 1 = trace the actual scene as the physically-based reflection
                                  // (in place of the IBL prefilter sample, falling back to it on a
                                  // miss), on a ray-tracing device with the `rayTracedReflections()`
                                  // opt-in; 0 = the IBL-prefilter reflection only (byte-identical).
    float rtReflectionBias;       // world-space self-hit normal offset for the reflection ray's
                                  // origin (sized from the scene scale in `makeLighting`).
    int   rtReflectionDeferred;   // 1 = the lit fragment reads the pre-traced reflection texture
                                  // (jittered + temporally accumulated live, supersampled on
                                  // export) by screen position instead of tracing inline; 0 =
                                  // the inline single-ray trace (render targets and the
                                  // raymarched fields keep this path).
    float rtReflectionScale;      // that texture's resolution as a fraction of the drawable when
                                  // deferred: the fragment's uv is (position.xy · scale) / the
                                  // texture size (the `fieldShadowScale` rule), so a future
                                  // half-res reflection tier needs no shader change.
    float sceneScale;             // the camera's eye-to-target distance (the scene-scale proxy the
                                  // shadow framing and rtReflectionBias also derive from): sizes the
                                  // sparkle finish's flake cells so they read the same at any scene
                                  // scale. 0 when no camera; only the sparkle path reads it.
    int   ltcEnabled;             // 1 = the LTC lookup tables are bound at fragment textures 8/9
                                  // (set by the renderer once the bundled tables load), so the area
                                  // light kinds (3-5) shade; 0 = area kinds contribute nothing (the
                                  // loader logs the failure once). Kinds 0-2 never read it.
    int   iesEnabled;             // 1 = the baked IES profile array is bound at fragment texture 10
                                  // (set by the renderer once a frame light carries a profile), so a
                                  // light with shaping.x >= 0 samples it; 0 = no light has a profile
                                  // and the punctual path is byte-identical.
    int   cookieEnabled;          // 1 = the cookie array is bound at fragment texture 11 (a frame
                                  // spot carries a cookie), so shaping.y >= 0 projects it; 0 = none,
                                  // byte-identical. Both flags follow the `ltcEnabled` discipline:
                                  // default 0, textures always bound (real or stand-in), the branch
                                  // skipped so a featureless frame executes the prior instructions.
    simd_float4 fogColor;         // atmosphere (`fog` / `volumetricLight`): the fog's linear ambient
                                  // in-scatter color; w is the gate AND the model: 0 leaves every
                                  // carrier's fog branch untaken (byte-identical), 1 = classic fog,
                                  // 2 = aerial perspective (the wavelength-split twin; still > 0,
                                  // so every existing fog gate holds and the carriers pick the
                                  // model with one compare against 1.5).
    simd_float4 fogParams;        // x = extinction density at height 0 (inverse world units; 0 = no
                                  // dimming, beams only), y = height falloff (density is
                                  // x·e^(−y·height); 0 = uniform), z = the volumetric in-scatter
                                  // gain (0 = no shaft march), w = the Henyey-Greenstein
                                  // anisotropy g, −1…1 (forward-leaning positive).
    simd_float4 fogParams2;       // x = the shaft march's step budget (a RenderQuality tier the
                                  // renderer resolves; the drawer packs 0), y = the camera's far
                                  // plane (the air backdrop's march cap), z = 1 while a skybox
                                  // backdrop was drawn (renderer-set; the aerial air veil steps
                                  // aside behind it, beams still add; read only by the air
                                  // fragment), w reserved.
    simd_float4 shadowLinearize;  // a punctual 2D-map caster's depth→world-distance constants,
                                  // read by the scattering transmittance term (the thickness the
                                  // light crossed inside the body): x = the shadow projection's
                                  // [2][2], y = its [3][2], z = 1 for a perspective (spot) map /
                                  // 0 for the orthographic directional box, w unused. All zero
                                  // when there is no punctual 2D caster (x == 0 skips the term).
    simd_float4 giOrigin;         // global illumination (`globalIllumination()`, ray-tracing
                                  // devices): xyz = the world-space corner of the probe volume
                                  // (the grid's first probe); w = 1 while the frame's probe
                                  // atlases are bound at fragment textures 13/14 (the gate:
                                  // 0 leaves every carrier's GI branch untaken, byte-identical).
    simd_float4 giSpacing;        // xyz = the per-axis distance between neighbouring probes;
                                  // w = the sketch's GI intensity (a multiplier on the sampled
                                  // bounce light, 1 = physical).
    simd_float4 giCounts;         // xyz = probes per axis (as floats, for grid math); w = the
                                  // self-shadow bias magnitude in world units, precomputed as
                                  // 0.75 · min axial spacing · the tunable 0.3 (the visibility
                                  // query's offset away from the surface).
    OllinGICascade giCascades[OLLIN_GI_MAX_CAMERA_CASCADES];
                                  // the camera-anchored probe cascades (vast scenes only), ordered
                                  // coarsest → finest; the scene-fitted volume stays the three
                                  // fields above (cascade 0). Entry c's probes live at atlas slot
                                  // (c + 1) · 512. Unread while `giCascadeInfo.x` <= 1, so a
                                  // room-scale frame is byte-identical to the pre-cascade path.
    simd_float4 giCascadeInfo;    // x = total cascade count including the scene volume (1 = no
                                  // camera cascades, the shipped single-volume path); y/z/w unused.
    simd_float4 contactShadow;    // contact shadows (`contactShadows()`): x = the screen-space
                                  // ray's length in world units (the gate: 0 leaves every mesh
                                  // carrier's sample branch untaken, byte-identical; the renderer
                                  // zeroes it when the mask pass didn't run); y = the mask
                                  // texture's uv scale (screen position * y / texture size, the
                                  // fieldShadowScale rule; 1 at full resolution); z = the march's
                                  // step budget (a RenderQuality tier the renderer resolves; the
                                  // drawer packs 0); w unused.
    simd_float4 aerialSun;        // aerial perspective (`aerialPerspective()`, fogColor.w = 2):
                                  // xyz = the world-space unit direction toward the sun (explicit,
                                  // or the `.sky` environment's sun through its rotation, or the
                                  // first directional light, or a default elevation); w = the
                                  // aerosol phase's forward anisotropy g. Unread while
                                  // fogColor.w < 2, so classic fog never touches it.
    simd_float4 aerialLight;      // rgb = the sun's in-scatter radiance (linear; carries the
                                  // low-elevation reddening and the overall in-scatter gain);
                                  // w = the aerosol (haze) fraction of the extinction, 0…1
                                  // (0 = pure molecular blue-shift, 1 = gray haze).
} OllinLighting;

// Per-frame constants auto-injected into every compute dispatch (bound at buffer
// index 10), so a kernel reads `u.time`/`u.dt`/`u.resolution`/… with no plumbing.
// `particleCount` is the dispatch's thread count (set per dispatch). `custom` is a
// 4-float per-dispatch knob bag the sketch fills (focus, strength, …) so a kernel
// can take a couple of live parameters without declaring its own struct. Stride 48
// (`custom` is float4, 16-aligned at offset 32).
typedef struct {
    simd_float2 resolution;     // canvas size in points
    simd_float2 mouse;          // cursor position in points (top-left origin)
    float time;                 // seconds since the sketch started
    float dt;                   // seconds since the previous frame
    unsigned int frameCount;    // frames drawn so far
    unsigned int particleCount; // this dispatch's thread count
    simd_float4 custom;         // four free per-dispatch floats (see ComputeParams)
} OllinComputeUniforms;

// A uniform-grid spatial hash over a toroidal 2-D domain (the GPU neighbor-search
// primitive `SpatialHash` builds and every particle-interaction sim queries).
// Cells tile `worldSize` exactly (`worldSize = float2(gridW, gridH) * cellSize`), so
// wrapping a position into `[origin, origin + worldSize)` and wrapping a cell index
// modulo `gridW`/`gridH` stay consistent. `cellSize` is set to the query radius, so
// every neighbor within the radius lives in the queried cell's toroidal 3×3 block
// (which needs `gridW`/`gridH` at least 3, which `SpatialHash` guarantees). Stride
// 32: float2 @0, float2 @8, float @16, three uints @20…28. (Distinct from
// `OllinGridParams` above, which is the 3D reference-floor uniform.)
typedef struct {
    simd_float2 origin;         // world-space min corner (points, top-left origin)
    simd_float2 worldSize;      // the toroidal domain extent = float2(gridW,gridH)*cellSize
    float cellSize;             // uniform cell edge, set to the neighbor query radius
    unsigned int gridW;         // cells across
    unsigned int gridH;         // cells down
    unsigned int numCells;      // gridW * gridH (the cell-count/start/cursor buffer length)
} OllinSpatialGrid;

// Per-substep parameters for the particle-fluid step (`ParticleFluid`), packed by
// the CPU each substep and bound at buffer index 11. The fluid runs in canvas
// points and seconds; `stiffness`/`nearStiffness` scale pressures computed from
// densities normalized to the seeded rest lattice, so 1 in density units means
// "packed as seeded". `box` is the wall rectangle the integrate pass clamps to
// (min x, min y, max x, max y). Stride 112 (16-aligned: two float2 rows, three
// float4 rows, then twelve floats).
typedef struct {
    simd_float2 gravity;          // points/s²
    simd_float2 interactionPoint; // pull/push center, canvas points
    simd_float4 box;              // walls: min x, min y, max x, max y (points)
    simd_float4 colorSlow;        // straight sRGB at rest
    simd_float4 colorFast;        // straight sRGB at `speedForFastColor`
    float interactionStrength;    // signed pull(+)/push(−) acceleration; 0 = none
    float interactionRadius;      // interaction falloff radius, points
    float restDensity;            // target density relative to the seeded lattice
    float stiffness;              // pressure constant (≈ speed of sound², pt²/s²)
    float nearStiffness;          // near-pressure constant (always repulsive)
    float viscosity;              // neighborhood velocity-smoothing blend, 0…1
    float dt;                     // substep seconds
    float wallBounce;             // fraction of normal velocity kept on wall hit
    float speedForFastColor;      // speed (pt/s) that reaches `colorFast`
    float predictDt;              // fixed evaluation look-ahead, seconds
    float _sphPad0;
    float _sphPad1;
} OllinSPHParams;

// One soft body: a contiguous run of particles (`start`…`start+count`) that
// shape-matching pulls back toward its rest layout. The CPU seeds `start`/`count`
// once; the per-substep reduce pass writes `center` (current centroid) and
// `rotation` (cos θ, sin θ of the best-fit rest→current rotation), which the
// particle pass reads to build each particle's goal position. Stride 32.
typedef struct {
    simd_float2 center;         // current centroid (written by the reduce pass)
    simd_float2 rotation;       // best-fit rotation as (cos θ, sin θ) (written)
    unsigned int start;         // first particle index (seeded, fixed)
    unsigned int count;         // particles in this body (seeded, fixed)
    simd_float2 _bodyPad;
} OllinSoftBody;

// Per-substep parameters for the soft-body step (`SoftBodies`), packed by the CPU
// and bound at buffer index 11. `stiffness` is the shape-matching pull already
// converted to this substep's alpha (0…1); `collisionRadius` equals the neighbor
// hash's cell size. Stride 64 (16-aligned).
typedef struct {
    simd_float2 gravity;          // points/s²
    simd_float2 interactionPoint; // pull/push center, canvas points
    simd_float4 box;              // walls: min x, min y, max x, max y (points)
    float interactionStrength;    // signed pull(+)/push(−) acceleration; 0 = none
    float interactionRadius;      // interaction falloff radius, points
    float stiffness;              // shape-match alpha for this substep, 0…1
    float collisionRadius;        // cross-body repulsion range, points
    float collisionStrength;      // repulsion acceleration at full overlap, pt/s²
    float dt;                     // substep seconds
    float wallBounce;             // fraction of normal velocity kept on wall hit
    float damping;                // fraction of velocity kept per second, 0…1
} OllinSoftBodyParams;

// Per-frame parameters for the steering step (`Swarm`), packed by the CPU and bound
// at buffer index 11. Every behavior is a weight, so a zero weight is a behavior
// that is off, and the kernel sums the weighted forces before one truncation at
// `maxForce` (the published combination method). Speeds and forces are per second,
// so the sim keeps its pace whatever the frame rate. Stride 96 (8-aligned).
typedef struct {
    simd_float2 target;           // seek/flee/arrive target, canvas points
    float maxSpeed;               // top speed, points/s
    float maxForce;               // strongest steering force, points/s²
    float separation;             // ── behavior weights, 0 = off ──
    float alignment;
    float cohesion;
    float seek;
    float flee;
    float arrive;
    float wander;
    float flow;
    float separationRadius;       // points; ≤ the hash cell (the perception radius)
    float viewCosine;             // cos of half the field of view; -1 sees all round
    float slowingRadius;          // where arrival begins to ramp down, points
    float wanderRadius;           // radius of the projected wander circle, points
    float wanderDistance;         // how far ahead that circle sits, points
    float wanderRate;             // radians of random displacement per second
    float flowScale;              // flow-field frequency, cycles per point
    float flowLookAhead;          // how far ahead the field is sampled, points
    float minSpeed;               // slowest an agent may travel; 0 lets it stop
    float dt;                     // seconds this step covers
    float _swarmPad0;
    float _swarmPad1;
} OllinSwarmParams;

// Per-frame constants bound to a user-supplied shader's fragment (buffer 1). The
// generated wrapper exposes these to the sketch's `shade(uv, info)` as a
// `ShaderInfo` value, so a shader reads `info.time` / `info.resolution` / … with
// no plumbing. Scalars only (no array member), so the Swift side fills it with the
// plain memberwise initializer; the user's free `params` ride a separate `float4`
// buffer (index 0), read through the `param(info, i)` helper the wrapper defines.
// Stride 32 (16-aligned).
#define OLLIN_SHADER_PARAM_ROWS 16
#define OLLIN_SHADER_PARAM_COUNT (OLLIN_SHADER_PARAM_ROWS * 4)
typedef struct {
    simd_float2 resolution;     // the layer this shader draws into, in pixels
    simd_float2 mouse;          // cursor position in points (top-left origin)
    float time;                 // seconds since the sketch started
    float deltaTime;            // seconds since the previous frame
    unsigned int frame;         // frames drawn so far
    unsigned int paramCount;    // number of valid user floats in the params buffer
} OllinShaderUniforms;

// Per-frame parameters for the strange-attractor step (`AttractorFlow`), packed by
// the CPU and bound at buffer index 11. Every particle rides the same velocity field
// and reads no other particle, so a step is `substeps` fourth-order Runge-Kutta steps
// of size `step`, fixed in the *system's* own time rather than the frame's, because a
// step much larger than the system's scale integrates a different system. The extent
// figures (`seed`, `escapeRadius`, `speedLow`/`speedHigh`) are measured once from a
// short CPU orbit of the same system, so they suit whatever it was tuned to.
// Stride 208 (16-aligned).
typedef struct {
    simd_float4 kA;           // system parameters 0…3
    simd_float4 kB;           // system parameters 4…7 (only Aizawa reaches this far)
    simd_float4 stops[8];     // speed→color ramp, straight RGBA; `stopCount` in use
    simd_float4 seed;         // xyz respawn-box center (world), w its half-extent
    float step;               // one Runge-Kutta step, in the system's own time
    float escapeRadius;       // past this from the seed center a particle is lost
    float speedLow;           // the speed that maps to the ramp's first stop
    float speedHigh;          // the speed that maps to its last
    float size;               // splat diameter, world units
    unsigned int system;      // which system (AttractorSystem.Kind's shader index)
    unsigned int substeps;    // Runge-Kutta steps this frame
    unsigned int stopCount;   // ramp stops in use, 1…8
} OllinAttractorParams;

// Per-frame parameters for the evolving population (`Evolution`), packed by the CPU
// and bound at buffer index 11. Two kernels read this struct: the trial step, which
// flies every individual along its own genome and scores it, and the breeding pass,
// which replaces the population with the children of whoever scored well. The pacing
// figures (`trialDuration`, `thrust`, `maxSpeed`) are derived from the distance a
// trial has to cover rather than named by the sketch, so moving the target re-paces
// the run. Stride 272 (16-aligned).
typedef struct {
    simd_float4 obstacles[8]; // walls, canvas points: xy corner, zw size; `obstacleCount` in use
    simd_float4 stops[4];     // score→color ramp, straight RGBA; `stopCount` in use
    simd_float2 start;        // where every trial begins, canvas points
    simd_float2 target;       // what the population is selected for reaching
    float targetRadius;       // inside this counts as arrived
    float spanToTarget;       // start→target distance: what a score is measured against
    float trialDuration;      // seconds one generation flies for
    float elapsed;            // seconds into the current trial (picks the live gene)
    float thrust;             // what one gene is worth, points/s²
    float maxSpeed;           // top speed an individual may travel, points/s
    float mutationRate;       // chance one gene is nudged when it is copied
    float mutationAmount;     // how far such a nudge may reach (genes live in -1…1)
    float dt;                 // seconds this step covers
    float size;               // dot diameter, points
    unsigned int genes;       // genome length (steering impulses per individual)
    unsigned int tournament;  // rivals each parent is picked as the best of
    unsigned int generation;  // which generation: the breeding pass's random stream
    unsigned int seed;        // the population's own seed, never the sketch's rng
    unsigned int obstacleCount;
    unsigned int stopCount;   // ramp stops in use, 1…4
} OllinEvolutionParams;

// Per-frame parameters for the particle Lenia step (`ParticleLenia`), packed by the
// CPU and bound at buffer index 11. Every particle reads the same numbers: the whole
// model is one energy field E = R - G(U), where U is the sum of a ring-shaped kernel
// over the neighbors, G scores that field, and R pushes anything closer than one unit
// apart. A particle simply walks down the gradient of E at its own position, so there
// is no force law, no velocity, and nothing per-particle to carry.
//
// Lengths are in *paper units*, and `spacing` says how many canvas points one of them
// is worth, so the shape of a configuration is independent of how large it is drawn.
// `wK` is not a free choice: it is the constant that normalizes the kernel over the
// plane, derived on the CPU from `muK`/`sigmaK`, which is what keeps `muG` meaning the
// same thing when the ring moves. Stride 112 (16-aligned).
typedef struct {
    simd_float4 stops[4];     // field→color ramp, straight RGBA; `stopCount` in use
    float muK;                // radius of the kernel's ring of influence, paper units
    float sigmaK;             // how wide that ring is
    float wK;                 // kernel normalization, derived from muK/sigmaK
    float muG;                // the field value growth peaks at (also the color's 1.0)
    float sigmaG;             // how narrow that peak is
    float cRep;               // how hard two particles inside one unit push apart
    float spacing;            // canvas points per paper unit
    float dt;                 // paper time units this step covers
    float size;               // dot diameter, points
    unsigned int stopCount;   // ramp stops in use, 1…4
    float _leniaPad0;
    float _leniaPad1;
} OllinLeniaParams;

// Per-frame parameters for the swarm-chemistry step (`SwarmChemistry`), packed by the
// CPU and bound at buffer index 11. Unlike every other sim here, the numbers that
// decide how a particle moves are *not* in this struct: each particle carries its own
// eight-value recipe in a separate buffer, and this struct only holds what is true of
// the whole world. What is here is the part that makes it evolve rather than merely
// mix: on contact one particle's recipe overwrites the other's, and `competition`
// picks which way it goes.
//
// The kinetic model is discrete-time (its published units are per *step*, not per
// second), so `dt` is in steps and a shared recipe means what it says.
//
// `lengthScale` is what makes that last claim true. The published value ranges were
// chosen for a world whose particles sit about 50 units apart, and the ranges carry
// length: a separation strength is in length²/step². Dropped unconverted into a canvas
// whose particles sit 17 points apart, separation comes out several times too strong
// and the swarm blows apart into an even gas. So recipes are *stored* in the published
// units, and the kernel converts on the way in: lengths and speeds by `lengthScale`,
// separation by its square. Stride 48 (16-aligned).
typedef struct {
    float dt;                  // steps this dispatch covers; 1 is the published step
    float perceptionLimit;     // the largest R a recipe may hold = the hash cell, points
    float contactRadius;       // how close two particles count as colliding, points
    float mutationRate;        // chance a recipe mutates as it is copied
    float mutationAmount;      // how far one mutated value may move, as a fraction of its range
    unsigned int competition;  // SwarmChemistry.Competition.shaderIndex: who transmits
    unsigned int transmits;    // 0 freezes every recipe (a plain heterogeneous swarm)
    unsigned int step;         // which step: the random stream for steering and mutation
    unsigned int seed;         // the sim's own seed, never the sketch's rng
    float size;                // dot diameter, points
    float opacity;             // how much light one particle contributes, 0…1
    float lengthScale;         // this world's mean spacing over the published one's (50)
} OllinSwarmChemistryParams;

// Constants for the final present/tone-map pass (`ollin_present_fragment`). The
// frame renders into a linear `rgba16Float` intermediate; this pass reads it,
// scales by `exposure`, maps high-dynamic-range values into displayable range
// per `toneMapMode`, then dithers + sRGB-encodes to the 8-bit drawable. Not a
// per-shape value — one operation over the whole resolved frame (see
// `Drawer.toneMapMode` / `Sketch.toneMap`).
// The two fields the 8-bit path reads sit first and never move: the shipped
// `ollin_present_fragment` reads only those, so the wide-gamut/HDR fields below
// are appended and its codegen is untouched (see `ollin_present_wide_fragment`,
// the twin that reads them).
typedef struct {
    int   toneMapMode;   // ToneMap.shaderIndex: 0 clamp (SDR), 1 reinhard, 2 aces
    float exposure;      // linear multiplier applied before the tone-map (1 = none)
    int   outputSpace;   // PresentEncoding: 0 sRGB 8-bit, 1 linear Display P3, 2 PQ Rec. 2020
    float ceiling;       // linear-P3 clamp: 1 = SDR white, higher = the display's headroom
    float referenceNits; // what 1.0 means in cd/m² when PQ-encoding (BT.2408 reference white)
    float peakNits;      // brightest luminance carried, in cd/m² (the mastering peak)
} OllinPresentUniforms;

// Constants for the *projected* present pass (`ollin_present_projected_fragment`
// and its wide twin): the corner-pin warp that squares a projector's picture up
// with the wall it lands on, and the edge fades that let one machine's picture
// meet another's without a bright bar down the join. Screen only: an export
// re-renders and never carries either (see `Installation.Projection`).
//
// The warp runs *backwards*. The fragment starts from where it is on the output
// and asks which part of the picture belongs there, so what the GPU reads is the
// map from output to picture rather than the one the four corners describe.
typedef struct {
    simd_float3x3 fromOutput;  // output fractions -> shown-part fractions; multiply (x, y, 1), divide by z
    simd_float2 sourceOrigin;  // where the shown part starts on the canvas, 0…1
    simd_float2 sourceSize;    // how much of the canvas it covers, 0…1
    simd_float4 fade;          // how far the fade reaches from the left/right/top/bottom edge, in shown-part fractions
    float curve;               // the shape of the fade: 1 a straight line, 2 the published S
    float gammaExponent;       // the standard curve (2.2) over the projector's own
} OllinProjectionUniforms;

#endif /* OLLIN_SHADER_TYPES_H */
