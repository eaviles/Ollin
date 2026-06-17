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
//   - `Shaders.metal` `#include`s it for the GPU-side definitions.
//   - At runtime the shader source is compiled with `makeLibrary(source:)`,
//     which has no include search path, so `MetalRenderer` splices this file's
//     text in place of the `#include` directive. That's why the header ships
//     beside `Shaders.metal` as a resource. A precompiled metallib, by
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

// One vertex of tessellated (triangle-path) geometry: float2 @0, float4 @16,
// for a stride of 32.
typedef struct {
    simd_float2 position;   // sketch-space, points, top-left origin, y-down
    simd_float4 color;      // straight (non-premultiplied) RGBA, 0...1
} OllinVertex;

// Per-frame constants, shared by both pipelines.
typedef struct {
    simd_float2 viewport;   // logical canvas size in points (width, height)
    float clipDepth;        // clip-space z (Metal NDC, [0,1]) the 2D vertex shaders
                            // emit, so 2D draws can occlude/be occluded by 3D
                            // geometry in a depth pass (see depth(at:)). 0 in a
                            // 2D-only frame, so those frames are byte-identical.
} Uniforms;

// Per-frame constants for the 3D pipelines (an active `Camera3D`). Bound at
// vertex buffer index 2 — distinct from the 2D `Uniforms` at index 1, so a 3D
// batch and the 2D batches around it (HUD/captions) each read their own without
// rebinding. World space is right-handed, y-up; `view` takes a world point into
// camera space (camera down −z) and `projection` into Metal clip space (z ∈ [0,1]).
typedef struct {
    simd_float4x4 view;        // world -> camera space
    simd_float4x4 projection;  // camera -> clip space (Metal z in [0,1])
    simd_float2 viewport;      // drawable size in points (for any screen-space math)
} Uniforms3D;

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
// with lights it shades `color` per the material model. The material's specular
// strength + shininess ride the spare `w` slots
// (`position.w`/`normal.w`) — the vertex shader reads only `position.xyz`/`normal.xyz`.
// `uv` carries texture coordinates (0,0 … 1,1) for the textured-mesh pipeline; the
// solid `ollin_mesh_vertex`/`_fragment` read only position/normal/color, so an
// untextured mesh leaves `uv` zero and is unaffected by it. Triangle indices are
// expanded into a flat list on the CPU (no index buffer), matching the 2D triangle
// path. Stride 64 (four 16-byte rows): float4 @0, float4 @16, float4 @32, float2 @48
// (+ 8 bytes pad, a reserved slot, e.g. a tangent later).
typedef struct {
    simd_float4 position;   // world-space xyz (model matrix baked in); w = specular strength (0…1)
    simd_float4 normal;     // world-space normal (normal matrix baked in); w = shininess exponent
    simd_float4 color;      // straight RGBA diffuse; rgb = surface color, a = opacity
    simd_float2 uv;         // texture coordinates, 0…1 (textured-mesh pipeline; 0 when untextured)
} OllinMeshVertex;

// Lighting for the 3D mesh model (the Blinn-Phong material on `ollin_mesh_fragment`).
// Per-frame state, like the camera: the sketch sets lights each `draw()` (see
// `Sketch.directionalLight`/`pointLight`/`spotLight`/`ambientLight`), and the renderer
// packs them into one `OllinLighting` bound to the mesh fragment. With `enabled == 0`
// (no lights and no ambient set) the fragment keeps the byte-identical normal-as-color
// path, so a 3D frame that sets no light renders exactly as before.

#define OLLIN_MAX_LIGHTS 8

// One light. `kind`: 0 directional (parallel rays), 1 point (omni from a position),
// 2 spot (point gated by a cone). Colors are linear (sRGB→linear on the CPU) and
// premultiplied by intensity. There's no distance attenuation in this model.
typedef struct {
    simd_float4 color;       // rgb = linear color × intensity; a unused
    simd_float4 position;    // point/spot: world-space position; w unused
    simd_float4 direction;   // directional: unit direction *to* the light; spot: unit cone axis (light's travel direction); w unused
    int   kind;              // 0 directional, 1 point, 2 spot
    float cosInner;          // spot: cosine of the inner half-angle (full brightness within)
    float cosOuter;          // spot: cosine of the outer half-angle (zero beyond); inner→outer is the soft penumbra
    float _pad;
} OllinLight;

// Shadow mapping (opt-in, `castShadows()`): one directional light casts. The
// caster's contribution is dimmed where a depth pass from its point of view found
// an occluder nearer than the receiver. `shadowLight` is the index of that light
// in `lights` (or -1 when shadows are off — then the mesh fragment is byte-identical
// to the unshadowed path); `lightViewProjection` takes a world point into the
// caster's clip space (an orthographic box auto-fit to the camera target);
// `shadowStrength` scales the darkening (1 = full); `shadowTexelWorld` is the
// world-space size of one shadow-map texel, the scale-invariant unit for the
// normal-offset bias.
typedef struct {
    simd_float4 ambient;          // rgb linear ambient (lights every surface flatly); a unused
    simd_float4 cameraPosition;   // world-space eye xyz (for the specular view direction); w unused
    OllinLight lights[OLLIN_MAX_LIGHTS];
    int lightCount;               // number of valid entries in `lights`
    int enabled;                  // 1 = lit shading (any light or ambient set); 0 = normal-as-color (unchanged)
    int shadowLight;              // index of the shadow-casting light in `lights`, or -1 (no shadows)
    float shadowStrength;         // 0…1 darkening applied to the caster where occluded
    simd_float4x4 lightViewProjection;  // world -> shadow-caster clip space
    float shadowTexelWorld;       // world-space size of one shadow-map texel (normal-bias scale)
    float _pad0;
    float _pad1;
    float _pad2;
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

// Constants for the final present/tone-map pass (`ollin_present_fragment`). The
// frame renders into a linear `rgba16Float` intermediate; this pass reads it,
// scales by `exposure`, maps high-dynamic-range values into displayable range
// per `toneMapMode`, then dithers + sRGB-encodes to the 8-bit drawable. Not a
// per-shape value — one operation over the whole resolved frame (see
// `Drawer.toneMapMode` / `Sketch.toneMap`).
typedef struct {
    int   toneMapMode;   // ToneMap.shaderIndex: 0 clamp (SDR), 1 reinhard, 2 aces
    float exposure;      // linear multiplier applied before the tone-map (1 = none)
} OllinPresentUniforms;

#endif /* OLLIN_SHADER_TYPES_H */
