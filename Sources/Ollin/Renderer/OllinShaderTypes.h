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
} Uniforms;

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
// point. Adding `param2` takes the stride to 144 (still 16-aligned), leaving 8
// bytes of tail padding for future fields.
typedef struct {
    simd_float3x3 transform;   // local sketch space -> sketch space (the CTM)
    simd_float2 center;        // shape center, local sketch space
    simd_float2 size;          // generic half-extent (see SDFShape)
    simd_float4 fillColor;     // straight RGBA; alpha 0 means no fill
    simd_float4 strokeColor;   // straight RGBA; alpha 0 means no stroke
    simd_float2 param0;        // shape-specific
    simd_float2 param1;        // shape-specific
    simd_float2 param2;        // shape-specific
    float strokeWidth;         // points; 0 means no stroke
    float extra;               // shape-specific scalar
    float bandWidth;           // hollow-band width (points); 0 means solid fill
    unsigned int shape;        // SDFShape.rawValue (32-bit on Apple platforms)
} SDFInstance;

#endif /* OLLIN_SHADER_TYPES_H */
