import Foundation

/// A light in the 3D scene: it shades solid meshes (`drawBox`, `drawSphere`, …)
/// through a Blinn-Phong material whose surface color is the current `fill`.
///
/// Lights are *per-frame* state, like the `Camera3D`: set them each `draw()` (the
/// scene rebuilds every frame). A mesh drawn with no lights set keeps the
/// normal-as-color placeholder look, so lighting is opt-in — add a light and the
/// solids start shading. There are three kinds:
///
/// - **directional** — parallel rays from a direction (the sun): no position, just
///   a direction the light travels.
/// - **point** — an omnidirectional source at a position (a bare bulb).
/// - **spot** — a point source narrowed to a cone (a stage light), with a soft
///   inner→outer edge.
///
/// Build them with the factories (`.directional`, `.point`, `.spot`) or use the
/// bare calls on `Sketch` (`directionalLight`, `pointLight`, `spotLight`,
/// `ambientLight`). There's no distance attenuation in this first model — a point
/// and a spot light reach equally far — so brightness is set by `intensity`.
public struct Light: Equatable, Sendable {

    /// Which of the three light models this is.
    public enum Kind: Equatable, Sendable {
        case directional
        case point
        case spot
    }

    /// The kind of light (directional / point / spot).
    public var kind: Kind
    /// The light's color. Combined with `intensity` to drive the shading.
    public var color: Color
    /// A scalar brightness multiplier on `color` (1 = the color as given).
    public var intensity: Double
    /// World-space position. Used by point and spot lights (ignored by directional).
    public var position: Vector3
    /// The direction the light *travels* (from the source outward). Used by
    /// directional lights and as the cone axis of a spot light.
    public var direction: Vector3
    /// Spot light only: the full cone angle in radians. Surfaces outside the cone
    /// receive no light from this source.
    public var coneAngle: Double
    /// Spot light only: the soft-edge fraction, `0…1`. `0` is a hard cone edge;
    /// larger values fade the cone in from `coneAngle` toward its center.
    public var penumbra: Double

    /// The most general initializer; prefer the `.directional`/`.point`/`.spot`
    /// factories, which fill in the fields that don't apply to a kind.
    public init(kind: Kind, color: Color, intensity: Double = 1,
                position: Vector3 = .zero, direction: Vector3 = Vector3(0, -1, 0),
                coneAngle: Double = .pi / 6, penumbra: Double = 0.2) {
        self.kind = kind
        self.color = color
        self.intensity = intensity
        self.position = position
        self.direction = direction
        self.coneAngle = coneAngle
        self.penumbra = penumbra
    }

    /// A directional light (parallel rays, like sunlight). `direction` is the way
    /// the light travels — `Vector3(0, -1, 0)` shines straight down.
    public static func directional(_ color: Color, direction: Vector3,
                                   intensity: Double = 1) -> Light {
        Light(kind: .directional, color: color, intensity: intensity, direction: direction)
    }

    /// A point light: an omnidirectional source at a world position.
    public static func point(_ color: Color, at position: Vector3,
                             intensity: Double = 1) -> Light {
        Light(kind: .point, color: color, intensity: intensity, position: position)
    }

    /// A spot light: a point source at `position` narrowed to a cone aimed along
    /// `direction`, with a `penumbra` soft edge (`0` hard, up to `1`).
    public static func spot(_ color: Color, at position: Vector3, direction: Vector3,
                            angle: Double = .pi / 6, penumbra: Double = 0.2,
                            intensity: Double = 1) -> Light {
        Light(kind: .spot, color: color, intensity: intensity,
              position: position, direction: direction, coneAngle: angle, penumbra: penumbra)
    }
}
