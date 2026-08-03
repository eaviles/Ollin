import Ollin

/// Light shaping: IES photometric profiles and a projected cookie (gobo).
///
/// A plain point or spot light throws a featureless pool; a real fixture has a
/// *shape* to its throw, measured by its manufacturer and published as an IES
/// file. Loading one onto a light reproduces the fixture:
///
/// - a **downlight** over the left pedestal (a hot center with a spill ring),
/// - a **batwing** street-lamp distribution mid-floor (dark under the pole,
///   bright wings at 40 degrees, the pattern that spaces street lights),
/// - an asymmetric **wallwasher** grazing the back wall (throws forward,
///   cut off behind, so the wall lights and the room doesn't).
///
/// The fourth light is a spot with a `LightCookie`: an image projected through
/// the cone the way a stage gobo or a slide projector works. Here it's a
/// window frame drawn in code, rocking slowly on the light's `roll`, throwing
/// afternoon-window light across the floor. The three `.ies` files ride
/// beside this sketch and load with `IESProfile(resource:in:)`; a profile's
/// intensities are normalized (peak 1), so `intensity` still sets brightness.
@main
final class LightShaping: Sketch {

    // Parse once and keep: a profile is plain data, like a loaded mesh.
    private let downlight = IESProfile(resource: "downlight", in: .module)!
    private let batwing = IESProfile(resource: "batwing", in: .module)!
    private let wallwash = IESProfile(resource: "wallwash", in: .module)!

    // The window gobo, drawn in code: 2×2 white panes behind black mullions,
    // wrapped once (the cookie resamples the image at init, so build it once).
    private let windowGobo: LightCookie = {
        var frame = Image(width: 128, height: 128, color: .black)
        for y in 0..<128 {
            for x in 0..<128 {
                let inFrame = x > 8 && x < 119 && y > 8 && y < 119
                let onMullion = abs(x - 64) < 5 || abs(y - 64) < 5
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    // Flat single-color matcaps for the glowing fixture props (cached; an
    // `Image` keeps its texture).
    private let warmGlow = Image(width: 1, height: 1, color: Color(hue: 0.10, saturation: 0.35, brightness: 1.0))
    private let coolGlow = Image(width: 1, height: 1, color: Color(hue: 0.56, saturation: 0.30, brightness: 1.0))

    override func draw() {
        background(Color(hex: 0x060709))
        ambientLight(Color(white: 0.02))   // a whisper so unlit faces aren't dead black

        cameraShowcase(.sway(amplitude: 0.35, period: 42), target: Vector3(0, -0.4, 0),
                       radius: 12.5, elevation: 0.34, fieldOfView: .pi / 4)

        // --- The shaped lights (per-frame, like every light) ---

        // The downlight hangs low over the left pedestal, straight down (the
        // profile's default axis), pooling a hot disc with its spill ring.
        pointLight(Color(hue: 0.09, saturation: 0.42, brightness: 1.0),
                   at: Vector3(-3.4, 1.2, 0.6), intensity: 1.4, profile: downlight)

        // The batwing hangs mid-floor: almost nothing straight down, wings at
        // 40 degrees, so it draws a wide bright ring instead of a hotspot.
        pointLight(Color(white: 0.95),
                   at: Vector3(0.4, 2.1, 0.2), intensity: 1.1, profile: batwing)

        // The wallwasher stands off the back wall, tilted at it the way a real
        // one aims; the roll turns the profile's forward wing (azimuth 0) into
        // the tilt plane, so the throw climbs the wall and the room stays quiet.
        pointLight(Color(hue: 0.58, saturation: 0.35, brightness: 1.0),
                   at: Vector3(3.2, 2.2, 0.8), intensity: 1.6,
                   profile: wallwash, axis: Vector3(0, -0.55, -1), roll: .pi / 2)

        // The window: a warm spot from high front-left, its gobo projected
        // across the floor, rocking gently on its roll.
        spotLight(Color(hue: 0.09, saturation: 0.38, brightness: 1.0),
                  at: Vector3(-4.6, 3.4, 4.4), direction: Vector3(0.62, -0.62, -0.48),
                  angle: 0.8, penumbra: 0.15, intensity: 1.35,
                  cookie: windowGobo, roll: sin(time * 0.25) * 0.12)

        // --- The set: a matte room that shows throw patterns honestly ---

        withState {
            translate(0, -1.3, 0)
            fill(Color(white: 0.62))
            material(.dielectric(roughness: 0.75))
            drawPlane(width: 18, depth: 14)
        }
        withState {
            translate(0, 1.2, -3.4)
            fill(Color(white: 0.58))
            material(.dielectric(roughness: 0.85))
            drawBox(width: 18, height: 5.0, depth: 0.25)
        }

        // A pedestal + sphere under the downlight, catching its ring.
        withState {
            translate(-3.4, -0.95, 0.6)
            fill(Color(white: 0.8))
            material(.dielectric(roughness: 0.5))
            drawBox(width: 1.1, height: 0.7, depth: 1.1)
        }
        withState {
            translate(-3.4, -0.1, 0.6)
            fill(Color(white: 0.9))
            material(.dielectric(roughness: 0.35))
            drawSphere(radius: 0.5)
        }

        // A low slab mid-floor so the batwing's dark-under-the-pole reads.
        withState {
            translate(0.4, -1.1, 0.2)
            fill(Color(white: 0.75))
            material(.dielectric(roughness: 0.6))
            drawBox(width: 1.6, height: 0.4, depth: 1.6)
        }

        // --- Glowing props marking each fixture ---

        for (position, glow) in [(Vector3(-3.4, 1.9, 0.6), warmGlow),
                                 (Vector3(0.4, 2.1, 0.2), warmGlow),
                                 (Vector3(3.2, 1.7, -1.6), coolGlow)] {
            withState {
                translate(position.x, position.y, position.z)
                fill(.white)
                matcap(glow)
                drawCylinder(radius: 0.16, height: 0.22)
            }
        }
        withState {
            translate(-4.6, 3.4, 4.4)
            fill(.white)
            matcap(warmGlow)
            drawSphere(radius: 0.14)
        }
    }
}
