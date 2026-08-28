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
/// - **sparkle** — tiny mirror flakes that flash as the view, object, or light moves
///   (glitter, metallic car paint, sequins).
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
/// For an **energy-conserving, physically-based** finish (true *metal* whose reflection
/// is tinted by the surface, and dielectrics parameterized by `roughness` rather than a
/// Blinn-Phong exponent), set `shading: .physicallyBased` (or use the `.metal(roughness:)`
/// / `.dielectric(roughness:)` helpers and the `.brushedMetal` / `.polishedMetal` /
/// `.smoothPlastic` / `.roughPlastic` built-ins). It shades through the same lights;
/// reflections of the surroundings layer on once an environment is set (image-based
/// lighting).
///
/// **Glass** is the physically-based finish with `transmission` turned up (use the
/// `.glass(...)` helper or the `.frostedGlass` built-in): light passes through the
/// surface, refracting the environment, and, with `rayTracedReflections()` on a
/// ray-tracing GPU, the actual scene behind it. Transmission needs an environment set
/// (`environment(_:)`) to have something to transmit; without one the material shades
/// as a plain physically-based dielectric. The `fill` tints what shows through, `ior`
/// bends it, `thickness` makes the body solid (with `attenuationColor` /
/// `attenuationDistance` deepening the tint the farther light travels inside).
///
/// A **thin film** rides it too (`thinFilm`, with its thickness in nanometers): a
/// transparent skin on the surface whose two faces reflect the same light out of step,
/// so the colors that survive depend on the film's thickness and on the angle you look
/// from. That is where a soap bubble, anodized titanium, oil on a puddle, and the inside
/// of a shell get their color, and unlike the stylized `iridescence` sheen it is
/// computed from the interference itself (use the `.soapFilm(thickness:)` helper or the
/// `.anodized` / `.oilOnWater` / `.nacre` built-ins).
///
/// Two more layered lobes ride the physically-based finish: **clearcoat** (a thin
/// polished lacquer over the base, at its own `clearcoatRoughness`: car paint, piano
/// lacquer; use the `.carPaint(roughness:)` helper or the `.lacquer` built-in) and
/// **sheen** (soft fabric fuzz catching light at the silhouette, tinted by
/// `sheenColor`: the `.satin` / `.felt` built-ins). Both are inert at `0`.
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
        /// Energy-conserving physically-based shading: a Cook-Torrance microfacet model
        /// driven by `metallic` and `roughness`, the way modern real-time 3D gets its
        /// photographic look. The surface color stays the current `fill`; a metal tints
        /// its highlight by that color, a dielectric keeps a neutral one. The Blinn-Phong
        /// finish fields (`specular`/`shininess`) are ignored in this mode. Reflections of
        /// the surroundings layer on once an environment is set (image-based lighting).
        case physicallyBased = 3
    }

    /// The diffuse shading model (`.standard` / `.toon` / `.gooch` / `.physicallyBased`).
    public var shading: Shading
    /// Toon shading: the number of cel bands (more = smoother steps). Ignored unless
    /// `shading == .toon`.
    public var toonBands: Double

    /// Physically-based shading: how metallic the surface is, `0…1`. At `0` it's a
    /// dielectric (plastic, ceramic, stone) with a neutral highlight and a diffuse body;
    /// at `1` it's a conductor (gold, copper, steel) whose reflection is tinted by the
    /// surface color and which has no diffuse term. Ignored unless `shading ==
    /// .physicallyBased`.
    public var metallic: Double
    /// Physically-based shading: surface roughness, `0…1`. `0` is mirror-smooth (a tight,
    /// sharp reflection), `1` is fully rough (a broad, soft one). Ignored unless `shading
    /// == .physicallyBased`.
    public var roughness: Double

    /// Physically-based shading: how directional the surface's polish is, `-1…1`.
    /// `0` (the default) is an even polish whose highlight is round. Toward `1` the
    /// highlight stretches into the streak of a brushed or turned finish (brushed
    /// aluminum, satin, the base of a pan), running along the surface's `u` axis on a
    /// mesh with a normal or surface map, and around a stable world frame everywhere
    /// else, which reads as a lathe finish on a sphere or cylinder. `-1` runs the
    /// streak the other way. Needs some `roughness` to show (a mirror has no lobe to
    /// stretch). Ignored unless `shading == .physicallyBased`.
    public var anisotropy: Double
    /// Spins the brushed streak in the surface plane, in radians: `0` follows the `u`
    /// axis (or the world frame), `.pi / 2` runs it the other way.
    public var anisotropyRotation: Double

    /// Physically-based shading: how much light passes *through* the surface, `0…1`.
    /// At `0` the surface is opaque (the default); at `1` it's clear glass, the diffuse
    /// body replaced by whatever shows through, tinted by the `fill` and blurred by
    /// `roughness` (frosting). Needs an environment set to have something to transmit.
    /// Distinct from a translucent `fill` alpha: transmission refracts and tints the
    /// light behind the surface instead of fading the whole surface out.
    /// Ignored unless `shading == .physicallyBased`.
    public var transmission: Double
    /// Index of refraction for the transmitted light: how strongly the body bends what
    /// shows through (and how reflective the surface is head-on). `1` doesn't bend at
    /// all; `1.33` is water, `1.5` common glass (the default), `2.42` diamond.
    public var ior: Double
    /// How thick the transmissive body is, in world units. `0` (the default) treats the
    /// surface as thin-walled, a soap-film shell that tints without displacing what's
    /// behind it; a positive thickness treats it as a solid whose interior bends the
    /// view and absorbs light along the way (see `attenuationColor`). For a solid
    /// sphere, its diameter is the natural value.
    public var thickness: Double
    /// The color white light becomes after traveling `attenuationDistance` through a
    /// solid body (Beer-Lambert absorption): a pale green makes thick glass edges go
    /// bottle-green. White (the default) absorbs nothing. Only applies when
    /// `thickness > 0`.
    public var attenuationColor: Color
    /// The travel distance (world units) at which white light has faded to
    /// `attenuationColor`. `0` (the default) turns absorption off.
    public var attenuationDistance: Double

    /// Physically-based shading: a thin transparent lacquer layer over the base surface,
    /// `0…1` (car paint, piano lacquer, varnished wood). The coat adds its own polished
    /// highlight and reflection on top of whatever the base is doing (a rough metal
    /// under a glassy coat is the car-paint look), and the base dims slightly by what
    /// the coat reflects away. `0` (the default) is no coat.
    /// Ignored unless `shading == .physicallyBased`.
    public var clearcoat: Double
    /// The coat layer's own roughness, `0…1`, independent of the base `roughness`:
    /// `0` (the default) is a freshly-polished gloss; raise it toward a matte varnish.
    public var clearcoatRoughness: Double

    /// Physically-based shading: fabric sheen strength, `0…1`, the soft rim glow of
    /// velvet, satin, felt, or moss, where stray fibers catch light at grazing angles.
    /// The sheen brightens silhouettes in `sheenColor` and the base dims to keep the
    /// energy honest. `0` (the default) is off.
    /// Ignored unless `shading == .physicallyBased`.
    public var sheen: Double
    /// The sheen tint (white by default). A tint different from the `fill` gives the
    /// two-tone shot-fabric look: a deep red body rimmed in orange reads as velvet.
    public var sheenColor: Color
    /// The sheen lobe's roughness, `0…1`: lower pulls the glow into a tighter satin
    /// band near the silhouette, higher spreads it into a dry, felty haze.
    public var sheenRoughness: Double

    /// Physically-based shading: how much of the surface's reflection comes off a
    /// transparent **film** lying on it, `0…1` (a soap bubble's wall, the oxide on
    /// anodized metal, oil on wet asphalt, the nacre of a shell). Light bounces off
    /// both faces of the film, and the two reflections meet again out of step, so some
    /// wavelengths add and others cancel: the color is *interference*, not a tint, and
    /// it changes with the angle you look from. `0` (the default) is off.
    /// Ignored unless `shading == .physicallyBased`.
    ///
    /// Distinct from `iridescence`, the stylized rim rainbow that rides any shading
    /// model: this one is measured in nanometers and computed from the physics, so it
    /// keeps its color under a moving light and reads as a real film.
    public var thinFilm: Double
    /// How thick that film is, in **nanometers** (light's own scale, not the scene's,
    /// so the number stays the same however big the object is). Around `300` runs
    /// gold to violet, `550` sits in the magenta-green band, and past about `1000` the
    /// bands crowd together and wash toward silver. `0` turns the film off whatever
    /// `thinFilm` says. A soap wall is roughly `300…800`.
    public var thinFilmThickness: Double
    /// The film's index of refraction: `1.3` (the default) is the soap or oxide film
    /// on most real surfaces, and a higher value both brightens the film's own
    /// reflection and shortens the color cycle.
    public var thinFilmIor: Double

    /// Specular highlight strength: `0` matte, `~0.5` glossy, `1` a bright hotspot.
    public var specular: Double
    /// Blinn-Phong shininess exponent: higher is a tighter, sharper highlight.
    public var shininess: Double

    /// Iridescence strength, `0…1`: a view-angle rainbow sheen on top of the shading.
    public var iridescence: Double
    /// Iridescence band scale: how many hue cycles the sheen runs through from head-on
    /// to grazing (low = a few broad bands, high = many fine ones).
    public var iridescenceScale: Double
    /// Soap-film mode for the iridescence: with flow above `0` the sheen stops being a
    /// view-angle rim glow and becomes a real *film*, its color read off a thickness
    /// field the way a bubble's is. The film drains downward (broad marbled patches on
    /// the body, fine stacked bands toward the bottom, a darkening cap where it thins)
    /// and a domain-warped swirl drifts through it as `iridescencePhase` advances; the
    /// colors follow the interference series (straw, magenta, cyan, washing pale where
    /// thick, going dark where thin) rather than a rainbow wheel. `iridescenceFlow`
    /// sets the swirl's share of the thickness (`1` is the natural look); in this mode
    /// `iridescenceScale` sets how many interference orders the film spans. Compose
    /// with `.glass()` for a soap bubble.
    public var iridescenceFlow: Double
    /// The film swirl's animation clock: advance it yourself (`time * 0.3` reads well)
    /// so the swirling stays under the sketch's control and exports reproduce. Only
    /// read when `iridescenceFlow > 0`.
    public var iridescencePhase: Double
    /// The film swirl's feature size, relative to the scene's framing (the sparkle
    /// sizing rule, so the default reads alike at any scene scale): `1` is the
    /// default, smaller is finer marbling. A small bubble seen from afar wants
    /// `0.3`-ish so the wisps stay visible on its surface.
    public var iridescenceFlowSize: Double

    /// Sparkle (metallic-flake) strength, `0…1`: the surface is peppered with tiny
    /// mirror flakes that flash in and out as the view, object, or light moves
    /// (glitter, metallic car paint, sequins). `0` is off.
    public var sparkle: Double
    /// Sparkle flake size, relative to the scene's framing: `1` is a fine glitter
    /// dust; larger reads as chunky flakes and, big enough, sequin facets.
    public var sparkleSize: Double
    /// Sparkle flash tightness: how exactly a flake must face the viewer to light up.
    /// Higher makes the flashes rarer and harder-edged.
    public var sparkleSharpness: Double
    /// The flake tint (white by default; gold or copper flakes are a tint away).
    public var sparkleColor: Color

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

    /// Real subsurface scattering strength, `0…1`: how much of the surface's light
    /// enters the body and re-emerges nearby, softening shading the way skin, wax,
    /// and marble do (a screen-space diffusion over the rendered surface, distinct
    /// from the stylized `subsurface` glow, which fakes back-light and can layer on
    /// top). `0` (the default) is off. Needs `scatteringRadius` set too; applies to
    /// solid and textured meshes on the main canvas.
    public var scattering: Double
    /// How far light travels under the surface before re-emerging, in world units.
    /// A human-scale head wants roughly 1% of its width; too large reads as wax.
    /// `0` (the default) turns the scattering off whatever `scattering` says.
    public var scatteringRadius: Double
    /// How far each channel travels *relative to* `scatteringRadius`: the channel
    /// ratios shape the diffusion color. The default (1, 0.37, 0.3) lets red run
    /// farthest, the warm halo of skin; near-equal channels read as a neutral
    /// marble or wax.
    public var scatteringColor: Color

    /// Gooch shading: the warm tone on the lit side. Ignored unless `shading == .gooch`.
    public var goochWarm: Color
    /// Gooch shading: the cool tone on the shadow side. Ignored unless `shading == .gooch`.
    public var goochCool: Color

    /// Build a material. Every parameter defaults to an inert value, so
    /// `Material(specular: 0.5)` is a plain glossy surface and the finishes only appear
    /// when you set them.
    public init(shading: Shading = .standard, toonBands: Double = 4,
                metallic: Double = 0, roughness: Double = 0.5,
                anisotropy: Double = 0, anisotropyRotation: Double = 0,
                transmission: Double = 0, ior: Double = 1.5,
                thickness: Double = 0, attenuationColor: Color = .white,
                attenuationDistance: Double = 0,
                clearcoat: Double = 0, clearcoatRoughness: Double = 0,
                sheen: Double = 0, sheenColor: Color = .white,
                sheenRoughness: Double = 0.5,
                thinFilm: Double = 0, thinFilmThickness: Double = 400,
                thinFilmIor: Double = 1.3,
                specular: Double = 0, shininess: Double = 32,
                iridescence: Double = 0, iridescenceScale: Double = 1,
                iridescenceFlow: Double = 0, iridescencePhase: Double = 0,
                iridescenceFlowSize: Double = 1,
                sparkle: Double = 0, sparkleSize: Double = 1,
                sparkleSharpness: Double = 48, sparkleColor: Color = .white,
                rim: Double = 0, rimPower: Double = 2, rimColor: Color = .white,
                subsurface: Double = 0, subsurfaceColor: Color = .white,
                scattering: Double = 0, scatteringRadius: Double = 0,
                scatteringColor: Color = Color(red: 1.0, green: 0.37, blue: 0.3),
                goochWarm: Color = Color(red: 0.7, green: 0.5, blue: 0.15),
                goochCool: Color = Color(red: 0.05, green: 0.1, blue: 0.35)) {
        self.shading = shading
        self.toonBands = max(1, toonBands)
        self.metallic = min(1, max(0, metallic))
        self.roughness = min(1, max(0, roughness))
        self.anisotropy = min(1, max(-1, anisotropy))
        self.anisotropyRotation = anisotropyRotation
        self.transmission = min(1, max(0, transmission))
        self.ior = max(1, ior)
        self.thickness = max(0, thickness)
        self.attenuationColor = attenuationColor
        self.attenuationDistance = max(0, attenuationDistance)
        self.clearcoat = min(1, max(0, clearcoat))
        self.clearcoatRoughness = min(1, max(0, clearcoatRoughness))
        self.sheen = min(1, max(0, sheen))
        self.sheenColor = sheenColor
        self.sheenRoughness = min(1, max(0, sheenRoughness))
        self.thinFilm = min(1, max(0, thinFilm))
        self.thinFilmThickness = max(0, thinFilmThickness)
        self.thinFilmIor = min(3, max(1, thinFilmIor))
        self.specular = max(0, specular)
        self.shininess = max(1, shininess)
        self.iridescence = min(1, max(0, iridescence))
        self.iridescenceScale = max(0, iridescenceScale)
        self.iridescenceFlow = max(0, iridescenceFlow)
        self.iridescencePhase = iridescencePhase
        self.iridescenceFlowSize = max(0.05, iridescenceFlowSize)
        self.sparkle = min(1, max(0, sparkle))
        self.sparkleSize = max(0.05, sparkleSize)
        self.sparkleSharpness = max(1, sparkleSharpness)
        self.sparkleColor = sparkleColor
        self.rim = min(1, max(0, rim))
        self.rimPower = max(0.1, rimPower)
        self.rimColor = rimColor
        self.subsurface = min(1, max(0, subsurface))
        self.subsurfaceColor = subsurfaceColor
        self.scattering = min(1, max(0, scattering))
        self.scatteringRadius = max(0, scatteringRadius)
        self.scatteringColor = scatteringColor
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
        m.sparkleColor = Material.linear(sparkleColor, alpha: sparkle)
        m.specular = Float(specular)
        m.shininess = Float(shininess)
        m.iridescence = Float(iridescence)
        m.iridescenceScale = Float(iridescenceScale)
        m.rimPower = Float(rimPower)
        m.toonBands = Float(toonBands)
        m.shadingModel = Int32(shading.rawValue)
        m.metallic = Float(metallic)
        m.roughness = Float(roughness)
        m.sparkleSize = Float(sparkleSize)
        m.sparkleSharpness = Float(sparkleSharpness)
        m.transmission = Float(transmission)
        m.ior = Float(ior)
        m.thickness = Float(thickness)
        m.iridescenceFlow = Float(iridescenceFlow)
        m.iridescencePhase = Float(iridescencePhase)
        m.iridescenceFlowSize = Float(iridescenceFlowSize)
        // Beer-Lambert exponentiates the attenuation color, so floor each channel just
        // above zero: pow(0, 0) is NaN territory under fast math, and a floored channel
        // still reads as "absorbs (almost) everything".
        let att = Material.linear(attenuationColor, alpha: attenuationDistance)
        m.attenuation = SIMD4<Float>(max(att.x, 1e-4), max(att.y, 1e-4), max(att.z, 1e-4), att.w)
        // Normal-incidence Fresnel from the IOR. The shader used to hard-code 0.04; pack
        // that exact literal at the default 1.5 so pre-glass frames stay bit-identical
        // (the computed ((0.5)/(2.5))^2 rounds to a different float than 0.04).
        m.f0 = ior == 1.5 ? 0.04 : Float(((ior - 1) / (ior + 1)) * ((ior - 1) / (ior + 1)))
        m.clearcoat = Float(clearcoat)
        m.clearcoatRoughness = Float(clearcoatRoughness)
        // The sheen strength premultiplies the tint (the shader tests the rgb sum, so
        // strength 0 reads as "no sheen" whatever the tint); w carries the roughness.
        let sc = Material.linear(sheenColor, alpha: sheenRoughness)
        m.sheenColor = SIMD4<Float>(sc.x * Float(sheen), sc.y * Float(sheen),
                                    sc.z * Float(sheen), sc.w)
        // The scattering falloff ratios ride raw (they are relative widths, not a
        // display color; linearizing would bend the ratios the sketch wrote), floored
        // just above zero so the kernel's per-channel stretch can't divide by zero.
        m.scatter = SIMD4<Float>(Float(max(0.001, scatteringColor.red)),
                                 Float(max(0.001, scatteringColor.green)),
                                 Float(max(0.001, scatteringColor.blue)),
                                 Float(scatteringRadius))
        m.scatterStrength = Float(scattering)
        // A film of no thickness has nothing to interfere in, so the strength ships as
        // zero there: that keeps the shader's gate a single compare and stops a
        // thickness of 0 from asking the model for a color it has no basis for.
        m.thinFilm = thinFilmThickness > 0 ? Float(thinFilm) : 0
        m.thinFilmThickness = Float(thinFilmThickness)
        m.thinFilmIor = Float(thinFilmIor)
        // The brushing rotation ships as cos/sin so the fragment never evaluates the
        // angle; at strength 0 the shader's gate keeps the whole lobe untouched.
        m.anisotropy = SIMD4<Float>(Float(anisotropy),
                                    Float(cos(anisotropyRotation)),
                                    Float(sin(anisotropyRotation)), 0)
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

    /// Unfired-clay earthenware: a faint, very broad sheen over a matte surface,
    /// the soft light-catch of a smoothed slip.
    static let clay = Material(specular: 0.14, shininess: 4)

    /// Soft rubber or matte vinyl: a wide, soft highlight, clearly present but
    /// never sharp, the sheen of an eraser or a tire sidewall.
    static let rubber = Material(specular: 0.38, shininess: 20)

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

    /// Beetle shell / butterfly wing: a few broad iridescent bands over a hard
    /// glossy shell, a deep structural shimmer rather than a busy rainbow.
    static let beetle = Material(specular: 0.85, shininess: 140,
                                 iridescence: 1.0, iridescenceScale: 0.8)

    // Sparkle (metallic-flake) family: mirror flakes that flash as the view moves.

    /// Glitter: a dense dust of tiny mirror flakes over a satin body. Craft glitter,
    /// or metallic car paint (the body color is the `fill`; tint the flakes gold or
    /// copper via `sparkleColor`).
    static let glitter = Material(specular: 0.35, shininess: 60, sparkle: 0.9)

    /// Sequins / disco: chunky mirror paillettes that flash whole as the view sweeps,
    /// over a glossy body.
    static let sequin = Material(specular: 0.5, shininess: 90,
                                 sparkle: 1.0, sparkleSize: 9, sparkleSharpness: 60)

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

    // Real subsurface scattering: the screen-space diffusion blur, on the
    // physically-based finish. The radius is in world units, so it names the one
    // scene-dependent number (a head-sized form wants roughly 1% of its width).

    /// **Skin**: a soft dielectric whose light diffuses under the surface, red
    /// running farthest, the warm halo that separates skin from painted plastic.
    /// `radius` is how far light travels under the surface, in world units.
    static func skin(radius: Double) -> Material {
        Material(shading: .physicallyBased, metallic: 0, roughness: 0.45,
                 scattering: 0.85, scatteringRadius: radius)
    }

    /// **Marble** / alabaster: a polished stone whose shading softens into the body,
    /// with a near-neutral, slightly warm diffusion. `radius` is how far light
    /// travels under the surface, in world units.
    static func marble(radius: Double) -> Material {
        Material(shading: .physicallyBased, metallic: 0, roughness: 0.2,
                 scattering: 0.7, scatteringRadius: radius,
                 scatteringColor: Color(red: 1.0, green: 0.83, blue: 0.72))
    }

    // Non-photorealistic shading models.

    /// Toon / cel shading: the diffuse term steps through hard bands, the cartoon
    /// look, with a small crisp highlight.
    static let toon = Material(shading: .toon, toonBands: 4,
                               specular: 0.4, shininess: 64)

    /// Gooch warm–cool shading: the technical-illustration / blueprint aesthetic,
    /// warm where lit and cool in shadow, with a faint highlight.
    static let gooch = Material(shading: .gooch, specular: 0.25, shininess: 48)

    // Physically-based (metallic-roughness) family, the energy-conserving tier. The
    // surface *color* is still the current `fill`; these set the `metallic`/`roughness`
    // that drive the Cook-Torrance shading (and, with an environment, the reflections).

    /// The physically-based finish with explicit `metallic`/`roughness` factors
    /// (the defaults are the neutral dielectric). With a metallic-roughness
    /// *map* on the mesh, the sampled channels multiply these, so
    /// `.physicallyBased(metallic: 1, roughness: 1)` shows a model's maps as
    /// authored (1 is the map factors' identity).
    static func physicallyBased(metallic: Double = 0, roughness: Double = 0.5) -> Material {
        Material(shading: .physicallyBased, metallic: metallic, roughness: roughness)
    }

    /// A physically-based **metal** of the given roughness (`0` mirror-smooth … `1` fully
    /// rough). The reflection is tinted by the surface `fill`. `Material.metal(roughness:
    /// 0.2)` is a lightly-brushed steel; pair with a gold/copper `fill` for those metals.
    static func metal(roughness: Double = 0.25) -> Material {
        Material(shading: .physicallyBased, metallic: 1, roughness: roughness)
    }

    /// A physically-based **dielectric** (non-metal: plastic, ceramic, stone, paint) of
    /// the given roughness. Keeps a neutral highlight over a diffuse body colored by `fill`.
    static func dielectric(roughness: Double = 0.5) -> Material {
        Material(shading: .physicallyBased, metallic: 0, roughness: roughness)
    }

    /// Brushed metal: a physically-based conductor whose highlight streaks along the
    /// brushing (the anisotropic lobe), the way a brushed or lathed surface reflects.
    static let brushedMetal = Material(shading: .physicallyBased, metallic: 1,
                                       roughness: 0.4, anisotropy: 0.8)

    /// Polished metal: a physically-based conductor with a tight, near-mirror reflection.
    static let polishedMetal = Material(shading: .physicallyBased, metallic: 1, roughness: 0.08)

    /// Smooth plastic: a physically-based dielectric with a clean, fairly sharp highlight.
    static let smoothPlastic = Material(shading: .physicallyBased, metallic: 0, roughness: 0.25)

    /// Rough plastic / matte paint: a physically-based dielectric with a broad, soft sheen.
    static let roughPlastic = Material(shading: .physicallyBased, metallic: 0, roughness: 0.7)

    // Glass (transmission) family: physically-based dielectrics that let light through.
    // The `fill` tints what shows through; an environment must be set for there to be
    // anything to transmit, and `rayTracedReflections()` upgrades the view through the
    // glass from the environment to the actual scene on a ray-tracing GPU.

    /// **Glass** of the given roughness (`0` clear … higher frosts the view through it).
    /// `thickness` `0` is a thin wall (a pane, a bubble); a positive thickness makes the
    /// body solid, bending the view and, with an `attenuationColor` short of white,
    /// absorbing light along the interior path (`attenuationDistance` sets how fast).
    /// The surface tint stays the current `fill`.
    static func glass(roughness: Double = 0, ior: Double = 1.5, thickness: Double = 0,
                      attenuationColor: Color = .white,
                      attenuationDistance: Double = 0) -> Material {
        Material(shading: .physicallyBased, metallic: 0, roughness: roughness,
                 transmission: 1, ior: ior, thickness: thickness,
                 attenuationColor: attenuationColor,
                 attenuationDistance: attenuationDistance)
    }

    /// Frosted glass: fully transmissive, but rough enough that what shows through
    /// softens to a blur. A thin wall; give it a `thickness` for a solid body.
    static let frostedGlass = Material(shading: .physicallyBased, metallic: 0,
                                       roughness: 0.2, transmission: 1)

    /// Clear glass, ready-made: the `glass()` default as a fixed value, a smooth
    /// thin-walled dielectric the view passes straight through, tinted by the
    /// `fill`. Reach for `glass(roughness:ior:thickness:...)` when the body needs
    /// its own shape.
    static let clearGlass = Material(shading: .physicallyBased, metallic: 0,
                                     roughness: 0, transmission: 1)

    /// Gummy candy / jelly: a glossy translucent body with a little depth, the
    /// light glowing into it rather than through. The flavor is the `fill`.
    static let gummy = Material(shading: .physicallyBased, metallic: 0, roughness: 0.25,
                                transmission: 0.6, ior: 1.4, thickness: 0.8)

    // Layered physically-based finishes: a clear lacquer coat over the base
    // (`clearcoat`), and fabric sheen at the silhouette (`sheen`).

    /// **Car paint**: a metallic base of the given roughness under a polished clear
    /// coat, so the body keeps a soft satin depth while the coat carries a glassy
    /// reflection. The paint color is the `fill`; layer `sparkle` on top for the
    /// metallic-flake version.
    static func carPaint(roughness: Double = 0.45) -> Material {
        Material(shading: .physicallyBased, metallic: 1, roughness: roughness,
                 clearcoat: 1, clearcoatRoughness: 0.04)
    }

    /// Piano lacquer / varnished wood: a matte dielectric body under a deep glassy
    /// coat. Reads best over a dark `fill`.
    static let lacquer = Material(shading: .physicallyBased, metallic: 0, roughness: 0.5,
                                  clearcoat: 1, clearcoatRoughness: 0.03)

    /// Satin: a smooth woven sheen pulled into a tight band near the silhouette,
    /// over a soft body.
    static let satin = Material(shading: .physicallyBased, metallic: 0, roughness: 0.55,
                                sheen: 0.5, sheenRoughness: 0.3)

    /// Felt / velour: a dry, fuzzy fabric whose silhouette catches a broad haze of
    /// light. Tint `sheenColor` away from the `fill` for the two-tone velvet look.
    static let felt = Material(shading: .physicallyBased, metallic: 0, roughness: 0.9,
                               sheen: 0.9, sheenRoughness: 0.75)

    // Thin-film interference: a transparent film lying on a physically-based surface,
    // colored by light meeting itself out of step rather than by any pigment. The
    // thickness is in nanometers, so these values are the same on a bubble and on a
    // building. Curved surfaces band on their own, because the film's path grows as
    // the surface turns away.

    /// **Anodized metal**: a polished conductor under a hard oxide film, the peacock
    /// blues and violets of anodized titanium or a heat-tinted exhaust pipe. The
    /// `fill` colors the metal under the film.
    static let anodized = Material(shading: .physicallyBased, metallic: 1, roughness: 0.18,
                                   thinFilm: 1, thinFilmThickness: 420)

    /// **Oil on water**: a slick over a dark wet surface, the swirl of color on a
    /// puddle. Reads best over a dark `fill`.
    static let oilOnWater = Material(shading: .physicallyBased, metallic: 0, roughness: 0.08,
                                     thinFilm: 1, thinFilmThickness: 550)

    /// **Nacre** / mother-of-pearl: a pale shell that runs through soft pinks and
    /// greens as it turns, over a smooth body.
    static let nacre = Material(shading: .physicallyBased, metallic: 0, roughness: 0.14,
                                thinFilm: 1, thinFilmThickness: 320)

    /// **A soap film** of the given thickness in nanometers: a clear thin wall you see
    /// through, colored the way a real bubble is. Wants an environment set, like the
    /// other transmissive finishes, and a thickness from about `300` to `800`. A real
    /// bubble drains as it stands, so drive the thickness down over time for the
    /// color to walk down its series.
    static func soapFilm(thickness: Double = 520) -> Material {
        Material(shading: .physicallyBased, metallic: 0, roughness: 0,
                 transmission: 1, ior: 1.33,
                 thinFilm: 1, thinFilmThickness: thickness, thinFilmIor: 1.33)
    }
}
