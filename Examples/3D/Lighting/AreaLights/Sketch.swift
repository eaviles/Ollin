import Ollin

/// Area lights: rect, disk, and tube sources shading a small studio set.
///
/// A point light is an infinitesimal spark; an area light is a *glowing surface*
/// (a softbox, a ring light's face, a neon tube), and that extent is what studio
/// lighting looks like: highlights stretch into the shape's reflection, shading
/// wraps softly, and brightness falls off physically with distance. Three sources
/// light this set:
///
/// - a warm **rect** panel on the left (the softbox key),
/// - a cool **disk** on the right (the fill),
/// - a magenta **tube** lying along the front edge of the floor (the neon accent).
///
/// The front row of spheres climbs in roughness left to right, so the panels'
/// reflections go from sharp little windows to broad sheens; the glossy floor
/// stretches all three into long streaks. `color` × `intensity` is each surface's
/// *radiance*, meaning how bright it looks head-on rather than how much light it
/// puts out in total, which is why the thin tube and the wide softbox run at
/// similar numbers and the tube still dominates the floor it lies close to. The
/// lights themselves are invisible, like every `Light`, so each one also draws a
/// matching glowing prop (a flat single-color matcap ignores the scene lighting,
/// which is exactly an emissive look). The tube's prop is nearly white where its
/// light is pink, which is the rule behind all three: a glowing thing has to
/// out-bright every reflection of itself, or the pool it casts reads as the
/// brighter object and the picture inverts.
///
/// `castShadows()` reaches the area lights too: with no punctual light present, the
/// first rect or disk panel is the caster, and its penumbra comes from the panel's
/// *real extent* rather than a knob. The softbox key breathes between a narrow
/// strip and a broad panel; watch the shadows harden and soften with it, staying
/// crisp where a shape meets the floor and spreading as they fall away (the
/// contact-hardening a real softbox gives). The panel's radiance scales down as it
/// grows, so the pour of light stays steady while only the shadows change. A tube
/// never casts: it glows in every direction, so there is no side to render a
/// shadow from. **Hold the space bar** to lift the shadows and compare. (Under the
/// hood, on a ray-tracing GPU each lit pixel traces visibility rays to points
/// spread over the panel's actual surface, so a wide panel even throws a lopsided
/// penumbra along its long axis; on other GPUs the panel renders a spot-style
/// shadow map from its center whose soft edge is sized from the same extent.)
@main
final class AreaLights: Sketch {

    // Flat single-color matcaps for the glowing light props (cached; an `Image`
    // keeps its texture).
    private let rectGlow = Image(width: 1, height: 1, color: Color(hue: 0.09, saturation: 0.30, brightness: 1.0))
    private let diskGlow = Image(width: 1, height: 1, color: Color(hue: 0.52, saturation: 0.45, brightness: 1.0))
    // The tube's own surface runs near-white where its light is pink: a glowing source
    // has to out-bright every reflection of itself, or the pool on the floor reads as
    // the brighter thing and the picture inverts.
    private let tubeGlow = Image(width: 1, height: 1, color: Color(hue: 0.87, saturation: 0.10, brightness: 1.0))

    override func draw() {
        background(Color(hex: 0x07080C))
        ambientLight(Color(white: 0.03))   // a whisper of fill so unlit backs aren't dead black

        cameraShowcase(.sway(amplitude: 0.4, period: 40), target: Vector3(0, -0.35, 0),
                       radius: 13, elevation: 0.38, fieldOfView: .pi / 4)

        // --- The three area sources (per-frame, like every light) ---

        // The rect panel: standing at the back-left, aimed at the set. Its yaw/pitch
        // also orient the glowing prop below, so the two can't drift apart. Its side
        // breathes between a narrow strip and a broad square; the radiance divides by
        // the area, so the light poured on the set holds steady while the shadow
        // edges do all the talking.
        let rectCenter = Vector3(-3.6, 1.0, -2.4)
        let rectSide = 1.0 + pingPong(over: 12) * 3.0
        let rectYaw = 0.65 + sin(time * 0.3) * 0.12     // a slow sway, like a hand-held bounce
        let rectPitch = 0.28    // positive pitch aims the panel down at the set
        let rectDir = panelDirection(yaw: rectYaw, pitch: rectPitch)
        let rectUp = panelUp(yaw: rectYaw, pitch: rectPitch)
        rectangleLight(Color(hue: 0.09, saturation: 0.30, brightness: 1.0),
                  at: rectCenter, direction: rectDir, width: rectSide, height: rectSide,
                  up: rectUp, intensity: 54 / (rectSide * rectSide))

        // The panel is the caster (the first rect or disk, with no punctual light in
        // the frame). Hold the space bar to lift the shadows and compare.
        if !isKeyDown(" ") { castShadows() }

        // The disk: a cool round fill from the right.
        let diskCenter = Vector3(3.8, 1.3, -1.2)
        let diskYaw = -0.9
        let diskPitch = 0.35
        let diskDir = panelDirection(yaw: diskYaw, pitch: diskPitch)
        diskLight(Color(hue: 0.52, saturation: 0.45, brightness: 1.0),
                  at: diskCenter, direction: diskDir, radius: 1.1, intensity: 4.5)

        // The tube: a thin neon lying along the front edge of the floor. Two things
        // here are about reading the picture rather than about the light. It sits far
        // enough off the floor for its pool to spread, since a brighter tube lying
        // closer clips its pool to flat white; and it is short enough that both ends
        // stay in frame, since a tube running off both sides of the picture reads as a
        // painted stripe, and then so do its pool and its reflected streak.
        let tubeA = Vector3(-3.2, -0.85, 3.0)
        let tubeB = Vector3(3.2, -0.85, 3.0)
        tubeLight(Color(hue: 0.87, saturation: 0.55, brightness: 1.0),
                  from: tubeA, to: tubeB, radius: 0.06, intensity: 9)

        // --- The set ---

        // Glossy floor: the panels' reflections stretch into long streaks.
        withState {
            translate(0, -1.3, 0)
            fill(Color(white: 0.55))
            material(.dielectric(roughness: 0.16))
            drawPlane(width: 18, depth: 14)
        }

        // Front row: one fill, roughness climbing left to right, so the panel
        // reflections go from sharp little windows to broad sheens.
        let roughnesses = [0.05, 0.14, 0.28, 0.45, 0.68]
        for (i, r) in roughnesses.enumerated() {
            withState {
                translate(-4 + Double(i) * 2, -0.5, 1.2)
                fill(Color(white: 0.92))
                material(.dielectric(roughness: r))
                drawSphere(radius: 0.8)
            }
        }

        // A brushed-metal knot center-back, catching all three sources at once.
        withState {
            translate(0, 0.1, -1.6)
            rotateY(time * 0.15)
            fill(Color(hue: 0.08, saturation: 0.25, brightness: 0.85))
            material(.metal(roughness: 0.3))
            drawTorusKnot(radius: 0.9, tube: 0.3)
        }

        // --- Glowing props marking the sources (drawn where each light sits) ---

        withState {
            translate(rectCenter.x, rectCenter.y, rectCenter.z)
            rotateY(rectYaw)
            rotateX(rectPitch)
            fill(.white)
            matcap(rectGlow)
            drawBox(width: rectSide, height: rectSide, depth: 0.06)
        }
        withState {
            translate(diskCenter.x, diskCenter.y, diskCenter.z)
            rotateY(diskYaw)
            // A cylinder's flat face is its local y; the extra quarter turn puts the
            // puck's face on the same axis the disk light faces.
            rotateX(diskPitch + .pi / 2)
            fill(.white)
            matcap(diskGlow)
            drawCylinder(radius: 1.1, height: 0.06)
        }
        withState {
            translate(0, tubeA.y, tubeA.z)
            rotateZ(.pi / 2)
            fill(.white)
            matcap(tubeGlow)
            drawCylinder(radius: 0.07, height: 6.4)
        }
    }

    /// The facing direction of a prop slab drawn with `rotateY(yaw)` then
    /// `rotateX(pitch)`: the composed rotation applied to the slab's local +z,
    /// so the light and its prop share one orientation.
    private func panelDirection(yaw: Double, pitch: Double) -> Vector3 {
        Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
    }

    /// The same composed rotation applied to the slab's local +y (the height axis).
    private func panelUp(yaw: Double, pitch: Double) -> Vector3 {
        Vector3(sin(pitch) * sin(yaw), cos(pitch), sin(pitch) * cos(yaw))
    }
}
