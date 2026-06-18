import Foundation

/// A ready-made lighting *scene* (an ambient term plus a set of `Light`s) that a
/// sketch drops in with one call (`lightingPreset(_:)`) instead of hand-placing
/// lights. The built-in set is a small, curated range of moods (`.standard`,
/// `.threePoint`, `.goldenHour`, `.noir`, `.studio`, `.moonlight`), each tuned with
/// color temperatures (`Color(kelvin:)`) so a rig reads as the light it really is.
///
/// It's a plain value, so it's also the *extension* surface: build your own with
/// `LightingPreset(ambient:lights:)`, or copy a built-in and tweak it:
///
/// ```swift
/// var rig = LightingPreset.noir
/// rig.ambient = Color(white: 0.06)            // lift the shadows a touch
/// rig.lights.append(.point(Color(kelvin: 8000), at: Vector3(2, 3, 1)))
/// lightingPreset(rig.intensified(by: 0.8))    // and dim the whole thing
/// ```
///
/// There's no registry to add to; a preset is just a value you pass in, the same
/// construct-or-mutate shape the material library uses. Lights are world-space (the
/// sun stays put as the camera orbits) and the preset is applied as *this frame's*
/// lighting, so call `lightingPreset(_:)` in `draw()` like the individual light calls.
public struct LightingPreset: Equatable, Sendable {

    /// The flat ambient term added to every lit surface, so faces turned away from
    /// the lights aren't pure black.
    public var ambient: Color

    /// The lights in the rig (directional / point / spot).
    public var lights: [Light]

    /// Build a lighting preset from an ambient term and a set of lights.
    public init(ambient: Color, lights: [Light]) {
        self.ambient = ambient
        self.lights = lights
    }

    /// A copy with every light's `intensity` scaled by `factor`: dim a whole rig
    /// (`< 1`) or push it brighter (`> 1`) without touching each light. The ambient
    /// is left alone (it sets the shadow floor, not the key brightness).
    public func intensified(by factor: Double) -> LightingPreset {
        LightingPreset(ambient: ambient,
                       lights: lights.map { var l = $0; l.intensity *= factor; return l })
    }
}

// MARK: - The curated set

public extension LightingPreset {

    /// The default rig: a soft neutral ambient with a bright key and a dimmer fill
    /// from the opposite side. This is exactly what solids get automatically when no
    /// light is set, and what `lights()` installs: balanced and unfussy, the one to
    /// reach for when you just want the scene to look 3D. The fill wraps softly so the
    /// shadow side falls off gently rather than hitting a hard terminator.
    static let standard = LightingPreset(
        ambient: Color(white: 0.26),
        lights: [
            .directional(.white, direction: Vector3(-0.4, -0.7, -0.6), intensity: 0.9, softness: 0.12),
            .directional(Color(white: 0.6), direction: Vector3(0.5, 0.3, 0.4), intensity: 0.42, softness: 0.4),
        ])

    /// A classic film three-point rig: a daylight **key** from the front-left with a
    /// crisp highlight, a cooler, soft **fill** from the front-right opening up the
    /// shadows, and a **rim** light raking from behind with a bright white specular to
    /// separate the subject from its background. Low ambient, so the modeling comes
    /// from the lights rather than a flat fill.
    static let threePoint = LightingPreset(
        ambient: Color(white: 0.06),
        lights: [
            .directional(Color(kelvin: 5200), direction: Vector3(0.55, -0.55, -0.6), intensity: 1.0,
                         specular: .white, softness: 0.12),
            .directional(Color(kelvin: 7000), direction: Vector3(-0.6, -0.2, -0.5), intensity: 0.45,
                         softness: 0.55),
            .directional(Color(kelvin: 7200), direction: Vector3(0.1, -0.4, 0.9), intensity: 0.8,
                         specular: .white),
        ])

    /// Warm, low, raking sun near the horizon with a cool sky bounce from above: the
    /// golden-hour look. Long, warm key shadows with a warm highlight, lifted by a
    /// soft blue fill.
    static let goldenHour = LightingPreset(
        ambient: Color(red: 0.14, green: 0.11, blue: 0.09),
        lights: [
            .directional(Color(kelvin: 3300), direction: Vector3(-0.75, -0.22, -0.4), intensity: 1.2,
                         specular: Color(kelvin: 3800), softness: 0.15),
            .directional(Color(kelvin: 8500), direction: Vector3(0.2, -0.9, 0.25), intensity: 0.4,
                         softness: 0.6),
        ])

    /// High-contrast, single hard key: a neutral, almost white raking light with a
    /// crisp white highlight, the shadows crushed nearly to black and only a whisper of
    /// cool fill, so unlit faces fall away into darkness. The noir / dramatic look;
    /// pairs well with `castShadows()`. Kept hard (no softness) for the sharp edge.
    static let noir = LightingPreset(
        ambient: Color(white: 0.015),
        lights: [
            .directional(Color(kelvin: 5800), direction: Vector3(-0.85, -0.3, -0.35), intensity: 1.6,
                         specular: .white),
            .directional(Color(kelvin: 9500), direction: Vector3(0.6, -0.1, 0.5), intensity: 0.05),
        ])

    /// Bright, soft, even daylight from several directions: the studio softbox /
    /// product look. Low contrast, no deep shadows, surfaces read clean. Every light
    /// wraps softly (the softbox diffusion) over a lower ambient than before, so the
    /// shaping comes from the soft lights rather than a flat fill.
    static let studio = LightingPreset(
        ambient: Color(white: 0.22),
        lights: [
            .directional(Color(kelvin: 5600), direction: Vector3(-0.35, -0.6, -0.5), intensity: 0.7,
                         softness: 0.5),
            .directional(Color(kelvin: 5600), direction: Vector3(0.45, -0.45, -0.4), intensity: 0.6,
                         softness: 0.6),
            .directional(Color(kelvin: 6500), direction: Vector3(0.0, -1.0, 0.15), intensity: 0.45,
                         softness: 0.6),
        ])

    /// Cool, dim, blue night light: a high-temperature "moon" key with a faint
    /// colder fill over a deep-blue ambient, both wrapping softly the way moonlight
    /// does. Quiet and atmospheric.
    static let moonlight = LightingPreset(
        ambient: Color(red: 0.04, green: 0.06, blue: 0.11),
        lights: [
            .directional(Color(kelvin: 9500), direction: Vector3(-0.4, -0.7, -0.5), intensity: 0.75,
                         softness: 0.4),
            .directional(Color(kelvin: 13000), direction: Vector3(0.5, -0.2, 0.4), intensity: 0.18,
                         softness: 0.6),
        ])
}
