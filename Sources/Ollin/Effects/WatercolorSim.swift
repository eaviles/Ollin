import Foundation

/// One paint in a `Sim.watercolor` field's palette: its optical character (how a
/// layer of it absorbs and scatters each of red, green, and blue light, the
/// Kubelka-Munk coefficients) plus the three physical habits that make watercolor
/// pigments behave differently from one another while they are wet:
///
/// - `density`: how readily the pigment settles onto the paper. Dense pigments
///   drop out of the water quickly and stay close to where they were laid down;
///   light ones ride the flow further before settling.
/// - `staining`: how hard it grips once settled. A staining pigment resists being
///   lifted back into moving water; a non-staining one re-dissolves and keeps
///   traveling.
/// - `granulation`: how much the paper's texture biases settling. A granulating
///   pigment collects in the hollows of the paper and leaves the grainy, speckled
///   wash watercolorists prize (or fight); a smooth pigment ignores the tooth.
///
/// You rarely need to build one by hand: the presets below are real paints with
/// measured coefficients, and `init(overWhite:overBlack:...)` derives coefficients
/// from the two colors you'd observe painting a layer over white and over black
/// paper, the practical way to invent a pigment (a transparent paint shows its
/// color over white and goes nearly black over black; an opaque one looks the
/// same on both).
public struct WatercolorPigment: Sendable, Equatable {

    /// Absorption per unit layer thickness (the Kubelka-Munk K), one coefficient
    /// per RGB channel. Internal: specified through the initializers.
    var k: SIMD3<Double>

    /// Scattering per unit layer thickness (the Kubelka-Munk S), per RGB channel.
    var s: SIMD3<Double>

    /// How readily the pigment settles onto the paper (0...1-ish; the presets sit
    /// between 0.01 and 0.09). Higher settles faster and travels less.
    public var density: Double

    /// Staining power: how strongly settled pigment resists being lifted back into
    /// the water (1 = lifts as readily as it settles; the presets run up to ~9).
    public var staining: Double

    /// How much the paper's height field biases settling toward the hollows
    /// (0 = indifferent to the tooth, 1 = strongly granulating).
    public var granulation: Double

    /// Build a pigment from raw Kubelka-Munk coefficients (absorption `k` and
    /// scattering `s`, each an RGB triple). The escape hatch for measured data;
    /// prefer `init(overWhite:overBlack:...)` for inventing paints by eye.
    public init(k: (Double, Double, Double), s: (Double, Double, Double),
                density: Double = 0.05, staining: Double = 1, granulation: Double = 0.3) {
        self.k = SIMD3(max(0, k.0), max(0, k.1), max(0, k.2))
        self.s = SIMD3(max(1e-4, s.0), max(1e-4, s.1), max(1e-4, s.2))
        self.density = max(0, density)
        self.staining = max(1e-3, staining)
        self.granulation = min(1, max(0, granulation))
    }

    /// Derive a pigment's coefficients from the color a unit layer of it shows
    /// painted **over white** and **over black**, the two swatches that pin down
    /// how it both filters and reflects light. A transparent paint keeps its hue
    /// over white and goes nearly black over black; an opaque one looks alike on
    /// both; a chalky "interference" paint can even be brighter over black.
    /// Channels are clamped so black stays strictly darker than white (the
    /// inversion needs `0 < overBlack < overWhite < 1` per channel).
    public init(overWhite: Color, overBlack: Color,
                density: Double = 0.05, staining: Double = 1, granulation: Double = 0.3) {
        let rw = SIMD3(overWhite.red, overWhite.green, overWhite.blue)
        let rb = SIMD3(overBlack.red, overBlack.green, overBlack.blue)
        var k = SIMD3<Double>(), s = SIMD3<Double>()
        for c in 0..<3 {
            let (kk, ss) = KubelkaMunk.coefficients(overWhite: rw[c], overBlack: rb[c])
            k[c] = kk; s[c] = ss
        }
        self.init(k: (k.x, k.y, k.z), s: (s.x, s.y, s.z),
                  density: density, staining: staining, granulation: granulation)
    }

    // MARK: Measured paints
    //
    // A palette of real watercolor paints with published measured coefficients
    // (credited in ATTRIBUTION.md). Density/staining/granulation are each paint's
    // measured habits: burnt umber granulates hard and stains, hansa yellow is a
    // light, smooth wash pigment.

    /// A cool transparent rose: vivid over white, nearly black over black.
    public static let quinacridoneRose = WatercolorPigment(
        k: (0.22, 1.47, 0.57), s: (0.05, 0.003, 0.03),
        density: 0.02, staining: 5.5, granulation: 0.81)
    /// An opaque earth red: looks much the same over white and black.
    public static let indianRed = WatercolorPigment(
        k: (0.46, 1.07, 1.50), s: (1.28, 0.38, 0.21),
        density: 0.05, staining: 7.0, granulation: 0.40)
    /// A dense, fairly opaque warm yellow.
    public static let cadmiumYellow = WatercolorPigment(
        k: (0.10, 0.36, 3.45), s: (0.97, 0.65, 0.007),
        density: 0.05, staining: 3.4, granulation: 0.81)
    /// A deep transparent leaf green.
    public static let hookersGreen = WatercolorPigment(
        k: (1.62, 0.61, 1.64), s: (0.01, 0.012, 0.003),
        density: 0.09, staining: 1.0, granulation: 0.31)
    /// A granulating sky blue with real body.
    public static let ceruleanBlue = WatercolorPigment(
        k: (1.52, 0.32, 0.25), s: (0.06, 0.26, 0.40),
        density: 0.01, staining: 1.0, granulation: 0.31)
    /// A heavy, strongly granulating, staining brown earth.
    public static let burntUmber = WatercolorPigment(
        k: (0.74, 1.54, 2.10), s: (0.09, 0.09, 0.004),
        density: 0.09, staining: 9.3, granulation: 0.90)
    /// A warm semi-opaque red.
    public static let cadmiumRed = WatercolorPigment(
        k: (0.14, 1.08, 1.68), s: (0.77, 0.015, 0.018),
        density: 0.02, staining: 1.0, granulation: 0.63)
    /// A very transparent glowing orange.
    public static let brilliantOrange = WatercolorPigment(
        k: (0.13, 0.81, 3.45), s: (0.005, 0.009, 0.007),
        density: 0.01, staining: 1.0, granulation: 0.14)
    /// A light, smooth, semi-opaque yellow, the classic glazing yellow.
    public static let hansaYellow = WatercolorPigment(
        k: (0.06, 0.21, 1.78), s: (0.50, 0.88, 0.009),
        density: 0.06, staining: 1.0, granulation: 0.08)
    /// An intense transparent blue-green.
    public static let phthaloGreen = WatercolorPigment(
        k: (1.55, 0.47, 0.63), s: (0.01, 0.05, 0.035),
        density: 0.02, staining: 1.0, granulation: 0.12)
    /// The classic granulating warm blue.
    public static let frenchUltramarine = WatercolorPigment(
        k: (0.86, 0.86, 0.06), s: (0.005, 0.005, 0.09),
        density: 0.01, staining: 3.1, granulation: 0.91)
    /// An interference paint: white-ish over white, colored over black.
    public static let interferenceLilac = WatercolorPigment(
        k: (0.08, 0.11, 0.07), s: (1.25, 0.42, 1.43),
        density: 0.06, staining: 1.0, granulation: 0.08)
}

/// The Kubelka-Munk layer optics behind `Sim.watercolor`'s rendering, on the CPU:
/// the same equations the render pass evaluates per pixel, kept here so pigment
/// derivation (`WatercolorPigment(overWhite:overBlack:)`) and the tests share one
/// reference implementation. All single-channel; callers loop RGB.
///
/// Reflectance channels live in **display (sRGB-encoded) space** by convention:
/// the colors a user hands `overWhite:`/`overBlack:` are the colors they see, and
/// the render pass converts its result to linear light only at output. Running
/// the layer math in display space is what keeps the derived pigment's swatch
/// matching the color the user picked.
enum KubelkaMunk {

    /// Reflectance and transmittance of a pigment layer of thickness `x` with
    /// absorption `k` and scattering `s` (one channel). A zero-thickness layer is
    /// the identity (R 0, T 1); an infinitely thick one tends to R = a - b.
    static func layer(k: Double, s: Double, x: Double) -> (r: Double, t: Double) {
        guard x > 0 else { return (0, 1) }
        let ss = max(s, 1e-6)
        let a = 1 + k / ss
        let b = max(a * a - 1, 0).squareRoot()
        // The b -> 0 limit (a pure scatterer, k = 0): R = Sx/(1+Sx), T = 1/(1+Sx).
        guard b > 1e-6 else {
            let sx = ss * x
            return (sx / (1 + sx), 1 / (1 + sx))
        }
        let bsx = min(b * ss * x, 30)          // sinh overflows past ~700; 30 is already opaque
        let sh = sinh(bsx), ch = cosh(bsx)
        let c = a * sh + b * ch
        return (sh / c, b / c)
    }

    /// Optically composite an upper layer (`r1`, `t1`) over a lower one (`r2`,
    /// `t2`): light bounces between them, and the closed form sums the series.
    static func composite(r1: Double, t1: Double, r2: Double, t2: Double) -> (r: Double, t: Double) {
        let inter = 1 - r1 * r2
        guard inter > 1e-6 else { return (r1, 0) }
        return (r1 + t1 * t1 * r2 / inter, t1 * t2 / inter)
    }

    /// Invert the layer equations: from the reflectance a unit layer shows over
    /// white (`overWhite`) and over black (`overBlack`), recover that channel's
    /// absorption and scattering. Inputs are clamped to the region where the
    /// inversion is defined (`0 < overBlack < overWhite < 1`).
    static func coefficients(overWhite: Double, overBlack: Double) -> (k: Double, s: Double) {
        let rw = min(max(overWhite, 0.02), 0.99)
        let rb = min(max(overBlack, 0.005), rw - 0.005)
        let a = 0.5 * (rw + (rb - rw + 1) / rb)
        let b = max(a * a - 1, 1e-12).squareRoot()
        // acoth(y) = atanh(1/y); the argument is > 1 in the clamped region.
        let y = (b * b - (a - rw) * (a - 1)) / (b * (1 - rw))
        let s = (1 / b) * atanh(min(max(1 / y, -0.999999), 0.999999))
        let sSafe = max(s, 1e-4)
        return (max(sSafe * (a - 1), 0), sSafe)
    }
}

extension Sim {

    /// The fixed configuration a `.watercolor` hands the renderer's dedicated
    /// multi-pass solver (`runWatercolor`). Like the fluid, watercolor bypasses
    /// the single-texture step hooks and keeps several persistent fields, so its
    /// parameters travel here rather than in `params`.
    struct WatercolorConfig: Sendable {
        var pigments: [WatercolorPigment]   // 1...3, one per seed color channel
        var edgeDarkening: Float            // η: how much water the wet edge sheds per step
        var edgeWidth: Float                // the blur width (texels) that defines "near the edge"
        var viscosity: Float                // μ in the shallow-water equations
        var drag: Float                     // κ: the flow's friction against the paper
        var relaxation: Int                 // divergence-relaxation iterations per step
        var backruns: Bool                  // run the capillary layer (wet fronts creep into damp paper)
        var dryBrush: Float                 // 0 = off; else only paper above this height gets wet
        var absorbency: Float               // α: saturation the paper soaks up per step where wet
        var grain: Float                    // paper feature scale, in field texels
        var paperSeed: Float                // picks the paper's texture
        var paperColor: SIMD3<Float>        // the sheet's own reflectance (display-space RGB)
        var speed: Int                      // main simulation steps per frame
    }

    /// The watercolor configuration, when this is a `.watercolor` (else `nil`).
    /// Read by the renderer's dedicated pipeline, and by `WatercolorField` for its
    /// palette sugar.
    var watercolorConfig: WatercolorConfig? {
        if case let .watercolor(c) = kind { return c }
        return nil
    }

    /// **Watercolor**: wet paint on rough paper, simulated. The field is a sheet
    /// of textured paper; drawing into it lays down water and pigment, and each
    /// frame the wash *behaves*: water flows inside the wetted area (steered by
    /// the paper's tooth), carries pigment with it, sheds water at the wet edge so
    /// pigment migrates outward and dries as a dark rim (the signature watercolor
    /// edge), and settles pigment onto the paper at each paint's own pace.
    /// Dense pigments drop early, granulating ones collect in the paper's
    /// hollows, staining ones refuse to lift back up. With `backruns` on, water
    /// also creeps through the paper's pores, so a wet puddle expands back into a
    /// drying wash as a branching, dark-edged bloom.
    ///
    /// Painting is drawing into the field (`withField`), with the field's palette
    /// mapped onto the mark's color channels: red is the first pigment, green the
    /// second, blue the third, and **alpha is water**. `WatercolorField.ink(_:)` and
    /// `.water(_:)` build those colors for you; any drawing call works as a brush.
    /// The `image` is the finished painting: pigment layers composited optically
    /// (Kubelka-Munk), so thin washes glow, glazes mix like light through stained
    /// glass, and pigment character survives, over the paper color.
    ///
    /// A wash stays *wet* (it keeps flowing) until you either stop it or bake it:
    /// `WatercolorField.dry()` fixes the current wash into a dried glaze layer and
    /// starts the next wash on top. Successive dried glazes composite optically,
    /// which is the classic luminous-glazing technique.
    ///
    /// ```swift
    /// var paint: WatercolorField!
    /// override func setup() { paint = watercolor(pigments: [.frenchUltramarine, .burntUmber]) }
    ///
    /// override func draw() {
    ///     withField(paint) {
    ///         if mouseIsPressed { fill(paint.ink(0)); drawCircle(mouseX, mouseY, 24) }
    ///     }
    ///     drawImage(paint.image, 0, 0)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - pigments: The palette, up to three, one per seed color channel.
    ///   - edgeDarkening: How much water the wet edge sheds each step (the
    ///     strength of the dark rim). Around 0.01...0.05; 0 turns the effect off.
    ///   - backruns: Whether water creeps through the paper's pores, letting a
    ///     puddle bloom back into a damp wash. Costs two passes per step.
    ///   - dryBrush: 0 for a normal wet brush. Above 0, paint only wets paper
    ///     whose height exceeds the threshold, so strokes skip across the tooth
    ///     and break up (the dry-brush texture). Try 0.5...0.7.
    ///   - absorbency: How fast the paper drinks (saturates) where it's wet;
    ///     feeds the backrun creep. 0...1.
    ///   - grain: The paper texture's feature scale in field texels.
    ///   - paperSeed: Picks the sheet of paper; same seed, same tooth.
    ///   - paperColor: The sheet's own color, shown wherever no pigment covers.
    ///   - speed: Main simulation steps per frame (1...4). More evolves the wash
    ///     faster, at proportional GPU cost.
    public static func watercolor(pigments: [WatercolorPigment] = [.frenchUltramarine,
                                                                   .quinacridoneRose,
                                                                   .hansaYellow],
                                  edgeDarkening: Double = 0.04,
                                  backruns: Bool = true,
                                  dryBrush: Double = 0,
                                  absorbency: Double = 0.3,
                                  grain: Double = 14,
                                  paperSeed: Double = 7,
                                  paperColor: Color = Color(red: 1, green: 0.995, blue: 0.98),
                                  speed: Int = 1) -> Sim {
        let palette = pigments.isEmpty ? [.frenchUltramarine] : Array(pigments.prefix(3))
        return Sim(kind: .watercolor(WatercolorConfig(
            pigments: palette,
            edgeDarkening: Float(min(max(edgeDarkening, 0), 0.2)),
            edgeWidth: 10,
            viscosity: 0.1,
            drag: 0.01,
            relaxation: 24,
            backruns: backruns,
            dryBrush: Float(min(max(dryBrush, 0), 1)),
            absorbency: Float(min(max(absorbency, 0), 1)),
            grain: Float(min(max(grain, 2), 128)),
            paperSeed: Float(paperSeed),
            paperColor: SIMD3(Float(paperColor.red), Float(paperColor.green), Float(paperColor.blue)),
            speed: max(1, min(4, speed)))))
    }
}

/// A `SimField` that runs `Sim.watercolor`: the painting surface, plus the small
/// palette surface painting needs. `ink(_:)`/`water(_:)` build brush colors for
/// the field's pigments, and `dry()` bakes the current wash into a dried glaze so
/// the next wash paints over it (wet-on-dry, and the luminous glazing stack).
/// Make one with `watercolor(...)` in `setup()` and hold it; see `Sim.watercolor`
/// for the model and `withField` for painting into it.
public final class WatercolorField: SimField {

    /// Set when the sketch asks for the current wash to dry; the renderer
    /// consumes it on the next frame it steps this field (bakes the wash into
    /// the dried glaze stack, then resets water, mask, and loose pigment).
    var pendingDry = false

    /// Set when the sketch asks for the standing water to lift; consumed like
    /// `pendingDry` (clears the flow, keeps the pigment, leaves the sheet damp).
    var pendingBlot = false

    /// The field's palette (the pigments its seed color channels map to).
    public var pigments: [WatercolorPigment] { sim.watercolorConfig?.pigments ?? [] }

    /// Fix the current wash: everything painted since the last `dry()` stops
    /// moving and becomes a dried glaze under the next wash. Later strokes paint
    /// *over* it wet-on-dry, re-wetting nothing, and the dried layers composite
    /// optically, so glazing thin washes over one another builds luminous color.
    /// Takes effect on the next frame the field steps.
    public func dry() { pendingDry = true }

    /// Lift the standing water without fixing anything: the wash stops flowing,
    /// but its pigment stays where it lies (suspended and settled alike) and the
    /// sheet stays damp. This is the "drying but still damp" state the classic
    /// backrun wants: blot a wash, then touch water (or a wet stroke) to it, and
    /// the flood creeps back through the damp ground (`backruns` on), pushing
    /// the parked pigment ahead of it into a branching, darkened bloom. Unlike
    /// `dry()`, nothing is baked: the next wet touch can still move this paint.
    /// Takes effect on the next frame the field steps.
    public func blot() { pendingBlot = true }

    /// A brush color loaded with one of the field's pigments: `pigment` indexes
    /// the palette (0-based), `load` is how much pigment the brush carries, and
    /// `water` how wet the stroke is. Wetter strokes spread further and carry
    /// their pigment thinner (the water is the mark's alpha, and it dilutes the
    /// load); drier ones stay put. Use it as any fill or stroke color inside a
    /// `withField` block.
    public func ink(_ pigment: Int = 0, load: Double = 0.6, water: Double = 1) -> Color {
        let l = min(max(load, 0), 1)
        var rgb = SIMD3<Double>()
        if (0..<3).contains(pigment) { rgb[pigment] = l }
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z,
                     alpha: min(max(water, 0), 1))
    }

    /// A clean-water brush color: wets and pushes the wash around without adding
    /// pigment. Drop it into a drying wash (with `backruns` on) to bloom it.
    public func water(_ amount: Double = 1) -> Color {
        Color(red: 0, green: 0, blue: 0, alpha: min(max(amount, 0), 1))
    }
}

public extension Sketch {
    /// Make a full-canvas watercolor field (see `Sim.watercolor`): wet paint on
    /// textured paper, painted by drawing into it. Persistent, like `simField(_:)`;
    /// create it once in `setup()` and store it. `scale` is the field's internal
    /// resolution as a fraction of the canvas; the default half resolution keeps
    /// the many passes cheap and reads as paper-soft rather than blurry.
    func watercolor(_ sim: Sim = .watercolor(), scale: Double = 0.5) -> WatercolorField {
        let resolved = sim.watercolorConfig != nil ? sim : .watercolor()
        return WatercolorField(sim: resolved, width: Int(width.rounded()),
                               height: Int(height.rounded()), scale: scale, drawer: drawer)
    }

    /// `watercolor(_:scale:)` with just a palette: the common case,
    /// `paint = watercolor(pigments: [.frenchUltramarine, .burntUmber])`.
    func watercolor(pigments: [WatercolorPigment], scale: Double = 0.5) -> WatercolorField {
        watercolor(.watercolor(pigments: pigments), scale: scale)
    }
}
