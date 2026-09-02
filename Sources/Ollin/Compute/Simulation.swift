import Foundation
import simd

/// A GPU ping-pong texture simulation in a few lines — the texture-half headline of
/// the compute path, the way `Particles` is the buffer-half headline.
///
/// You give it a size and a per-cell update written as a short MSL **body snippet**;
/// `Simulation` generates the kernel, owns the ping-pong textures, and hands back an
/// `image` you draw. It's the engine for reaction-diffusion, cellular automata,
/// fluid, and any field that evolves by reading its neighbors each step:
///
/// ```swift
/// lazy var gray = Simulation(width: 512, height: 512, substeps: 12, step: """
///     // Gray-Scott reaction-diffusion: A in .r, B in .g.
///     float2 lap = -value.xy
///         + 0.2  * (tap(-1,0).xy + tap(1,0).xy + tap(0,-1).xy + tap(0,1).xy)
///         + 0.05 * (tap(-1,-1).xy + tap(1,-1).xy + tap(-1,1).xy + tap(1,1).xy);
///     float a = value.x, b = value.y, reaction = a * b * b;
///     float feed = custom.x, kill = custom.y;
///     result.x = clamp(a + (1.0 * lap.x - reaction + feed * (1.0 - a)), 0.0, 1.0);
///     result.y = clamp(b + (0.5 * lap.y + reaction - (kill + feed) * b), 0.0, 1.0);
/// """)
///
/// override func draw() {
///     if frameCount == 0 { compute(seedKernel, writing: gray.current) }  // initial state
///     updateSimulation(gray, custom: SIMD4(feed, kill, 0, 0))
///     drawImage(gray.image, in: Rectangle(x: 0, y: 0, width: width, height: height))
/// }
/// ```
///
/// In the snippet these are in scope:
/// - `value` (`float4`) — this cell's current value (read).
/// - `result` (`float4`) — what to write, pre-initialised to `value` (write).
/// - `tap(dx, dy)` (`float4`) — the source field at integer offset `(dx, dy)`, with
///   **toroidal wrap** (the edges join), for neighbor stencils.
/// - `gid` (`uint2`) — this cell's coordinate; `size` (`uint2`) — the field size.
/// - `u` (`OllinComputeUniforms` — `u.time`/`u.dt`/`u.frameCount`/…) and `custom`
///   (`float4`, the live parameters from `updateSimulation(_:custom:)`), both read-only.
/// - the shader-library helpers (`hash12`, `valueNoise`, `srgbToLinear`, …).
///
/// Fresh textures start zeroed; seed a sim's initial state with a one-shot
/// `compute(_:writing: sim.current)` on the first frame. For a custom signature or a
/// non-ping-pong layout, drop to the raw `ComputeTexture` + `compute(...)` core.
@MainActor
public final class Simulation {
    /// Field width in texels.
    public let width: Int
    /// Field height in texels.
    public let height: Int
    /// How many kernel steps run per `updateSimulation` call (a sim that needs many
    /// small iterations per frame for stability runs them in one command buffer).
    public let substeps: Int
    private let kernel: ComputeKernel
    private let pingpong: PingPongTexture

    /// Build a `width`×`height` simulation whose per-cell update is the MSL `step`
    /// body (see the type doc for the locals in scope). `substeps` kernel iterations
    /// run per `updateSimulation` call (default 1); `format` is the texel layout
    /// (default `.rgba16Float`).
    public convenience init(width: Int, height: Int, substeps: Int = 1,
                            format: ComputeTextureFormat = .rgba16Float, step: String) {
        self.init(width: width, height: height, substeps: substeps, format: format,
                  kernel: Simulation.wrap(step))
    }

    /// Build a simulation from a full `ComputeKernel`. Its entry must have the
    /// signature `(texture2d<float, access::read> [[texture(0)]], texture2d<float,
    /// access::write> [[texture(1)]], constant OllinComputeUniforms& [[buffer(10)]],
    /// constant float4& [[buffer(11)]], uint2 gid [[thread_position_in_grid]])` and
    /// write texture 1 from texture 0 — the layout `init(…step:)` generates.
    public init(width: Int, height: Int, substeps: Int = 1,
                format: ComputeTextureFormat = .rgba16Float, kernel: ComputeKernel) {
        precondition(width > 0 && height > 0, "Simulation needs a positive size")
        precondition(substeps > 0, "Simulation needs at least one sub-step")
        self.width = width
        self.height = height
        self.substeps = substeps
        self.kernel = kernel
        self.pingpong = PingPongTexture(width: width, height: height, format: format)
    }

    /// The texture holding the current field — what `image` wraps, and what to seed
    /// (`compute(_:writing: sim.current)`) before the first step.
    public var current: ComputeTexture { pingpong.read }

    /// The current field wrapped as an `Image` for `drawImage` (the latest GPU
    /// contents, resolved at draw time).
    public var image: Image { pingpong.read.image }

    /// Record `substeps` simulation steps into `drawer`, swapping the ping-pong after
    /// each so `current` ends on the freshly written field. Called by
    /// `Sketch.updateSimulation`. `custom` is bound (always 16 bytes) at index 11.
    func recordUpdate(into drawer: Drawer, custom: SIMD4<Float>) {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: custom) { bytes.append(contentsOf: $0) }
        for _ in 0..<substeps {
            let read = pingpong.read, write = pingpong.write
            drawer.recordDispatch(RecordedDispatch(
                kernel: kernel, gridWidth: width, gridHeight: height,
                textures: [read, write], params: bytes))
            pingpong.advance()
        }
    }

    /// Wrap a body snippet into a complete texture-step kernel: read the source
    /// field at this cell (and, via `tap`, its neighbors), expose `value`/`result`/
    /// `size` around the user's statements, and write the result.
    private static func wrap(_ body: String) -> ComputeKernel {
        let source = """
        kernel void ollin_simulation_step(
            texture2d<float, access::read>  _src [[texture(0)]],
            texture2d<float, access::write> _dst [[texture(1)]],
            constant OllinComputeUniforms &u   [[buffer(10)]],
            constant float4 &custom            [[buffer(11)]],
            uint2 gid [[thread_position_in_grid]]) {
            uint2 size = uint2(_dst.get_width(), _dst.get_height());
            if (gid.x >= size.x || gid.y >= size.y) { return; }
            // Toroidal neighbor read: positive-modulo wrap so any integer offset is
            // in range and the field's edges join.
            #define _wrap(V, N) ((((int(V)) % int(N)) + int(N)) % int(N))
            #define tap(DX, DY) _src.read(uint2(_wrap(int(gid.x) + (DX), size.x), _wrap(int(gid.y) + (DY), size.y)))
            float4 value = _src.read(gid);
            float4 result = value;
            {
        \(body)
            }
            _dst.write(result, gid);
            #undef tap
            #undef _wrap
        }
        """
        return ComputeKernel(entry: "ollin_simulation_step", source)
    }
}
