// figure: frame=0
//
// Guide diagram (Chapter 20): the orbiting camera. The eye rides a sphere
// around the target: azimuth turns it around the up axis, elevation tilts it
// above the horizon, radius sets how far away it sits. Drawn with the 3D
// system it explains.
import Ollin

final class Orbit: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        camera(.orbiting(target: Vector3(0, 0.85, 0), radius: 10.4,
                         azimuth: 2.5, elevation: 0.38, fieldOfView: .pi / 4.6))
        ambientLight(Color(white: 0.72))
        directionalLight(Color(white: 0.55), direction: Vector3(-0.4, -1, -0.3))

        // A faint ground grid for bearings.
        fill(ink.withAlpha(0.1))
        for i in -4...4 {
            withState { translate(Double(i), 0, 0); drawBox(width: 0.014, height: 0.014, depth: 8) }
            withState { translate(0, 0, Double(i)); drawBox(width: 8, height: 0.014, depth: 0.014) }
        }

        // The subject being looked at, on the ground at the target.
        withState {
            translate(0, 0.55, 0); rotateY(0.7)
            fill(Color(hex: 0x555555)); specular(0.2); shininess(30)
            drawTorusKnot(radius: 0.42, tube: 0.15, segments: 200, sides: 12)
        }

        // The camera's spherical perch: radius, elevation, azimuth.
        let radius = 3.6, elevation = 0.5, azimuth = 0.8
        let ringR = radius * cos(elevation), ringH = radius * sin(elevation)
        let eye = Vector3(ringR * sin(azimuth), ringH, ringR * cos(azimuth))
        let target = Vector3(0, 0.55, 0)

        // The orbit ring the eye rides at this elevation.
        withState {
            translate(0, ringH, 0)
            fill(ink.withAlpha(0.45))
            drawTorus(radius: ringR, tube: 0.016, segments: 96, sides: 8)
        }

        // The camera: a small body with a lens cone aimed at the target.
        let look = (target - eye).normalized
        withState {
            translate(eye.x, eye.y, eye.z)
            fill(accent); specular(0.25); shininess(40)
            let axis = Vector3.unitY.cross(look)
            let tilt = acos(max(-1, min(1, Vector3.unitY.dot(look))))
            if axis.length > 1e-6 { rotate(tilt, axis: axis.normalized) }
            drawBox(width: 0.34, height: 0.3, depth: 0.34)
            withState { translate(0, 0.26, 0); drawCone(radius: 0.15, height: 0.24) }
        }

        // The line of sight, dashed.
        fill(accent.withAlpha(0.85))
        let span = target - eye
        for i in stride(from: 0.09, to: 0.97, by: 0.08) {
            drawTube([eye + span * i, eye + span * (i + 0.035)], radius: 0.014, sides: 6)
        }

        // Azimuth: a ground arc swinging toward the eye's meridian.
        arc(points: (0...40).map { i in
            let a = 2.2 - Double(i) / 40 * (2.2 - 0.85)
            return Vector3(ringR * sin(a), 0.02, ringR * cos(a))
        })
        // Elevation: the climb from the ground up to the eye.
        arc(points: (0...30).map { i in
            let e = 0.03 + Double(i) / 30 * (elevation - 0.09)
            return Vector3(radius * cos(e) * sin(azimuth), radius * sin(e),
                           radius * cos(e) * cos(azimuth))
        })

        // Labels ride billboards pinned to world points.
        fill(ink); textSize(30)
        label("the target", at: Vector3(0, -0.35, 0.9))
        label("the camera", at: eye + Vector3(0.3, 0.62, 0))
        label("radius", at: (eye + target) * 0.5 + Vector3(0.25, 0.42, 0))
        label("azimuth", at: Vector3(3.75 * sin(1.5), -0.18, 3.75 * cos(1.5)))
        label("elevation", at: Vector3(4.4 * cos(0.24) * sin(azimuth), 4.1 * sin(0.24),
                                       4.4 * cos(0.24) * cos(azimuth)))
        fill(ink.withAlpha(0.6))
        label("the orbit ring", at: Vector3(-ringR * 0.75, ringH + 0.4, -ringR * 0.6))
    }

    func arc(points: [Vector3]) {
        fill(accent)
        drawTube(points, radius: 0.022, sides: 8)
        // An arrowhead at the arc's end, aimed along its final step.
        let tip = points[points.count - 1], back = points[points.count - 2]
        let dir = (tip - back).normalized
        withState {
            translate(tip.x, tip.y, tip.z)
            let axis = Vector3.unitY.cross(dir)
            let tilt = acos(max(-1, min(1, Vector3.unitY.dot(dir))))
            if axis.length > 1e-6 { rotate(tilt, axis: axis.normalized) }
            drawCone(radius: 0.07, height: 0.2)
        }
    }

    func label(_ text: String, at point: Vector3) {
        withBillboard(at: point) {
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
