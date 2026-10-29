/// What a `Volume` is made of, for `drawVolume(_:size:medium:)`: how thickly it
/// stands in the way of light, what color it scatters the scene's lights in, and
/// what light it gives off itself.
///
/// ```swift
/// drawVolume(smoke, size: 4, medium: .smoke)
/// drawVolume(core, size: 2, medium: .fire)
/// drawVolume(cloud, size: 8, medium: Medium(density: 0.2, glow: .violet))
/// ```
///
/// Every dial scales with the grid: where a volume reads 0.5 the medium is half
/// as thick and glows half as bright as where it reads 1. Light passing through
/// fades by Beer's law, `exp(-density * value * distance)`, so a box of value 1
/// that is `1 / density` world units deep lets through about 37% of what is
/// behind it. The scattered light is the scene's lights and ambient, shadowed by
/// the volume itself and by the solids around it, and with `bounce` the light
/// the medium passes on to itself: a thick white cloud glows from inside and its
/// far side keeps some of the light, the way a real one does, rather than
/// going dark a short way past the lit face.
public struct Medium: Equatable, Hashable, Sendable {
    /// How thickly the medium blocks light where the grid reads 1, in inverse
    /// world units (the unit `fog(_:density:heightFalloff:)` takes): light
    /// crossing `d` units of it keeps `exp(-density * d)` of itself. 0 blocks
    /// nothing, which leaves a pure glow. Clamped at 0.
    public var density: Double
    /// The color the medium scatters light in: each channel, in linear light, is
    /// the share of the light it stops that it sends back out (white scatters
    /// everything, like a cloud; black scatters nothing, like soot or ink, and
    /// only darkens).
    public var color: Color
    /// The light the medium gives off itself, per world unit of depth where the
    /// grid reads 1 (black, the default, gives off none). A glow with no
    /// `density` adds over what is behind it without hiding it, like a hot thin
    /// gas; with density, the glow of the deep parts is dimmed by the parts in
    /// front, like a flame's core behind its smoke.
    public var glow: Color
    /// How bright the glow is, a multiplier on `glow` (1 = the color as given).
    public var glowIntensity: Double
    /// Which way the medium scatters, `-0.95…0.95`: 0 sends light out equally
    /// in every direction, toward 1 mostly onward (a cloud lit from behind
    /// glows at its edges, the silver lining), toward -1 mostly back toward the
    /// light. The same dial as `volumetricLight(_:anisotropy:)`.
    public var anisotropy: Double
    /// How much of the light the medium stops it passes on to itself, `0…1`:
    /// at 0 each point is lit once by what reaches it through the medium, so a
    /// thick cloud is bright at its lit face and dark a short way in; at 1 (the
    /// default) the light bounces around inside, the interior glows, the far
    /// side keeps some light, and a cloud lit from behind shines through at
    /// its thin edges. A thick white cloud lit from the front reads what the
    /// exact solution for such a medium gives, about 1.06 of a white matte
    /// surface under the same light. Clamped to `0…1`; costs nothing at 0.
    public var bounce: Double

    /// A medium from its dials; the defaults are a white, evenly scattering
    /// haze one unit thick at a grid value of 1, bouncing its light inside.
    public init(density: Double = 1, color: Color = .white, glow: Color = .black,
                glowIntensity: Double = 1, anisotropy: Double = 0, bounce: Double = 1) {
        self.density = density
        self.color = color
        self.glow = glow
        self.glowIntensity = glowIntensity
        self.anisotropy = anisotropy
        self.bounce = bounce
    }

    /// Gray smoke: thick, scattering half the light it stops, a little
    /// forward.
    public static let smoke = Medium(density: 2, color: Color(linear: 0.5, green: 0.5, blue: 0.5), anisotropy: 0.2)
    /// A white cloud: thicker still, scattering nearly everything it stops
    /// and leaning forward, so it shines at the edge facing away from a light
    /// behind it.
    public static let cloud = Medium(density: 4, color: Color(linear: 0.95, green: 0.95, blue: 0.95), anisotropy: 0.5)
    /// Fire: a thin, dark medium glowing orange, so the deep glow shows
    /// through the near smoke.
    public static let fire = Medium(density: 0.8, color: Color(linear: 0.1, green: 0.1, blue: 0.1),
                                    glow: Color(hex: 0xFF7A1F), glowIntensity: 3)
    /// Ink: dense and black, scattering nothing, so it only takes light away,
    /// like a drop spreading in water or the shadow of an X-ray.
    public static let ink = Medium(density: 8, color: .black)
    /// A nebula: barely there, glowing violet over what is behind it and
    /// scattering a little of the scene's light forward.
    public static let nebula = Medium(density: 0.15, color: .white,
                                      glow: Color(hex: 0x8A5CFF), glowIntensity: 1.5,
                                      anisotropy: 0.3)
}

extension Medium: ParamChoices {
    /// The presets on the inspector's menu: `@Param var air: Medium = .smoke`.
    public static var paramChoices: [(name: String, value: Medium)] {
        [("smoke", .smoke), ("cloud", .cloud), ("fire", .fire), ("ink", .ink),
         ("nebula", .nebula)]
    }
}
