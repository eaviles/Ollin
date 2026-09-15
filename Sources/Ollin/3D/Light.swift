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
/// Any light with a position can be given a `reach`: the distance past which it
/// contributes exactly nothing. A frame may carry as many of those as it likes
/// (`OLLIN_MAX_SCENE_LIGHTS`); past eight the renderer shades each pixel against
/// the lights that actually arrive there rather than all of them.
///
/// A point or spot light can also be *shaped*: an `IESProfile` (a real
/// fixture's measured angular throw) sculpts where the intensity goes, and a
/// spot can project a `LightCookie` image through its cone (a gobo, a gel).
///
/// A light's position and direction are **world-space** by default, so the sun
/// stays put as the camera orbits, which is what a sun, a sky, and a product
/// shot all want. `relativeTo(.camera)` reads them in the camera's own frame
/// instead (x right, y up, z back toward the eye, the eye at the origin), resolved
/// against the active `Camera3D` each frame, so the light rides the view: a
/// `headlight()` that keeps the side facing you from ever going black, or a
/// whole rig (`LightingPreset.relativeTo(.camera)`) that holds its look under
/// orbit instead of turning with the world.
public struct Light: Equatable, Sendable {

    /// The frame a light's `position`, `direction`, and `up` are read in.
    public enum Frame: Equatable, Sendable {
        /// World space (the default): the light stays put as the camera moves.
        case world
        /// The active camera's own space, the eye at the origin, x to its right,
        /// y up, and z back toward it (the camera looks down −z). Resolved into
        /// world space against the frame's `Camera3D` each time the lights pack,
        /// so the light follows the view. With no camera set it reads as world.
        case camera
    }

    /// Which light model this is.
    public enum Kind: Equatable, Sendable {
        case directional
        case point
        case spot
        case rectangle
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
    public var isTwoSided: Bool
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

    /// How far this light carries, in world units. `nil` (the default) is the
    /// unbounded model: a point or spot light reaches equally far forever, and an
    /// area light falls off physically but never quite reaches zero.
    ///
    /// Give it a number and the light is full strength at the source, a quarter of
    /// that halfway out, and *exactly* nothing at `reach` and beyond. (Real light
    /// thins as the inverse square of the distance. That curve has no finite edge
    /// and blows up at the source, and this is the same shape with both ends made
    /// usable.) The bound is what makes a courtyard of lamps read as lamps rather
    /// than one flat wash, and it is also what lets a frame carry many of them: a
    /// light that cannot arrive somewhere is not shaded there.
    ///
    /// Ignored by a directional light, which has no position to measure from.
    public var reach: Double?

    /// The frame `position`, `direction`, and `up` are read in: `.world` (the
    /// default) or `.camera`, the view's own frame. See `relativeTo(_:)`.
    public var frame: Frame

    /// Whether this light throws a shadow while the scene casts them
    /// (`castShadows()`); `true` by default.
    ///
    /// A frame can carry several casters at once, so a key light and a spot both
    /// throw. Set this to `false` on a light that should only add brightness: a
    /// bounce or fill light usually reads better with no shadow of its own, and each
    /// caster costs its own depth pass over the scene. A frame casts from at most four
    /// lights, the ones set first. Two kinds never take an extra slot: a **tube**, which
    /// emits radially and so has no direction to render a map from, and a **point**
    /// light, which casts only when it is the frame's primary caster (it needs the one
    /// cube map, or the one acceleration structure, that belongs to that caster). With
    /// `castShadows()` off, nothing casts and this is ignored.
    ///
    /// Use `castingShadow(_:)` to set it on a light from a factory.
    public var castsShadow: Bool

    /// The most general initializer; prefer the `.directional`/`.point`/`.spot`/
    /// `.rect`/`.disk`/`.tube` factories, which fill in the fields that don't
    /// apply to a kind.
    public init(kind: Kind, color: Color, intensity: Double = 1,
                specular: Color? = nil, softness: Double = 0,
                position: Vector3 = .zero, direction: Vector3 = Vector3(0, -1, 0),
                coneAngle: Double = .pi / 6, penumbra: Double = 0.2,
                width: Double = 1, height: Double = 1, radius: Double = 0.5,
                length: Double = 1, up: Vector3 = .unitY, isTwoSided: Bool = false,
                profile: IESProfile? = nil, cookie: LightCookie? = nil,
                roll: Double = 0, reach: Double? = nil,
                castsShadow: Bool = true, frame: Frame = .world) {
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
        self.isTwoSided = isTwoSided
        self.profile = profile
        self.cookie = cookie
        self.roll = roll
        self.reach = reach.map { max(0, $0) }
        self.castsShadow = castsShadow
        self.frame = frame
    }

    /// This light read in `frame`: `.relativeTo(.camera)` makes its `position`,
    /// `direction`, and `up` camera-space, so it follows the view, and
    /// `.relativeTo(.world)` puts it back. The numbers are left as they are; only
    /// the frame they mean changes. In camera space the eye sits at the origin,
    /// `Vector3(0, 0, -1)` is the direction the camera looks, and a point light at
    /// `Vector3(2, 1, 0)` hangs two to the right of the eye and one above it.
    public func relativeTo(_ frame: Frame) -> Light {
        var copy = self
        copy.frame = frame
        return copy
    }

    /// A light shining from the eye along the view, the lamp on a miner's helmet:
    /// a camera-relative directional light down `Vector3(0, 0, -1)`, so whatever
    /// faces the camera is lit and the side facing away is what falls off. Use it
    /// as a fill that follows an orbit, so a turned-away face never goes fully
    /// black, or on its own for the flat, even look of a flash. It casts no
    /// shadow: seen from the eye, every shadow it would throw hides behind what
    /// throws it, so the pass would buy nothing.
    public static func headlight(_ color: Color = .white, intensity: Double = 1,
                                 specular: Color? = nil, softness: Double = 0) -> Light {
        Light(kind: .directional, color: color, intensity: intensity,
              specular: specular, softness: softness, direction: Vector3(0, 0, -1),
              castsShadow: false, frame: .camera)
    }

    /// This light with its `position`, `direction`, and `up` in world space: a
    /// world light comes back untouched (the same values, no arithmetic), a
    /// camera-relative one is turned and moved by the camera's basis (its
    /// `position` offset from the eye), and comes back marked `.world`. With no
    /// camera the numbers are taken as world space as they stand.
    func resolved(in camera: Camera3D?) -> Light {
        guard frame == .camera else { return self }
        var world = self
        world.frame = .world
        guard let camera else { return world }
        let basis = camera.basis
        func turned(_ v: Vector3) -> Vector3 {
            basis.right * v.x + basis.up * v.y + basis.back * v.z
        }
        world.position = camera.eye + turned(position)
        world.direction = turned(direction)
        world.up = turned(up)
        return world
    }

    /// This light with its shadow turned on or off: `Light.point(...).castingShadow(false)`
    /// adds a fill that lights the scene and throws nothing. See `castsShadow`.
    public func castingShadow(_ on: Bool = true) -> Light {
        var copy = self
        copy.castsShadow = on
        return copy
    }

    /// This light carried only so far: `Light.point(...).reaching(30)` lights its own
    /// neighborhood and nothing past 30 world units. `nil` puts it back to unbounded.
    /// See `reach`.
    public func reaching(_ distance: Double?) -> Light {
        var copy = self
        copy.reach = distance.map { max(0, $0) }
        return copy
    }

    /// A directional light (parallel rays, like sunlight). `direction` is the way
    /// the light travels — `Vector3(0, -1, 0)` shines straight down. `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) wraps the
    /// terminator for a gentler shaded edge.
    public static func directional(_ color: Color, direction: Vector3,
                                   intensity: Double = 1,
                                   specular: Color? = nil, softness: Double = 0,
                                   castsShadow: Bool = true) -> Light {
        Light(kind: .directional, color: color, intensity: intensity,
              specular: specular, softness: softness, direction: direction,
              castsShadow: castsShadow)
    }

    /// A point light: an omnidirectional source at a world position. `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) softens the
    /// terminator. An IES `profile` shapes the falloff by angle, aimed along
    /// `axis` (the fixture's hanging direction, straight down by default) and
    /// spun about it by `roll`. `reach` bounds how far it carries (see `reach`).
    public static func point(_ color: Color, at position: Vector3,
                             intensity: Double = 1,
                             specular: Color? = nil, softness: Double = 0,
                             profile: IESProfile? = nil,
                             direction: Vector3 = Vector3(0, -1, 0),
                             roll: Double = 0, reach: Double? = nil,
                             castsShadow: Bool = true) -> Light {
        Light(kind: .point, color: color, intensity: intensity,
              specular: specular, softness: softness, position: position,
              direction: direction, profile: profile, roll: roll, reach: reach,
              castsShadow: castsShadow)
    }

    /// A spot light: a point source at `position` narrowed to a cone aimed along
    /// `direction`, with a `penumbra` soft edge (`0` hard, up to `1`). `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) softens the
    /// terminator. An IES `profile` shapes the throw inside the cone, a
    /// `cookie` projects an image through it, `roll` spins both about the beam,
    /// and `reach` bounds how far it carries (see `reach`).
    public static func spot(_ color: Color, at position: Vector3, direction: Vector3,
                            coneAngle: Double = .pi / 6, penumbra: Double = 0.2,
                            intensity: Double = 1,
                            specular: Color? = nil, softness: Double = 0,
                            profile: IESProfile? = nil, cookie: LightCookie? = nil,
                            roll: Double = 0, reach: Double? = nil,
                            castsShadow: Bool = true) -> Light {
        Light(kind: .spot, color: color, intensity: intensity,
              specular: specular, softness: softness,
              position: position, direction: direction, coneAngle: coneAngle, penumbra: penumbra,
              profile: profile, cookie: cookie, roll: roll, reach: reach,
              castsShadow: castsShadow)
    }

    /// A rect area light: a glowing `width` × `height` panel centered at `position`,
    /// facing along `direction` (its travel direction, like a spot's axis), the height
    /// axis oriented by the `up` hint. `isTwoSided` makes both faces emit. Highlights
    /// stretch into the panel's reflection and brightness falls off with distance;
    /// `color` × `intensity` is the panel's radiance, so a bigger panel casts more
    /// light. `specular` (default `nil` = `color`) tints its highlight, and
    /// `reach` bounds how far it carries (see `reach`).
    public static func rectangle(_ color: Color, at position: Vector3, direction: Vector3,
                            width: Double, height: Double, up: Vector3 = .unitY,
                            isTwoSided: Bool = false, intensity: Double = 1,
                            specular: Color? = nil, reach: Double? = nil,
                            castsShadow: Bool = true) -> Light {
        Light(kind: .rectangle, color: color, intensity: intensity, specular: specular,
              position: position, direction: direction,
              width: width, height: height, up: up, isTwoSided: isTwoSided,
              reach: reach, castsShadow: castsShadow)
    }

    /// A disk area light: a glowing circular panel of `radius` centered at `position`,
    /// facing along `direction`. `isTwoSided` makes both faces emit. Falls off with
    /// distance like the rect; `color` × `intensity` is the disk's radiance.
    /// `specular` (default `nil` = `color`) tints its highlight, and `reach`
    /// bounds how far it carries (see `reach`).
    public static func disk(_ color: Color, at position: Vector3, direction: Vector3,
                            radius: Double, isTwoSided: Bool = false, intensity: Double = 1,
                            specular: Color? = nil, reach: Double? = nil,
                            castsShadow: Bool = true) -> Light {
        Light(kind: .disk, color: color, intensity: intensity, specular: specular,
              position: position, direction: direction,
              radius: radius, isTwoSided: isTwoSided, reach: reach,
              castsShadow: castsShadow)
    }

    /// A tube area light: a glowing cylinder of `radius` running `from` one point `to`
    /// another (a fluorescent or neon tube), emitting radially all around. Falls off
    /// with distance; `color` × `intensity` is the tube surface's radiance, so a thin
    /// tube wants a high intensity (a real neon is a very bright surface). `specular`
    /// (default `nil` = `color`) tints its highlight, and `reach` bounds how far it
    /// carries (see `reach`).
    public static func tube(_ color: Color, from: Vector3, to: Vector3,
                            radius: Double = 0.1, intensity: Double = 1,
                            specular: Color? = nil, reach: Double? = nil) -> Light {
        let axis = to - from
        let len = axis.length
        return Light(kind: .tube, color: color, intensity: intensity, specular: specular,
                     position: (from + to) * 0.5,
                     direction: len > 0 ? axis * (1 / len) : Vector3(1, 0, 0),
                     radius: radius, length: len, reach: reach)
    }
}
