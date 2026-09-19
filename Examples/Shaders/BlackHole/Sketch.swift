import Ollin

/// A black hole, drawn by following light backward past it.
///
/// Every pixel is a ray leaving the camera. Near the hole a ray does not go
/// straight: it curves in its plane by the orbit equation of general
/// relativity, and it either falls in (the shadow), crosses the thin disk of
/// hot gas circling the hole, or reaches the sky somewhere other than where it
/// was pointing. That last is why the stars near the edge smear into arcs, and
/// why the far side of the disk shows over the top of the hole and under it:
/// light from behind comes round.
///
/// The disk shines as a black body at the temperature its radius gives it, and
/// the camera sees that temperature shifted by g, the ratio of the frequency
/// that arrives to the frequency that left. Climbing out of the hole's well
/// lowers g everywhere, and the gas's own motion raises it on the side turning
/// toward the camera and lowers it on the side turning away, so one side of
/// the disk burns blue-white and the other smolders red. `beaming` scales only
/// that motion, so at 0 the two sides match.
///
/// Drag to move round the hole and scroll to come closer. The beacon is one
/// bright star placed directly behind the hole from where the camera starts:
/// there its light arrives from every side at once, as a ring, and as the
/// camera drifts off that line the ring breaks into two arcs, one each side.
/// The grid sky shows the same folding on lines of latitude and longitude.
///
/// All the work is two `.metal` files beside this one: `physics.metal` for the
/// light paths, the disk and the color of heat, and `blackhole.metal` for the
/// camera and the sky, which includes the first. Swift only turns the
/// parameters into the numbers the shader reads.
///
/// Inspired by the black-hole piece in the vgpu example gallery (Vercel Labs,
/// MIT, https://github.com/vercel-labs/vgpu), read for which pieces are worth
/// having rather than for code: it is WGSL over WebGPU, and nothing in it
/// transfers as source. The physics is written from the published sources: the
/// orbit equation for light in the Schwarzschild geometry, and the thin disk's
/// image, flux and shift as J.-P. Luminet worked them out in "Image of a
/// spherical black hole with thin accretion disk" (Astronomy and Astrophysics
/// 75, 1979), with the disk's flux from D. N. Page and K. S. Thorne (1974). The
/// color of a black body goes through the CIE 1931 observer in the fit of C.
/// Wyman, P.-P. Sloan and P. Shirley (Journal of Computer Graphics Techniques 2,
/// 2013). All are credited in ATTRIBUTION.md.
@main
final class BlackHole_Example: Sketch {
    override var canvasSize: CanvasSize { .fhd1080 }

    enum Sky: CaseIterable, ParamOption {
        case stars, grid
    }

    // MARK: Parameters

    /// How far the camera hovers from the hole, in horizon radii. Scroll to
    /// change it.
    @Param(5 ... 120, icon: "arrow.left.and.right") var distance = 26.0
    /// Height above the disk's plane, in degrees. Near 0 the disk is edge-on
    /// and its far side stands up over the hole.
    @Param(-85 ... 85, icon: "angle") var elevation = 7.0
    /// How fast the camera drifts round the hole, in degrees a second.
    @Param(-20 ... 20, icon: "arrow.clockwise") var drift = 1.5
    /// The vertical field of view, in degrees.
    @Param(10 ... 100, icon: "camera") var fieldOfView = 38.0
    /// The outer edge of the disk, in horizon radii. The inner edge is the
    /// innermost stable orbit, 3, where the gas stops circling and falls.
    @Param(6 ... 30, icon: "circle.circle") var diskSize = 14.0
    /// The disk's hottest temperature in kelvin, before any shift.
    @Param(2000 ... 20000, icon: "thermometer.medium") var temperature = 4500.0
    /// How much of the Doppler shift and beaming to keep: 1 is the physics, 0
    /// makes both sides of the disk the same.
    @Param(0 ... 1, icon: "sun.max") var beaming = 1.0
    /// How clumped the gas is: 0 a smooth disk, 1 streaks with gaps between.
    @Param(0 ... 1, icon: "wind") var turbulence = 0.8
    /// How fast the gas turns, as a multiple of a clock where one second is the
    /// time light takes to cross one horizon radius.
    @Param(0 ... 40, icon: "hurricane") var spin = 8.0
    @Param(icon: "sparkles") var sky = Sky.stars
    @Param(0 ... 3, icon: "star") var starlight = 1.0
    @Param(icon: "scope") var beacon = true
    @Param(0.1 ... 8, icon: "plusminus") var exposure = 0.7
    @Param(0 ... 2, icon: "light.max") var glow = 0.35
    /// Four rays a pixel instead of one: smooth edges on the thin rings round
    /// the shadow and steady stars where the hole shrinks them, at four times
    /// the work. Worth turning on for a still or an export.
    @Param(icon: "square.grid.2x2") var antialiasing = false

    /// Where the camera is round the hole, in degrees. The beacon sits behind
    /// the hole as seen from 0.
    private var azimuth = 0.0

    override func setup() {
        toneMap(.aces)
    }

    override func draw() {
        if mouseIsPressed {
            let moved = mouse - previousMouse
            azimuth -= moved.x * 0.25
            elevation = min(max(elevation + moved.y * 0.25, -85), 85)
        }
        distance = min(max(distance * (1 + scrollDeltaY * 0.004), 5), 120)
        azimuth += drift * deltaTime

        let radians = Double.pi / 180
        let lens = Shader(resource: "blackhole", in: .module, params: [
            Float(distance), Float(elevation * radians), Float(azimuth * radians),
            Float(fieldOfView * radians), 3, Float(diskSize),
            Float(temperature), Float(beaming), Float(exposure),
            Float(turbulence), Float(time * spin), Float(starlight),
            sky == .grid ? 1 : 0, beacon ? 4 : 0,
            // Straight behind the hole from the camera's starting place.
            Float.pi, Float(-7 * radians),
            antialiasing ? 4 : 1,
        ])
        let frame = generate(lens)
        drawImage(frame.filtered(.bloom(threshold: 0.9, amount: glow, radius: 28)).image, 0, 0)
    }
}
