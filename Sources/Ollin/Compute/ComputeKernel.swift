import Foundation

/// A GPU compute kernel — a Metal `kernel` function plus the name to call it by.
///
/// `ComputeKernel` is a value: it carries only the MSL `source` and the `entry`
/// function name, and is constructible anywhere (a sketch property, a `let`) with
/// no device. The renderer compiles it lazily on first dispatch and caches the
/// pipeline by the source's hash, so re-creating the same kernel value each frame
/// is free. Before compiling, the renderer splices in `<metal_stdlib>`, the shared
/// CPU↔GPU types (`OllinParticle`, `OllinComputeUniforms`), and the shared shader
/// library (`OllinShaderLib`: `hash12`/`valueNoise`/`curlNoise`/`discSample`/
/// `palette`/the `sd*` catalog/…, the same helpers fragment shaders get), so a
/// kernel can use those directly without writing any includes (see
/// `MetalRenderer.composeComputeSource`).
///
/// Standard per-frame constants are bound at **buffer index 10** as
/// `OllinComputeUniforms` (read `u.time`, `u.dt`, `u.resolution`, `u.mouse`,
/// `u.frameCount`, `u.particleCount`), and an optional 4-float "custom" parameter bag
/// (or any `ComputeParams` bytes) at **index 11**. Bind your own buffers at
/// indices 0…9.
///
/// Most particle sketches never write a `ComputeKernel` by hand — the `Particles`
/// convenience generates one from a body snippet. Reach for this directly when you
/// want full control over the kernel signature or a custom buffer layout.
public struct ComputeKernel: Sendable {
    /// The kernel's MSL source — one or more `kernel` functions. The shared types
    /// and the shader library are spliced in ahead of this at compile time, so
    /// reference `OllinParticle` / `curlNoise` / … freely; write no `#include`s.
    public let source: String
    /// The name of the `kernel` function to dispatch.
    public let entry: String
    /// Where the source came from, so a `#include "…"` inside it resolves against that
    /// file's own folder: the `.metal` file for the resource and file forms, and the
    /// `.swift` the string was written in for the inline form.
    let sourcePath: String

    /// Make a kernel from MSL `source`, dispatching the function named `entry`.
    public init(entry: String, _ source: String, file: String = #filePath) {
        self.entry = entry
        self.source = source
        self.sourcePath = file
    }

    /// Load a kernel's MSL from a bundled **`.metal` resource file**, dispatching the
    /// function named `entry`. Keeping kernels in their own `.metal` files (rather
    /// than inline Swift strings) gives them real Metal syntax highlighting and
    /// editor checking; the shared types and the shader library are still spliced in
    /// at compile time, so the file references `OllinComputeUniforms` / `hash22` /
    /// `curlNoise` / … freely and writes no `#include`s. One file may hold several
    /// kernels — load each as its own `ComputeKernel` with a different `entry` (they
    /// share one compile, the pipeline cache keys on source + entry).
    ///
    /// `in:` has no default on purpose: a default argument would resolve to Ollin's
    /// own bundle, never the caller's — pass `.module` from the sketch that bundles
    /// the `.metal` file (and list it as a `.copy` resource on the target). Returns
    /// `nil` if the resource isn't found or can't be read. `withExtension` defaults
    /// to `"metal"`.
    public init?(entry: String, resource name: String,
                 withExtension ext: String = "metal", in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.entry = entry
        self.source = source
        self.sourcePath = url.path
    }

    /// Load a kernel's MSL from a `.metal` file at `url`, dispatching `entry`. Like
    /// `init(entry:resource:in:)` but from an arbitrary file path (a kernel a sketch
    /// writes or fetches at runtime). Returns `nil` if the file can't be read.
    public init?(entry: String, contentsOf url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.entry = entry
        self.source = source
        self.sourcePath = url.path
    }
}
