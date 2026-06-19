import Foundation
import COllinShaders

/// The *finish* of a 3D mesh surface: how it responds to light, separate from its
/// color. The surface *color* stays the current `fill`; a `Material` sets everything
/// else — the shading model and the layered finishes — and you drop it in with
/// `material(_:)`:
///
/// ```swift
/// fill(.red)
/// material(.clay)        // matte, earthy
/// drawSphere(radius: 200)
///
/// material(.soapBubble)  // a rainbow that shifts as it turns
/// drawSphere(radius: 200)
/// ```
///
/// A material composes a **shading model** with a set of **finishes**:
///
/// - **shading** — how the diffuse term is shaded: `.standard` (smooth Lambert),
///   `.toon` (hard cel bands), or `.gooch` (warm→cool, the technical-illustration look).
/// - **specular** / **shininess** — the Blinn-Phong highlight.
/// - **rim** — a Fresnel edge glow (velvet, backlit fuzz, a ghostly halo).
/// - **subsurface** — fake light bleeding through thin geometry (jade, wax, skin).
/// - **iridescence** — a Fresnel-driven rainbow sheen that shifts with view angle
///   (soap film, oil slick, beetle shell).
///
/// Each finish is inert at its zero value, so they layer freely — a `.toon` material
/// can still carry a rim, an iridescent one a touch of subsurface. Like
/// `LightingPreset`, it's a plain value, so the built-in set is also the extension
/// surface — construct your own or copy and tweak a built-in:
///
/// ```swift
/// var m = Material.glossy
/// m.iridescence = 0.5         // a faint pearlescent sheen over the gloss
/// material(m)
/// ```
///
/// There's no registry; a material is just a value you pass in. It shades through the
/// directional/point/spot light model, so it needs lights set (the auto-lit default
/// rig counts), and a fully unlit surface (`noLights()`) shows none of the finishes.
///
/// The built-ins cover the **dielectric** finishes the model represents faithfully
/// (matte through polished) plus the stylized families above. True *metal* (a
/// highlight tinted by the surface, environment reflections) and *glass* (refraction,
/// real transparency) are the physically-based / environment-lighting tier;
/// `.polished` is the closest this model reaches.
public struct Material: Equatable, Sendable {

    /// How the diffuse term is shaded.
    public enum Shading: Int, Equatable, Sendable {
        /// Smooth Lambert shading (the default, photographic).
        case standard = 0
        /// Hard cel bands — the cartoon / anime look. The number of steps is `toonBands`.
        case toon = 1
        /// Warm→cool tonal shading (`goochWarm` on the lit side, `goochCool` in shadow):
        /// the non-photorealistic technical-illustration look.
        case gooch = 2
    }

    /// The diffuse shading model (`.standard` / `.toon` / `.gooch`).
    public var shading: Shading
    /// Toon shading: the number of cel bands (more = smoother steps). Ignored unless
    /// `shading == .toon`.
    public var toonBands: Double

    /// Specular highlight strength: `0` matte, `~0.5` glossy, `1` a bright hotspot.
    public var specular: Double
    /// Blinn-Phong shininess exponent: higher is a tighter, sharper highlight.
    public var shininess: Double

    /// Iridescence strength, `0…1`: a view-angle rainbow sheen on top of the shading.
    public var iridescence: Double
    /// Iridescence band scale: how many hue cycles the sheen runs through from head-on
    /// to grazing (low = a few broad bands, high = many fine ones).
    public var iridescenceScale: Double

    /// Rim (Fresnel edge) strength, `0…1`: how strongly `rimColor` glows at grazing
    /// angles. `0` is off.
    public var rim: Double
    /// Rim falloff exponent: higher pulls the glow into a thinner edge.
    public var rimPower: Double
    /// The rim glow color.
    public var rimColor: Color

    /// Subsurface (fake translucency) strength, `0…1`: how much light appears to bleed
    /// through thin geometry, glowing in `subsurfaceColor`. `0` is off.
    public var subsurface: Double
    /// The color of the subsurface glow (a jade green, a warm wax, a fleshy tone).
    public var subsurfaceColor: Color

    /// Gooch shading: the warm tone on the lit side. Ignored unless `shading == .gooch`.
    public var goochWarm: Color
    /// Gooch shading: the cool tone on the shadow side. Ignored unless `shading == .gooch`.
    public var goochCool: Color

    /// Build a material. Every parameter defaults to an inert value, so
    /// `Material(specular: 0.5)` is a plain glossy surface and the finishes only appear
    /// when you set them.
    public init(shading: Shading = .standard, toonBands: Double = 4,
                specular: Double = 0, shininess: Double = 32,
                iridescence: Double = 0, iridescenceScale: Double = 1,
                rim: Double = 0, rimPower: Double = 2, rimColor: Color = .white,
                subsurface: Double = 0, subsurfaceColor: Color = .white,
                goochWarm: Color = Color(red: 0.7, green: 0.5, blue: 0.15),
                goochCool: Color = Color(red: 0.05, green: 0.1, blue: 0.35)) {
        self.shading = shading
        self.toonBands = max(1, toonBands)
        self.specular = max(0, specular)
        self.shininess = max(1, shininess)
        self.iridescence = min(1, max(0, iridescence))
        self.iridescenceScale = max(0, iridescenceScale)
        self.rim = min(1, max(0, rim))
        self.rimPower = max(0.1, rimPower)
        self.rimColor = rimColor
        self.subsurface = min(1, max(0, subsurface))
        self.subsurfaceColor = subsurfaceColor
        self.goochWarm = goochWarm
        self.goochCool = goochCool
    }

    /// A copy with the iridescence strength scaled by `factor` (everything else left
    /// alone): dial a sheen up or down without rebuilding the material.
    public func iridescent(by factor: Double) -> Material {
        var m = self
        m.iridescence = min(1, max(0, iridescence * factor))
        return m
    }

    /// The GPU-side packed form (colors linearized), bound per mesh batch.
    func gpuMaterial() -> OllinMaterial {
        var m = OllinMaterial()
        m.rimColor = Material.linear(rimColor, alpha: rim)
        m.subsurfaceColor = Material.linear(subsurfaceColor, alpha: subsurface)
        m.goochWarm = Material.linear(goochWarm, alpha: 0)
        m.goochCool = Material.linear(goochCool, alpha: 0)
        m.specular = Float(specular)
        m.shininess = Float(shininess)
        m.iridescence = Float(iridescence)
        m.iridescenceScale = Float(iridescenceScale)
        m.rimPower = Float(rimPower)
        m.toonBands = Float(toonBands)
        m.shadingModel = Int32(shading.rawValue)
        return m
    }

    private static func linear(_ c: Color, alpha: Double) -> SIMD4<Float> {
        SIMD4<Float>(Float(Color.srgbToLinear(c.red)),
                     Float(Color.srgbToLinear(c.green)),
                     Float(Color.srgbToLinear(c.blue)),
                     Float(alpha))
    }
}

// MARK: - The curated library

public extension Material {

    /// Flat and chalky: no specular highlight, so the surface reads purely by its
    /// diffuse shading. The plainest finish.
    static let matte = Material(specular: 0, shininess: 8)

    /// Unfired-clay earthenware: a barely-there broad sheen over a matte surface.
    static let clay = Material(specular: 0.05, shininess: 6)

    /// Soft rubber or matte vinyl: a wide, dim highlight — more present than clay.
    static let rubber = Material(specular: 0.12, shininess: 16)

    /// Molded plastic: a clear, medium highlight. The everyday "shiny but not a
    /// mirror" finish.
    static let plastic = Material(specular: 0.5, shininess: 48)

    /// Glazed ceramic / porcelain: a bright, fairly tight highlight over a smooth
    /// surface.
    static let ceramic = Material(specular: 0.75, shininess: 96)

    /// High-gloss lacquer: a strong, sharp highlight — wet-looking and reflective
    /// without being a mirror.
    static let glossy = Material(specular: 0.9, shininess: 160)

    /// Polished, near-mirror finish: the brightest, tightest hotspot this model
    /// reaches — the closest approximation to metal or chrome short of the
    /// physically-based / environment-lighting tier.
    static let polished = Material(specular: 1.0, shininess: 256)

    // Iridescent family — a Fresnel rainbow sheen over a glossy base.

    /// A general pearlescent finish: a broad rainbow sheen riding a glossy rim.
    static let iridescent = Material(specular: 0.6, shininess: 80,
                                     iridescence: 0.85, iridescenceScale: 1.0)

    /// Soap-bubble film: bright, tightly-banded iridescence over a very glossy
    /// surface. Pair with a translucent `fill` for the see-through bubble look.
    static let soapBubble = Material(specular: 0.85, shininess: 140,
                                     iridescence: 1.0, iridescenceScale: 1.6)

    /// Oil slick on water: many fine rainbow bands over a darker, less glossy base.
    static let oilSlick = Material(specular: 0.45, shininess: 60,
                                   iridescence: 0.95, iridescenceScale: 2.6)

    /// Beetle shell / butterfly wing: a few broad iridescent bands over a satin
    /// surface — a deep structural shimmer rather than a busy rainbow.
    static let beetle = Material(specular: 0.7, shininess: 100,
                                 iridescence: 0.75, iridescenceScale: 0.7)

    // Rim / Fresnel glow.

    /// Velvet / backlit fuzz: a soft Fresnel glow rimming the silhouette over a
    /// near-matte body, the way light catches the edge of fabric or moss.
    static let velvet = Material(specular: 0.08, shininess: 20,
                                 rim: 0.8, rimPower: 2.2)

    // Subsurface scattering.

    /// Jade / polished stone: light glowing through the thin edges in a cool green,
    /// over a glossy body.
    static let jade = Material(specular: 0.55, shininess: 70,
                               subsurface: 0.9,
                               subsurfaceColor: Color(red: 0.35, green: 0.85, blue: 0.55))

    /// Wax / candle: a soft warm glow bleeding through the surface, low gloss.
    static let wax = Material(specular: 0.2, shininess: 24,
                              subsurface: 0.85,
                              subsurfaceColor: Color(red: 1.0, green: 0.75, blue: 0.45))

    // Non-photorealistic shading models.

    /// Toon / cel shading: the diffuse term steps through hard bands, the cartoon
    /// look, with a small crisp highlight.
    static let toon = Material(shading: .toon, toonBands: 4,
                               specular: 0.4, shininess: 64)

    /// Gooch warm–cool shading: the technical-illustration / blueprint aesthetic,
    /// warm where lit and cool in shadow, with a faint highlight.
    static let gooch = Material(shading: .gooch, specular: 0.25, shininess: 48)
}
