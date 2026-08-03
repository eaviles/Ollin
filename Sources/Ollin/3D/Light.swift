import Foundation

/// A light in the 3D scene: it shades solid meshes (`drawBox`, `drawSphere`, …)
/// through a Blinn-Phong material whose surface color is the current `fill`.
///
/// Lights are *per-frame* state, like the `Camera3D`: set them each `draw()` (the
/// scene rebuilds every frame). A mesh drawn with no lights set is shaded by a
/// sensible default rig (so a solid looks 3D out of the box); setting a light, an
/// ambient, or a `LightingPreset` takes over the scene. There are three kinds:
///
/// - **directional** — parallel rays from a direction (the sun): no position, just
///   a direction the light travels.
/// - **point** — an omnidirectional source at a position (a bare bulb).
/// - **spot** — a point source narrowed to a cone (a stage light), with a soft
///   inner→outer edge.
///
/// Beyond those three punctual kinds, a light can be an **area**: a glowing
/// surface rather than an infinitesimal source, shaded analytically (the
/// linearly-transformed-cosine technique), so highlights stretch into the
/// shape's reflection and shading softens the way studio lighting does:
///
/// - **rect**: a flat rectangular panel (a softbox, a window).
/// - **disk**: a flat circular panel (a ring light's face, a recessed ceiling can).
/// - **tube**: a glowing cylinder between two points (a fluorescent or neon tube).
///
/// Build them with the factories (`.directional`, `.point`, `.spot`, `.rect`,
/// `.disk`, `.tube`) or use the bare calls on `Sketch` (`directionalLight`,
/// `pointLight`, `spotLight`, `rectLight`, `diskLight`, `tubeLight`,
/// `ambientLight`). There's no distance attenuation in the punctual model (a
/// point and a spot light reach equally far), so brightness is set by
/// `intensity`. An area light instead falls off physically (its surface fills
/// less of the sky as it recedes), and its `color` × `intensity` is the
/// surface's *radiance*, so a bigger panel casts more light into the scene.
///
/// A point or spot light can also be *shaped*: an `IESProfile` (a real
/// fixture's measured angular throw) sculpts where the intensity goes, and a
/// spot can project a `LightCookie` image through its cone (a gobo, a gel).
public struct Light: Equatable, Sendable {

    /// Which light model this is.
    public enum Kind: Equatable, Sendable {
        case directional
        case point
        case spot
        case rect
        case disk
        case tube
    }

    /// The kind of light (directional / point / spot).
    public var kind: Kind
    /// The light's color, used for the diffuse term. Combined with `intensity` to
    /// drive the shading.
    public var color: Color
    /// A scalar brightness multiplier on `color` (1 = the color as given).
    public var intensity: Double
    /// The light's *specular* color — the tint of its highlight. `nil` (the default)
    /// uses `color`, so a plain light's highlight matches its diffuse color. Set it to
    /// give a light a punchier or differently-tinted highlight than its fill light (a
    /// crisp white spec over a warm key, a strong rim), scaled by the same `intensity`.
    public var specular: Color?
    /// Diffuse **softness**, `0…1`: wraps the light a little past the terminator so the
    /// shaded edge is gentler (a softbox vs a bare bulb). `0` (the default) is hard
    /// Lambert shading, unchanged; higher values fill the shadow side more.
    public var softness: Double
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
    /// Rect light only: the panel's full width, in world units.
    public var width: Double
    /// Rect light only: the panel's full height, in world units.
    public var height: Double
    /// Disk and tube lights: the disk's radius / the tube's thickness radius.
    public var radius: Double
    /// Tube light only: the tube's full length along `direction`.
    public var length: Double
    /// Rect light only: an up hint that orients the panel's height axis (like a
    /// camera's up vector). Ignored by every other kind; a disk is round, so it
    /// needs no orientation beyond `direction`.
    public var up: Vector3
    /// Rect and disk lights: `true` emits from both faces of the panel; `false`
    /// (the default) lights only what the panel faces. A tube always emits radially.
    public var twoSided: Bool
    /// An IES photometric profile shaping where this light sends its intensity
    /// (point and spot only; `nil`, the default, keeps the plain falloff). The
    /// profile's 0° aims along the light's axis: a spot's `direction`, or the
    /// `direction` a point light is given as its fixture axis (straight down
    /// by default). See `IESProfile`.
    public var profile: IESProfile?
    /// A projected image (spot only; `nil`, the default, projects nothing).
    /// The image's edges land at the outer cone, its color multiplies the
    /// light (black blocks, color tints), and `roll` spins it. See `LightCookie`.
    public var cookie: LightCookie?
    /// Rotation about the beam axis, in radians: spins an asymmetric
    /// `profile`'s azimuth and a `cookie`'s image together, the way rotating
    /// a real fixture in its yoke turns both. Ignored with neither set.
    public var roll: Double

    /// The most general initializer; prefer the `.directional`/`.point`/`.spot`/
    /// `.rect`/`.disk`/`.tube` factories, which fill in the fields that don't
    /// apply to a kind.
    public init(kind: Kind, color: Color, intensity: Double = 1,
                specular: Color? = nil, softness: Double = 0,
                position: Vector3 = .zero, direction: Vector3 = Vector3(0, -1, 0),
                coneAngle: Double = .pi / 6, penumbra: Double = 0.2,
                width: Double = 1, height: Double = 1, radius: Double = 0.5,
                length: Double = 1, up: Vector3 = .unitY, twoSided: Bool = false,
                profile: IESProfile? = nil, cookie: LightCookie? = nil,
                roll: Double = 0) {
        self.kind = kind
        self.color = color
        self.intensity = intensity
        self.specular = specular
        self.softness = min(1, max(0, softness))
        self.position = position
        self.direction = direction
        self.coneAngle = coneAngle
        self.penumbra = penumbra
        self.width = max(0, width)
        self.height = max(0, height)
        self.radius = max(0, radius)
        self.length = max(0, length)
        self.up = up
        self.twoSided = twoSided
        self.profile = profile
        self.cookie = cookie
        self.roll = roll
    }

    /// A directional light (parallel rays, like sunlight). `direction` is the way
    /// the light travels — `Vector3(0, -1, 0)` shines straight down. `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) wraps the
    /// terminator for a gentler shaded edge.
    public static func directional(_ color: Color, direction: Vector3,
                                   intensity: Double = 1,
                                   specular: Color? = nil, softness: Double = 0) -> Light {
        Light(kind: .directional, color: color, intensity: intensity,
              specular: specular, softness: softness, direction: direction)
    }

    /// A point light: an omnidirectional source at a world position. `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) softens the
    /// terminator. An IES `profile` shapes the falloff by angle, aimed along
    /// `axis` (the fixture's hanging direction, straight down by default) and
    /// spun about it by `roll`.
    public static func point(_ color: Color, at position: Vector3,
                             intensity: Double = 1,
                             specular: Color? = nil, softness: Double = 0,
                             profile: IESProfile? = nil,
                             axis: Vector3 = Vector3(0, -1, 0),
                             roll: Double = 0) -> Light {
        Light(kind: .point, color: color, intensity: intensity,
              specular: specular, softness: softness, position: position,
              direction: axis, profile: profile, roll: roll)
    }

    /// A spot light: a point source at `position` narrowed to a cone aimed along
    /// `direction`, with a `penumbra` soft edge (`0` hard, up to `1`). `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) softens the
    /// terminator. An IES `profile` shapes the throw inside the cone, a
    /// `cookie` projects an image through it, and `roll` spins both about
    /// the beam.
    public static func spot(_ color: Color, at position: Vector3, direction: Vector3,
                            angle: Double = .pi / 6, penumbra: Double = 0.2,
                            intensity: Double = 1,
                            specular: Color? = nil, softness: Double = 0,
                            profile: IESProfile? = nil, cookie: LightCookie? = nil,
                            roll: Double = 0) -> Light {
        Light(kind: .spot, color: color, intensity: intensity,
              specular: specular, softness: softness,
              position: position, direction: direction, coneAngle: angle, penumbra: penumbra,
              profile: profile, cookie: cookie, roll: roll)
    }

    /// A rect area light: a glowing `width` × `height` panel centered at `position`,
    /// facing along `direction` (its travel direction, like a spot's axis), the height
    /// axis oriented by the `up` hint. `twoSided` makes both faces emit. Highlights
    /// stretch into the panel's reflection and brightness falls off with distance;
    /// `color` × `intensity` is the panel's radiance, so a bigger panel casts more
    /// light. `specular` (default `nil` = `color`) tints its highlight.
    public static func rect(_ color: Color, at position: Vector3, direction: Vector3,
                            width: Double, height: Double, up: Vector3 = .unitY,
                            twoSided: Bool = false, intensity: Double = 1,
                            specular: Color? = nil) -> Light {
        Light(kind: .rect, color: color, intensity: intensity, specular: specular,
              position: position, direction: direction,
              width: width, height: height, up: up, twoSided: twoSided)
    }

    /// A disk area light: a glowing circular panel of `radius` centered at `position`,
    /// facing along `direction`. `twoSided` makes both faces emit. Falls off with
    /// distance like the rect; `color` × `intensity` is the disk's radiance.
    /// `specular` (default `nil` = `color`) tints its highlight.
    public static func disk(_ color: Color, at position: Vector3, direction: Vector3,
                            radius: Double, twoSided: Bool = false, intensity: Double = 1,
                            specular: Color? = nil) -> Light {
        Light(kind: .disk, color: color, intensity: intensity, specular: specular,
              position: position, direction: direction,
              radius: radius, twoSided: twoSided)
    }

    /// A tube area light: a glowing cylinder of `radius` running `from` one point `to`
    /// another (a fluorescent or neon tube), emitting radially all around. Falls off
    /// with distance; `color` × `intensity` is the tube surface's radiance, so a thin
    /// tube wants a high intensity (a real neon is a very bright surface). `specular`
    /// (default `nil` = `color`) tints its highlight.
    public static func tube(_ color: Color, from: Vector3, to: Vector3,
                            radius: Double = 0.1, intensity: Double = 1,
                            specular: Color? = nil) -> Light {
        let axis = to - from
        let len = axis.length
        return Light(kind: .tube, color: color, intensity: intensity, specular: specular,
                     position: (from + to) * 0.5,
                     direction: len > 0 ? axis * (1 / len) : Vector3(1, 0, 0),
                     radius: radius, length: len)
    }
}
