import Foundation

/// A GPU compute kernel — a Metal `kernel` function plus the name to call it by.
///
/// `ComputeKernel` is a value: it carries only the MSL `source` and the `entry`
/// function name, and is constructible anywhere (a sketch property, a `let`) with
/// no device. The renderer compiles it lazily on first dispatch and caches the
/// pipeline by the source's hash, so re-creating the same kernel value each frame
/// is free. Before compiling, the renderer splices in `<metal_stdlib>`, the shared
/// CPU↔GPU types (`OllinParticle`, `OllinComputeUniforms`), and the compute prelude
/// (`OllinCompute.h` — `hash21`/`valueNoise`/`curlNoise`/`discSample`/…), so a
/// kernel can use those directly without writing any includes (see
/// `MetalRenderer.composeComputeSource`).
///
/// Standard per-frame constants are bound at **buffer index 10** as
/// `OllinComputeUniforms` (read `u.time`, `u.dt`, `u.resolution`, `u.mouse`,
/// `u.frameCount`, `u.particleCount`), and an optional 4-float "custom" knob bag
/// (or any `ComputeParams` bytes) at **index 11**. Bind your own buffers at
/// indices 0…9.
///
/// Most particle sketches never write a `ComputeKernel` by hand — the `Particles`
/// convenience generates one from a body snippet. Reach for this directly when you
/// want full control over the kernel signature or a custom buffer layout.
public struct ComputeKernel: Sendable {
    /// The kernel's MSL source — one or more `kernel` functions. The shared types
    /// and the compute prelude are spliced in ahead of this at compile time, so
    /// reference `OllinParticle` / `curlNoise` / … freely; write no `#include`s.
    public let source: String
    /// The name of the `kernel` function to dispatch.
    public let entry: String

    /// Make a kernel from MSL `source`, dispatching the function named `entry`.
    public init(entry: String, _ source: String) {
        self.entry = entry
        self.source = source
    }
}
