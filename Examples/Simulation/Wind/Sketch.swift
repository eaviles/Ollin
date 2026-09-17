import Ollin

/// A simulation of your own: a wind that carries dust, run by two Metal kernels this
/// sketch writes rather than a rule from the catalog.
///
/// The field holds a wind in red and green and dust in blue. The **step** kernel
/// relaxes each cell's wind toward its four neighbors (a viscosity), turns it a little
/// by the brightness of a noise layer the sketch hands the field as an *input* (the
/// weather), and carries the dust from upwind. The **inject** kernel is how a drawn
/// mark enters the field: a drag pushes the wind along the brush's motion, which the
/// sketch passes in as the shader's two parameters, and drops dust where the brush
/// went. The edge is a live choice: wrapping, the wind and the dust come back around;
/// clamped, they pile against the walls. The picture is the dust through a ramp with
/// the wind's own arrows over it (`.arrows`), and every half second the sketch reads
/// the field back (`snapshot()`) to print the mean wind speed.
///
/// Drag to push the wind; left alone, a gust arrives every second. Press any
/// key to clear.
@main
final class Wind: Sketch {
    /// How hard the weather turns the wind.
    @Param(0 ... 1) var stirring = 0.35
    /// Pixels of arrow per unit of wind.
    @Param(0 ... 80) var arrowScale = 36.0
    /// Draw the wind's arrows over the dust.
    @Param var drawsArrows = true
    /// Whether the field wraps around (a torus) or stops at walls.
    @Param var wraps = true

    private var wind: SimField!
    private var lastMouse: Vector2?
    private var meanSpeed = 0.0

    /// Every cell: wind toward its neighbors and a little toward a trade wind that
    /// turns with the clock (the shader's second parameter is its heading), turned by
    /// the weather (the first parameter is how hard), dust carried in from upwind.
    /// `sampleRaw` reads the state anywhere, so the carry is one read a little way
    /// against the wind.
    private let stepSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float4 me = cell(info);
        float2 around = (cell(info, -1, 0).xy + cell(info, 1, 0).xy
                       + cell(info, 0, -1).xy + cell(info, 0, 1).xy) * 0.25;
        float2 trade = float2(cos(param(info, 1)), sin(param(info, 1))) * 0.35;
        float2 v = mix(mix(me.xy, around, 0.5), trade, 0.02);
        float turn = (input(info, 0).r - 0.5) * param(info, 0);
        v = float2(v.x * cos(turn) - v.y * sin(turn), v.x * sin(turn) + v.y * cos(turn));
        float dust = sampleRaw(info, uv - v * info.texel * 2.0).z * 0.996;
        return float4(v, dust, 1.0);
    }
    """

    /// The inject's source: the brush's motion arrives as the two parameters, so a
    /// mark pushes the wind that way and drops dust where it lands.
    private let injectSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float4 me = cell(info);
        float4 m = mark(info);
        float2 push = float2(param(info, 0), param(info, 1)) * m.a;
        return float4(me.xy + push, min(me.z + m.a, 1.0), 1.0);
    }
    """

    /// The dust alone, as a gray the ramp below recolors.
    private let dust = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float d = sampleRaw(info, uv).z;
        return float4(d, d, d, 1.0);
    }
    """)

    /// The two kernels with this frame's numbers: the stirring on the step, the
    /// brush's push on the inject. Same source each frame, so nothing recompiles.
    private func sim(push: Vector2) -> Sim {
        .shader(Shader(stepSource, params: [Float(stirring), Float(time * 0.15)]),
                inject: Shader(injectSource, params: [Float(push.x), Float(push.y)]))
    }

    override func setup() {
        wind = makeSimField(sim(push: .zero), scale: 0.5)
    }

    override func draw() {
        background(Color(hex: 0x0B0F14))
        wind.edge = wraps ? .wrapping : .clamped

        // The weather: a noise layer generated each frame, read by the step as input 0.
        wind.inputs = [generate(.noise(scale: 2.5, sharpness: 0.2,
                                       warp: 0.3 + 0.2 * sin(time * 0.1)))]

        // The brush: its motion since last frame becomes the inject's push. Left
        // alone, the sketch breathes on its own: a gust from a random spot every
        // two seconds, so the field has weather before a hand arrives.
        let now = Vector2(mouseX, mouseY)
        var push = Vector2.zero
        var gust: Vector2?
        if mouseIsPressed, let last = lastMouse {
            push = (now - last) * 0.06
        } else if frameCount % 60 == 1 {
            let angle = random(.tau)
            push = Vector2(cos(angle), sin(angle)) * 0.8
            gust = Vector2(random(width * 0.2, width * 0.8), random(height * 0.2, height * 0.8))
        }
        lastMouse = mouseIsPressed ? now : nil
        wind.sim = sim(push: push)
        withField(wind) {
            noStroke(); fill(.white)
            if mouseIsPressed { drawCircle(now.x, now.y, 34) }
            if let gust { drawCircle(gust.x, gust.y, 70) }
        }

        // The picture: dust through a ramp, the wind's arrows over it.
        drawImage(wind.filtered(.shader(dust)).filtered(.gradientMap(.mako)).image, 0, 0)
        if drawsArrows {
            drawImage(wind.filtered(.arrows(spacing: 36, scale: arrowScale,
                                            color: Color(white: 1, alpha: 0.7), width: 1.5)).image, 0, 0)
        }

        // The readback: every half second, the mean wind speed over the whole field.
        if frameCount % 30 == 0, let snap = wind.snapshot() {
            var sum = 0.0
            var n = 0
            for y in stride(from: 0, to: snap.height, by: 4) {
                for x in stride(from: 0, to: snap.width, by: 4) {
                    let v = snap[x, y]
                    sum += Double((v.x * v.x + v.y * v.y).squareRoot())
                    n += 1
                }
            }
            meanSpeed = n > 0 ? sum / Double(n) : 0
        }
        fill(Color(white: 1, alpha: 0.8)); noStroke()
        textSize(18)
        drawText(String(format: "mean wind %.3f", meanSpeed), 24, height - 28)
    }

    override func keyPressed() {
        wind = makeSimField(sim(push: .zero), scale: 0.5)
    }
}
