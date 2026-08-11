import Ollin

/// Motion blur: the cinematic streak a real camera's open shutter leaves.
///
/// Three spheres orbit a still colonnade at very different speeds. Without the
/// blur every frame is an instantaneous exposure: the fast sphere teleports
/// between positions and the motion reads as a strobe. With `motionBlur()` on,
/// each sphere streaks along its own path (the same `withMotion { }` blocks
/// temporal AA uses hand the renderer their exact screen motion), and because
/// the camera keeps drifting, the still columns pick up a gentler smear from
/// the camera's own travel, read straight from the depth buffer with no
/// declaration at all. The shutter dial is the photographic control: 0.5 is
/// the film-standard 180-degree shutter, lower is crisper and more staccato,
/// higher smears further than any real shutter could. Exports carry the blur
/// deterministically, so a video of this sketch streaks exactly like the
/// window.
@main
final class MotionBlur: Sketch {

    @Param(icon: "wind", group: "Shutter")
    var blur = true

    @Param(0...1.5, icon: "camera.shutter.button", group: "Shutter")
    var shutter = 0.5

    override func draw() {
        background(Color(white: 0.05))

        cameraShowcase(.turntable(period: 36), target: Vector3(0, 1.1, 0),
                       radius: 8, elevation: 0.16, fieldOfView: .pi / 3.4)

        ambientLight(Color(white: 0.12))
        directionalLight(.white, direction: Vector3(-0.4, -0.9, -0.5), intensity: 0.9)
        if blur { motionBlur(shutter: shutter) }

        // The colonnade holds still: any streak it carries is the camera's own
        // motion, reprojected from the depth buffer.
        fill(Color(white: 0.55))
        for i in 0..<8 {
            withState {
                let angle = Double(i) / 8 * .tau
                translate(3.1 * cos(angle), 1.0, 3.1 * sin(angle))
                drawCylinder(radius: 0.16, height: 2.0)
            }
        }

        // Three movers at very different paces: the fast one streaks hard, the
        // slow one barely smears, and the middle one sits between. Each declares
        // its motion with `withMotion`, so the streak follows the sphere's own
        // path even while the camera moves the other way.
        let orbits: [(speed: Double, radius: Double, height: Double, size: Double, color: Color)] = [
            (2.6, 2.1, 1.9, 0.30, Color(hex: 0xE0B040)),
            (1.1, 2.6, 1.1, 0.38, Color(hex: 0xC05A3E)),
            (0.35, 1.5, 0.55, 0.46, Color(hex: 0x4E8FB0)),
        ]
        for (i, orbit) in orbits.enumerated() {
            withMotion("sphere-\(i)") {
                withState {
                    fill(orbit.color)
                    rotate(time * orbit.speed, axis: .unitY)
                    translate(orbit.radius, orbit.height, 0)
                    drawSphere(radius: orbit.size)
                }
            }
        }

        withState {
            fill(Color(white: 0.28))
            translate(0, -0.06, 0)
            drawBox(width: 13, height: 0.12, depth: 13)
        }

        drawCaption("motionBlur(shutter: \(String(format: "%.2f", shutter))) \(blur ? "on" : "off")")
    }
}
