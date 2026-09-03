import COllinShaders
import Ollin
import simd

/// Depth of field, *earned* rather than faked. A blurred photograph isn't a sharp
/// image with a blur filter on top; it's countless rays of light that each landed
/// in a slightly different place because they passed through the lens out of
/// focus. This sketch renders that literally. Nine smooth 3D curves are drawn not
/// as lines but as a spray of faint samples scattered along them, and each sample
/// is pushed to a random spot inside a ball whose radius grows with how far that
/// point sits from the focal plane. Where a curve crosses the focus it stays a
/// crisp bright ribbon; away from it the samples spread into soft bokeh. The blur
/// *emerges* from the statistics of where the light fell. There is no blur filter
/// anywhere.
///
/// **It converges.** Every frame scatters a few passes of a million samples, and
/// they are added into an `Accumulator`, which keeps the running *mean* of all the
/// passes so far. The picture settles instead of brightening without end, and the
/// longer you leave it the smoother the bokeh gets; move the focus or the camera
/// and the average starts over. The pieces, each one a framework feature:
///   • a `ComputeBuffer` of the ribbons' own struct read beside the particle
///     buffer, `compute(_:buffers:)` binding the two at indices 0 and 1;
///   • the camera packed for the kernel by `cameraParams()`, so the kernel projects
///     through the sketch's own `Camera3D` with `ollin_project_eye`;
///   • `ballSample` for the scatter, uniform over the ball's volume;
///   • `drawParticles(style: .light)`, the radiometric deposit: every sample
///     leaves `color × alpha × area` wherever it lands, one texel at one pixel;
///   • `withAccumulator` for the running mean, and `developed(exposure:ground:)`
///     to print it: exposure, a Reinhard roll-off, the ground added after the curve.
///
/// A mild perspective makes near samples bloom into bigger discs than far ones,
/// the look of a fast lens. Each sample is drawn as three particles (its red,
/// green, and blue) scattered to slightly different radii, so the bokeh grows
/// chromatic fringes the same emergent way. **Drag left and right to rack focus**,
/// and turn the parameters in the inspector: *Turn* orbits the camera, which
/// restarts the average every frame (each frame is then its own short exposure).
///
/// Inspired by Anders Hoff's depth-of-field and color-shift technique
/// (inconvergent). `LineSpray` wraps this whole pipeline for lines; the
/// `Rendering/LineSpray` example uses it.
@main
final class DepthOfField_Example: Sketch {
    @Param("Focal distance", 3 ... 10) var focalDistance = 6.6
    @Param("Bokeh", 0 ... 0.3) var bokeh = 0.06
    @Param("Color shift", 0 ... 0.5) var colorShift = 0.2
    @Param("Exposure", 1 ... 120) var exposure = 24.0
    @Param("Passes per frame", 1 ... 8) var passesPerFrame = 4
    @Param("Turn") var turning = false

    /// One ribbon: a closed 3D Lissajous figure and its color. The kernel reads
    /// these straight from a buffer of this struct (three float4 rows, 48 bytes).
    private struct Ribbon {
        var frequency: SIMD4<Float>
        var phase: SIMD4<Float>
        var color: SIMD4<Float>
    }

    private let samplesPerPass = 250_000
    /// Light a ribbon emits per pass, spread along its whole length, so a pass
    /// deposits about this much over the thousand or so pixels it crosses.
    private let ribbonLight = 500.0
    private var ribbons: ComputeBuffer<Ribbon>!
    private var samples: PingPong<OllinParticle>!
    private var light: Accumulator!
    private var azimuth = 0.55
    private var lastView: [Double] = []
    private let ground = Color(red: 0.012, green: 0.012, blue: 0.024)

    /// One thread per channel of one sample: pick a ribbon and a spot on it, take
    /// it into camera space, push it into the bokeh ball, project it, and write
    /// the particle the light path draws.
    private let scatter = ComputeKernel(entry: "scatter", """
        struct Ribbon { float4 frequency; float4 phase; float4 color; };
        struct Lens {
            OllinCameraMatrices camera;
            float4 lens;   // x focal distance, y bokeh strength, z color shift, w unused
            float4 misc;   // x seed, y samples per pass, z ribbon count, w light per sample
        };

        kernel void scatter(device const Ribbon *ribbons [[buffer(0)]],
                            device OllinParticle *out [[buffer(1)]],
                            constant OllinComputeUniforms &u [[buffer(10)]],
                            constant Lens &p [[buffer(11)]],
                            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            const float TAU = 6.28318530718;
            uint sample = id / 3u;
            uint channel = id % 3u;
            float3 seed = float3(float(sample & 4095u), float(sample >> 12u), p.misc.x);

            uint count = max(uint(p.misc.z), 1u);
            uint r = min(uint(hash13(seed) * float(count)), count - 1u);
            Ribbon ribbon = ribbons[r];
            float t = hash13(seed + float3(1.7, 2.9, 0.3));
            float3 world = 0.95 * sin(ribbon.frequency.xyz * t * TAU + ribbon.phase.xyz);

            // Into camera space; the defocus is the distance from the focal plane
            // along the view axis, and it sets the ball the sample scatters in.
            float3 eye = (p.camera.view * float4(world, 1.0)).xyz;
            float defocus = abs(-eye.z - p.lens.x);
            float radius = defocus * p.lens.y;
            // Color shift: red scatters a little wider than green, blue tighter,
            // so the fringes of the bokeh come out chromatic.
            float shift = p.lens.z * min(defocus, 1.0);
            float widen = (channel == 0u) ? 1.0 + shift : (channel == 2u) ? 1.0 - shift : 1.0;
            eye += ballSample(seed + float3(3.3, 7.1, 5.5)) * radius * widen;

            float4 screen = ollin_project_eye(p.camera, eye, u.resolution);
            OllinParticle o;
            o.velocity = float2(0.0);
            o.life = 1.0;
            o.seedA = 0.0;
            o.seedB = 0.0;
            if (screen.w <= 0.0) {
                o.position = float2(-16.0);
                o.size = 0.0;
                o.color = float4(0.0);
                out[id] = o;
                return;
            }
            float3 mask = (channel == 0u) ? float3(1, 0, 0)
                        : (channel == 1u) ? float3(0, 1, 0) : float3(0, 0, 1);
            // A one-pixel point, its whole light in the pixel it lands on: alpha
            // is 4/pi over the disc's area, so the deposit is the radiance itself.
            o.position = screen.xy;
            o.size = 1.0;
            o.color = float4(ribbon.color.rgb * mask * p.misc.w, 1.27323954474);
            out[id] = o;
        }
        """)

    override func setup() {
        // Nine closed curves, fixed by the seed: integer frequencies (so each
        // closes), random phases, and hues spaced evenly round the wheel.
        seed(4)
        var table: [Ribbon] = []
        for i in 0 ..< 9 {
            let c = Color(hue: Double(i) / 9, saturation: 0.8, brightness: 1).linearRGBA
            table.append(Ribbon(
                frequency: SIMD4(Float(Int(random(1, 4))), Float(Int(random(1, 4))), Float(Int(random(1, 4))), 0),
                phase: SIMD4(Float(random(.tau)), Float(random(.tau)), Float(random(.tau)), 0),
                color: SIMD4(c.x, c.y, c.z, 1)))
        }
        ribbons = ComputeBuffer(table)
        samples = PingPong(count: samplesPerPass * 8 * 3)
        light = makeAccumulator()
    }

    override func draw() {
        background(ground)
        if turning { azimuth += 0.15 / max(frameRate, 1) }
        let focal = mouseIsPressed ? map(mouseX, 0, width, 3, 10) : focalDistance
        let view = Camera3D.orbiting(target: .zero, radius: 7, azimuth: azimuth,
                                     elevation: 0.35, fieldOfView: .pi / 6)
        camera(view)

        // Anything the picture depends on restarts the average.
        let signature = [azimuth, focal, bokeh, colorShift, Double(passesPerFrame)]
        if signature != lastView {
            lastView = signature
            light.reset()
        }

        // One frame of passes: the kernel writes every sample, the light path
        // deposits them, and the accumulator folds them into its mean.
        let passes = max(1, passesPerFrame)
        let count = samplesPerPass * passes * 3
        var params = cameraParams()
        params.append(SIMD4<Float>(Float(focal), Float(bokeh), Float(colorShift), 0))
        params.append(SIMD4<Float>(Float(random(100)), Float(samplesPerPass), 9,
                                   Float(ribbonLight * 9 / Double(samplesPerPass))))
        let out = samples.write
        compute(scatter, buffers: [ribbons, out], count: count, params: params)
        samples.advance()
        withAccumulator(light, passes: passes) {
            blendMode(.add)
            drawParticles(out, count: count, style: .light)
        }

        drawImage(light.developed(exposure: exposure, ground: ground).image, 0, 0)
        drawCaption("drag to rack focus · \(light.passes) passes")
    }
}
