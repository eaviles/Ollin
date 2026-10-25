import Foundation
import simd
import COllinShaders   // OllinParticle (the GPU particle struct, shared with the shaders)

/// How `drawParticles` turns a particle into pixels.
///
/// - `.marks` (the default) draws each particle as an anti-aliased disc of ink:
///   its coverage is remapped to perceptual alpha, the same carve-out every thin
///   mark in Ollin takes so a sub-pixel dot reads as dark as its area warrants over
///   a light ground, and its color is an sRGB tone linearized on the way in.
/// - `.light` draws each particle as light: the coverage is the plain area ramp,
///   so a particle deposits `color × alpha × area` wherever it lands, exactly linear
///   in its size and independent of where it falls on the pixel grid, and `color`
///   is taken as linear radiance (author an sRGB tone through `srgbToLinear` in the
///   kernel). It is the style for additive accumulation (`blendMode(.add)` into an
///   `Accumulator` or a `noClear` canvas), where the perceptual remap would lift a
///   dot that straddles a pixel corner to more than twice the light of one that
///   lands on a center. A disc at or under one pixel takes a cheap path: its quad
///   is a single texel, so a million one-pixel points cost a million fragments
///   rather than twenty-five million. Drawn into an `Accumulator` that holds
///   nothing else, the pass is single-sample and such a disc spreads its light
///   over the four pixels around it in bilinear shares, which sum to all of it
///   wherever it falls.
public enum ParticleStyle: Sendable, Equatable {
    /// Anti-aliased ink over a ground: perceptual coverage, sRGB color.
    case marks
    /// Radiometric light for additive sums: linear area coverage, linear color,
    /// and a one-texel path for particles at or under one pixel.
    case light
}

/// A GPU particle system in a few lines — the headline of the compute path.
///
/// You give it a count and a per-particle update written as a short MSL **body
/// snippet**; `Particles` generates the full kernel, owns the ping-pong buffers,
/// and renders the particles as additive sub-pixel discs. Drive it from `draw()`:
///
/// ```swift
/// lazy var sand = Particles(count: 1_000_000, step: """
///     if (life <= 0.0) {                       // (re)spawn the dead
///         position = hash22(float2(id, u.frameCount)) * u.resolution;
///         life = 1.0;
///     }
///     position += curlNoise(position * 0.003 + u.time * 0.1) * 60.0 * u.dt;
///     life -= 0.25 * u.dt;
///     color = float4(0.6, 0.8, 1.0, 1.0); size = 1.5;
/// """)
///
/// override func setup() { background(.black); noClear() }
/// override func draw() {
///     blendMode(.add); toneMap(.aces)
///     stepParticles(sand)     // one sim step
///     drawParticles(sand)       // additive discs
/// }
/// ```
///
/// In the snippet these locals are in scope, read and write them freely:
/// `position` (`float2`), `velocity` (`float2`), `color` (`float4` straight RGBA),
/// `size` (on-screen diameter, points), `life` (`float`), and the scratch
/// `seedA`/`seedB` (`float`). Read-only: `id` (`uint` particle index), `u`
/// (`OllinComputeUniforms` — `u.time`/`u.dt`/`u.resolution`/`u.mouse`/…), and
/// `custom` (`float4`, the live parameters you pass to `stepParticles(_:custom:)`).
/// The shader-library helpers (`hash12`, `valueNoise`, `curlNoise`, `discSample`,
/// `palette`, …) are available. The particle struct is `OllinParticle`.
///
/// A step can read pictures. Hand them to `stepParticles(_:custom:textures:)`
/// and read one at a canvas point with `picture(index, point)`, which returns
/// its color as linear light, multiplied by its alpha, sampled smoothly and held
/// at the edge. A layer is read as drawn this frame, so particles can steer by
/// what the sketch draws:
///
/// ```swift
/// // In the step: turn along the brightness of a blurred layer.
/// float here = picture(0, position).r;
/// float ahead = picture(0, position + velocity * 4.0).r;
/// velocity = rotate2D(velocity, (ahead - here) * 6.0 * u.dt);
/// ```
///
/// A picture not handed over reads as clear.
///
/// For a custom signature or layout, pass a full `ComputeKernel` via
/// `init(count:kernel:)`, or drop to the raw `compute(_:reading:writing:)` /
/// `drawParticles(_ buffer:)` primitives.
@MainActor
public final class Particles {
    /// Number of particles.
    public let count: Int
    private let kernel: ComputeKernel
    private let pingpong: PingPong<OllinParticle>

    /// Build a system of `count` particles whose per-particle update is the MSL
    /// `step` body (see the type doc for the locals in scope).
    public convenience init(count: Int, step: String) {
        self.init(count: count, kernel: Particles.wrap(step))
        readsFourPictures = true
    }

    /// Build a system from a full `ComputeKernel`. Its entry must have the
    /// signature `(device const OllinParticle* [[buffer(0)]], device OllinParticle*
    /// [[buffer(1)]], constant OllinComputeUniforms& [[buffer(10)]], constant
    /// float4& [[buffer(11)]], uint id [[thread_position_in_grid]])` and write
    /// buffer 1 from buffer 0, the layout `init(count:step:)` generates. The
    /// pictures handed to `stepParticles(_:custom:textures:)` bind at texture
    /// indices 0… with a linear clamped sampler at sampler index 0.
    public init(count: Int, kernel: ComputeKernel) {
        precondition(count > 0, "Particles needs a positive count")
        self.count = count
        self.kernel = kernel
        self.pingpong = PingPong(count: count)
    }

    /// Whether the kernel declares all four picture slots (the generated step
    /// does), so every slot is bound, with a clear stand-in where no picture
    /// was handed over.
    private var readsFourPictures = false

    /// The clear one-pixel picture an unfilled slot of the generated step reads.
    private static let clearPicture = ImageComputeTexture(Image(width: 1, height: 1), readsLight: true)

    /// The buffer holding the current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Record one simulation step into `drawer` and swap the ping-pong so `current`
    /// becomes the freshly written buffer. Called by `Sketch.stepParticles`.
    func recordStep(into drawer: Drawer, custom: SIMD4<Float>, textures: [Image] = []) {
        let read = pingpong.read, write = pingpong.write
        var bytes: [UInt8] = []
        withUnsafeBytes(of: custom) { bytes.append(contentsOf: $0) }
        var bound: [ComputeTextureBindable?] = textures.map { ImageComputeTexture($0, readsLight: true) }
        if readsFourPictures {
            while bound.count < 4 { bound.append(Particles.clearPicture) }
        }
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count, buffers: [read, write],
            textures: bound, params: bytes))
        pingpong.swap()   // at record time, so the following draw reads the output
    }

    /// Wrap a body snippet into a complete particle-step kernel: bind the ping-pong
    /// buffers and standard uniforms, expose the particle fields as locals around
    /// the user's statements, and write the result back.
    private static func wrap(_ body: String) -> ComputeKernel {
        let source = """
        static inline float4 ollin_particles_picture(uint index, float2 point, float2 resolution,
                                                     texture2d<float> p0, texture2d<float> p1,
                                                     texture2d<float> p2, texture2d<float> p3,
                                                     sampler s) {
            float2 uv = point / max(resolution, float2(1.0));
            switch (index) {
                case 0: return p0.sample(s, uv, level(0));
                case 1: return p1.sample(s, uv, level(0));
                case 2: return p2.sample(s, uv, level(0));
                case 3: return p3.sample(s, uv, level(0));
                default: return float4(0.0);
            }
        }
        #define picture(index, point) ollin_particles_picture((index), (point), u.resolution, \\
            _picture0, _picture1, _picture2, _picture3, _pictureSampler)

        kernel void ollin_particles_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            constant OllinComputeUniforms &u   [[buffer(10)]],
            constant float4 &custom            [[buffer(11)]],
            texture2d<float> _picture0         [[texture(0)]],
            texture2d<float> _picture1         [[texture(1)]],
            texture2d<float> _picture2         [[texture(2)]],
            texture2d<float> _picture3         [[texture(3)]],
            sampler _pictureSampler            [[sampler(0)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle _p = inBuf[id];
            float2 position = _p.position;
            float2 velocity = _p.velocity;
            float4 color    = _p.color;
            float  size     = _p.size;
            float  life     = _p.life;
            float  seedA    = _p.seedA;
            float  seedB    = _p.seedB;
            {
        \(body)
            }
            _p.position = position; _p.velocity = velocity; _p.color = color;
            _p.size = size; _p.life = life; _p.seedA = seedA; _p.seedB = seedB;
            outBuf[id] = _p;
        }
        """
        return ComputeKernel(entry: "ollin_particles_step", source)
    }
}
