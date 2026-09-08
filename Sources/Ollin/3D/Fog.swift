import Foundation

/// The air a 3D scene stands in, as one value: a color, how much of the view
/// it takes, and whether it pools low. `fog(_:)` takes it whole, and the
/// presets name the looks the dials usually land on.
///
/// The bare `fog(_:density:heightFalloff:)` measures the air in inverse
/// world units, so a density that reads as mist over a ten-unit courtyard
/// reads as soup over a one-unit tabletop. A `Fog` measures it against the
/// camera instead: `veil` is how much of a surface at the camera's target
/// distance is fog, and `pooling` how fast the fog thins with height in
/// target distances, so `.mist` reads alike at any scene scale, the way a
/// bare `aerialPerspective()` does. The densities are worked out each frame
/// from the camera in force; with no 3D camera the frame has nothing to fog.
public struct Fog: Equatable, Hashable, Sendable {
    /// The fog's color, which is also the glow of the air itself.
    public var color: Color
    /// How much of a surface at the camera's target distance is fog, `0…1`:
    /// 0.25 a light haze, 0.5 a mist that halves the far side of the scene,
    /// 0.8 thick. Clamped below 1, since an air that hides the target
    /// entirely hides everything.
    public var veil: Double
    /// How the fog pools low: 0 is the same thickness at every height, 1
    /// thins it to a third by one target distance of height, 2 by half that.
    public var pooling: Double

    public init(_ color: Color = Color(hex: 0xB4BDC9), veil: Double = 0.5, pooling: Double = 0) {
        self.color = color
        self.veil = min(0.99, max(0, veil))
        self.pooling = max(0, pooling)
    }

    /// The same fog in another color.
    public func tinted(_ color: Color) -> Fog {
        Fog(color, veil: veil, pooling: pooling)
    }

    /// The extinction density in inverse world units this fog means at a
    /// camera whose target is `distance` away: the density whose transmittance
    /// over that distance leaves `1 - veil` of the surface.
    public func density(at distance: Double) -> Double {
        -log(1 - veil) / max(distance, 1e-4)
    }

    /// The height falloff in inverse world units this fog means at that
    /// framing distance.
    public func heightFalloff(at distance: Double) -> Double {
        pooling / max(distance, 1e-4)
    }

    /// A light, even haze: a quarter of the target veiled.
    public static let haze = Fog(veil: 0.25)
    /// The default mist: the target half veiled, the same at every height.
    public static let mist = Fog(veil: 0.5)
    /// Thick air: most of the target gone, the near things left.
    public static let thick = Fog(veil: 0.8)
    /// Morning mist pooled low: the target half veiled at ground level,
    /// thinning fast with height so tall things rise clear.
    public static let groundMist = Fog(veil: 0.5, pooling: 2)
    /// Night air: a dark blue-black haze that swallows the far side.
    public static let night = Fog(Color(hex: 0x0A0E18), veil: 0.6)
}

extension Fog: ParamChoices {
    /// The presets on the inspector's menu: `@Param var air: Fog = .mist`.
    public static var paramChoices: [(name: String, value: Fog)] {
        [("haze", .haze), ("mist", .mist), ("thick", .thick),
         ("groundMist", .groundMist), ("night", .night)]
    }
}
