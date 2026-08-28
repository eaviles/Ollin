import Foundation
import simd

/// A sea state: how hard the wind has been blowing, for how far, and in which
/// direction. It describes waves the way an oceanographer does, as how much
/// water stands at each wavelength and heading rather than as a list of waves,
/// which is what lets one inverse Fourier transform turn the whole description
/// into a moving surface in a single step.
///
/// ```swift
/// override func draw() {
///     background(Color(hex: 0x9FC4DE))
///     camera(.perspective(eye: Vector3(0, 18, 90), target: Vector3(0, 0, -40)))
///     light(.directional(Vector3(-0.4, -0.7, -0.5)))
///     let sea = oceanField(.breeze)          // the GPU transform runs here
///     drawOcean(sea, segments: 220, tiles: 3)
/// }
/// ```
///
/// `waveHeight` is the one knob in world units, and it means what a sailor
/// means: the significant wave height, the average of the tallest third, which
/// is four times the surface's standard deviation. The rest shape the sea
/// rather than size it. Everything is deterministic from `seed`, so the same
/// sketch draws the same ocean on every run.
public struct Ocean: Hashable, Sendable {

    /// The significant wave height in world units: the average height of the
    /// tallest third of the waves, four times the surface's standard deviation.
    /// The spectrum's own shape decides which wavelengths carry that height.
    public var waveHeight: Double

    /// Wind speed in world units per second. It sets *which* waves the sea
    /// carries rather than how tall they stand: the longest wave a wind can
    /// raise grows with the square of its speed, so a higher number moves the
    /// energy into longer, slower swell and a lower one into short chop.
    public var windSpeed: Double

    /// The heading the wind blows toward, in degrees, measured in the patch's
    /// own ground plane from the x axis toward z.
    public var windDirection: Double

    /// How sharply the waves point. At 0 the surface is the plain sum of its
    /// waves, which is round and soft. Raising it moves water sideways toward
    /// the crests, which is what makes them narrow and the troughs wide, the
    /// way a real sea looks. Past about 1.5 the crests start to fold through
    /// themselves, which shows up as foam rather than as shape.
    public var choppiness: Double

    /// The width of one period of the sea in world units. The field repeats on
    /// this distance, so it is also the scale everything else is read against:
    /// a 200 unit patch holding a 2 unit wave reads as open water, and a 20 unit
    /// patch holding the same wave reads as a pond.
    public var patchSize: Double

    /// Ripples shorter than this (world units) are damped out of the spectrum.
    /// A field can only carry detail down to two of its own texels, so asking
    /// for shorter waves than the resolution can draw buys aliasing rather than
    /// detail.
    public var smallestWave: Double

    /// How tightly the waves line up with the wind. 2 is the published value
    /// and gives a broad fan; higher numbers narrow it toward a single heading.
    public var spread: Double

    /// How many seconds the sea takes to repeat exactly, or 0 for a sea that
    /// never repeats. Rounding every wave's frequency down to a multiple of one
    /// step makes the whole surface periodic, which is what lets an export loop
    /// cleanly. It coarsens the motion slightly, so keep it long (10 seconds and
    /// up) unless a short loop is the point.
    public var loopSeconds: Double

    /// The seed behind the sea's randomness. Two oceans with the same seed and
    /// the same knobs are the same water, frame for frame.
    public var seed: Int

    public init(waveHeight: Double = 1.6,
                windSpeed: Double = 11,
                windDirection: Double = 30,
                choppiness: Double = 1.1,
                patchSize: Double = 220,
                smallestWave: Double = 0.5,
                spread: Double = 2,
                loopSeconds: Double = 0,
                seed: Int = 1) {
        self.waveHeight = max(0, waveHeight)
        self.windSpeed = max(0.1, windSpeed)
        self.windDirection = windDirection
        self.choppiness = max(0, choppiness)
        self.patchSize = max(1, patchSize)
        self.smallestWave = max(0.001, smallestWave)
        self.spread = max(0.1, spread)
        self.loopSeconds = max(0, loopSeconds)
        self.seed = seed
    }

    /// Barely stirred water: a long, low swell with almost no chop.
    public static let calm = Ocean(waveHeight: 0.35, windSpeed: 6, choppiness: 0.5,
                                   patchSize: 180, smallestWave: 0.4)

    /// The default: a working breeze on open water.
    public static let breeze = Ocean()

    /// Long ocean swell, tall and slow, from a wind that has blown a long way.
    public static let swell = Ocean(waveHeight: 3.2, windSpeed: 18, choppiness: 1.0,
                                    patchSize: 400, smallestWave: 0.8)

    /// A gale: steep, crowded, foaming crests.
    public static let storm = Ocean(waveHeight: 6.5, windSpeed: 26, choppiness: 1.5,
                                    patchSize: 300, smallestWave: 0.35)

    // MARK: - The spectrum

    /// The Phillips spectrum at one wave vector, before any amplitude: how much
    /// of this sea stands at this wavelength and heading. Written from the
    /// published form (an equilibrium wind sea), and matched line for line by
    /// the shader that builds the same value on the GPU, which is what makes
    /// `amplitude(resolution:)` predict the surface the GPU actually draws.
    func spectrumShape(_ n: Int, _ m: Int) -> Double {
        let kx = 2 * Double.pi * Double(n) / patchSize
        let kz = 2 * Double.pi * Double(m) / patchSize
        let kk = kx * kx + kz * kz
        if kk < 1e-12 { return 0 }
        let kLen = kk.squareRoot()
        let largest = windSpeed * windSpeed / 9.81
        var p = exp(-1 / (kk * largest * largest)) / (kk * kk)
        let heading = windDirection * Double.pi / 180
        let along = (kx * cos(heading) + kz * sin(heading)) / kLen
        p *= pow(abs(along), spread)
        if along < 0 { p *= 0.07 }
        p *= exp(-kk * smallestWave * smallestWave)
        return p
    }

    /// The factor the spectrum is scaled by so the drawn surface stands exactly
    /// `waveHeight` tall.
    ///
    /// The height at a point is the sum of every wave in the field, so its
    /// variance is the sum of the spectrum over the whole grid (twice it, since
    /// each wave arrives as a conjugate pair). That sum is a closed form of the
    /// knobs above, so the scale can be worked out on the CPU rather than
    /// measured back off the GPU, and `waveHeight` becomes a number in world
    /// units instead of a dial to be turned by eye.
    func amplitude(resolution: Int) -> Double {
        let n = max(2, resolution)
        var total = 0.0
        for y in 0 ..< n {
            let m = y < n / 2 ? y : y - n
            for x in 0 ..< n {
                let k = x < n / 2 ? x : x - n
                total += spectrumShape(k, m)
            }
        }
        guard total > 0 else { return 0 }
        let sigma = waveHeight / 4
        return (sigma * sigma / (2 * total)).squareRoot()
    }

    /// The grid the transform can actually climb: a power of two, and the nearest
    /// one to what was asked for, held between 32 and 1024. The radix-2 butterfly
    /// halves the length at every rung, so anything else has no ladder.
    public static func roundedResolution(_ asked: Int) -> Int {
        let clamped = min(1024, max(32, asked))
        var n = 32
        while n < clamped { n *= 2 }
        // Nearest, not next: 200 is closer to 256 than to 128, and 140 the other way.
        if n > 32, Double(clamped) < Double(n) * 0.75 { n /= 2 }
        return n
    }

    /// The spectrum pass's parameters at one instant.
    func spectrumParams(resolution: Int, time: Double, amplitude: Double) -> [SIMD4<Float>] {
        let loopStep = loopSeconds > 0 ? 2 * Double.pi / loopSeconds : 0
        return [
            SIMD4(Float(resolution), Float(patchSize), Float(windSpeed),
                  Float(windDirection * Double.pi / 180)),
            SIMD4(Float(amplitude), Float(smallestWave), Float(spread),
                  Float(Double(seed % 4096))),
            SIMD4(Float(time), Float(loopStep), 0, 0)
        ]
    }

    /// The resolve pass's parameters: the sideways shift is applied here, so the
    /// field a sketch reads is already in world units.
    func resolveParams(resolution: Int) -> [SIMD4<Float>] {
        [SIMD4(Float(resolution), Float(patchSize), Float(choppiness), 0)]
    }
}

/// One frame of a sea, as the renderer needs it: the state, the instant, the
/// grid, and the amplitude the CPU worked out from the state so the surface
/// stands the height that was asked for.
struct OceanRequest {
    var ocean: Ocean
    var time: Double
    var amplitude: Double
    var resolution: Int
}

/// What the amplitude of a sea state depends on, and nothing more, so a sketch
/// turning a knob every frame works the sum out once per value it lands on.
struct OceanAmplitudeKey: Hashable {
    var ocean: Ocean
    var resolution: Int
}

/// One `drawOcean` call: which field to read, how finely to cut the grid, how
/// many periods of the field to cover, and how the water looks.
struct OceanDraw {
    var field: OceanField
    var water: WaterSurface
    var segments: Int
    var tiles: Int
}

/// How the water looks, separate from how it moves. An `Ocean` decides the
/// shape of the surface; a `WaterSurface` decides what that surface does with light:
/// the color of the body under it, what it reflects, how the sun glitters off
/// it, and how white a folding crest goes.
///
/// With an environment set (`environment(.sky(...))`) the surface reflects that
/// environment and `sky` is unused. Without one, `sky` is what it reflects.
public struct WaterSurface: Hashable, Sendable {

    /// The water where it is deep and flat.
    public var deep: Color

    /// The water where a crest stands up and light gets through the thin part
    /// of it. Blended in by wave height, so it reads as the crests lighting up.
    public var shallow: Color

    /// What a flat surface reflects when no environment is set.
    public var sky: Color

    /// The color of a folding crest.
    public var foam: Color

    /// How much of a fold turns white. 0 is a sea with no foam at all.
    public var foamAmount: Double

    /// How much light the surface returns when looked at straight down. Real
    /// water is 0.02, and raising it makes the whole surface more mirror-like
    /// at every angle.
    public var reflectance: Double

    /// How tight the sun's glitter is. Higher is a smaller, harder highlight.
    public var glitterTightness: Double

    /// How bright the sun's glitter is.
    public var glitter: Double

    public init(deep: Color = Color(hex: 0x0A2A3E),
                shallow: Color = Color(hex: 0x2E7E8C),
                sky: Color = Color(hex: 0x9FC4DE),
                foam: Color = Color(hex: 0xF2F6F7),
                foamAmount: Double = 1,
                reflectance: Double = 0.02,
                glitterTightness: Double = 900,
                glitter: Double = 26) {
        self.deep = deep
        self.shallow = shallow
        self.sky = sky
        self.foam = foam
        self.foamAmount = max(0, foamAmount)
        self.reflectance = min(1, max(0, reflectance))
        self.glitterTightness = max(1, glitterTightness)
        self.glitter = max(0, glitter)
    }

    /// The default: open sea under a daylight sky.
    public static let open = WaterSurface()

    /// Shallow tropical water: a bright green body under a pale sky.
    public static let tropical = WaterSurface(deep: Color(hex: 0x06514F), shallow: Color(hex: 0x37B7A4),
                                       sky: Color(hex: 0xC7E4EF))

    /// Late light: a warm, low sun over darker water.
    public static let dusk = WaterSurface(deep: Color(hex: 0x101B33), shallow: Color(hex: 0x3B4C77),
                                   sky: Color(hex: 0xE0A16A), foam: Color(hex: 0xEBD5C4),
                                   glitter: 3.4)

    /// Black water with white crests, for a drawing rather than a photograph.
    public static let ink = WaterSurface(deep: Color(hex: 0x07080B), shallow: Color(hex: 0x1D2330),
                                  sky: Color(hex: 0x3A4351), foam: .white,
                                  foamAmount: 1.6, glitter: 0.6)
}

/// One frame of a moving sea: the layer the transform wrote, plus the sea state
/// that made it. Build it in `draw()` with `oceanField(_:)` and hand it to
/// `drawOcean(_:)`.
///
/// The layer holds the surface in world units, one texel per grid point: red
/// and blue are how far that point has moved sideways, green is its height, and
/// alpha is how hard the surface is folding there (where foam belongs). It is
/// an ordinary layer, so `drawImage(sea.image, 0, 0)` shows the raw field and
/// `sea.layer.filtered(...)` runs the effect catalog over it.
public struct OceanField {

    /// The sea state this field was built from.
    public let ocean: Ocean

    /// How many texels the field carries along each side.
    public let resolution: Int

    /// The field itself, as a layer.
    public let layer: RenderTarget

    /// The field as a drawable image (red and blue sideways, green up, alpha
    /// the fold). It is signed data in world units rather than a picture, so
    /// most of it draws as black until it is mapped through a filter.
    public var image: Image { layer.image }

    init(ocean: Ocean, resolution: Int, layer: RenderTarget) {
        self.ocean = ocean
        self.resolution = resolution
        self.layer = layer
    }
}
